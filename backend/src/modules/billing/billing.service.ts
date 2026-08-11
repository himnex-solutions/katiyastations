import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { RealtimeService } from '../websocket/realtime.service';
import { AuditLogsService } from '../audit-logs/audit-logs.service';
import { KotsService } from '../kots/kots.service';
import { GenerateBillDto } from './dto/generate-bill.dto';
import { UpdateBillDto } from './dto/update-bill.dto';
import { AddPaymentDto } from './dto/add-payment.dto';
import { RefundBillDto } from './dto/refund-bill.dto';
import { PaymentPurgeRangeDto, PurgePaymentsDto } from './dto/purge-payments.dto';
import { CurrentUserPayload } from '../../common/decorators/current-user.decorator';
import { resolveBranchScope } from '../../common/utils/branch-scope.util';
import { buildPaginationMeta } from '../../common/dto/pagination.dto';
import { BranchFilterDto } from '../../common/dto/branch-filter.dto';
import { nextSequenceNumber } from '../../common/utils/sequence.util';

/** Who may reverse settled money. The cashier owns the till at the counter, so
 * they can void/refund a bill they just settled — alongside managers and the
 * accountant who owns the books. */
const REFUND_ROLES = ['branch_manager', 'accountant', 'cashier'];

/**
 * The ONLY bill state a purge may remove: settled in full, in cash or card, and
 * never reversed.
 *
 * Everything else is deliberately untouchable. 'credit' is money still on the
 * books — and because CreditRecord rows exist only for credit sales, excluding
 * this status is also what guarantees no credit record is ever cascaded away by
 * a purge. 'partial_paid' is a balance someone still owes; 'refunded' and
 * 'voided' are the audit trail of money given back, which is exactly the
 * history a deletion tool must not be able to quietly remove.
 */
const PURGEABLE_PAYMENT_STATUS = 'paid';

@Injectable()
export class BillingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: RealtimeService,
    private readonly auditLogs: AuditLogsService,
    private readonly kots: KotsService,
  ) {}

  async findAll(currentUser: CurrentUserPayload, filter: BranchFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where: any = branchId ? { branchId } : {};

    // Optional date window (payment history for a past day). Filtering here — on
    // the server, over ALL bills — instead of on the client's capped recent page
    // is what lets an older day's bills (and their revenue) surface at all.
    if (filter.startDate || filter.endDate) {
      where.createdAt = {};
      if (filter.startDate) where.createdAt.gte = new Date(filter.startDate);
      if (filter.endDate) where.createdAt.lt = new Date(filter.endDate);
    }

    const [items, total] = await Promise.all([
      this.prisma.bill.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: filter.skip,
        take: filter.take,
      }),
      this.prisma.bill.count({ where }),
    ]);

    return { data: items, meta: buildPaginationMeta(total, filter.page ?? 1, filter.take) };
  }

  async findOne(id: string) {
    const bill = await this.prisma.bill.findUnique({ where: { id } });
    if (!bill) throw new NotFoundException('Bill not found');
    return bill;
  }

  /**
   * "Settle Bill": creates the Bill (and a CreditRecord for credit sales),
   * then closes the session and frees the table — all as one atomic action,
   * matching the cashier screen's single "Settle Bill" button.
   */
  async generate(sessionId: string, currentUser: CurrentUserPayload, dto: GenerateBillDto) {
    // Idempotent replay of an offline-settled bill: it carries its own client
    // id, so a retried sync returns the bill already stored rather than billing
    // the session twice. Checked before the "already billed" guard so replaying
    // the SAME bill still succeeds even though the session is now billed.
    if (dto.id) {
      const existing = await this.prisma.bill.findUnique({ where: { id: dto.id } });
      if (existing) return existing;
    }

    const session = await this.prisma.tableSession.findUnique({ where: { id: sessionId } });
    if (!session) throw new NotFoundException('Session not found');
    if (session.status === 'billed') {
      throw new BadRequestException('This session has already been billed');
    }

    const branch = await this.prisma.branch.findUniqueOrThrow({ where: { id: session.branchId } });
    const cashier = await this.prisma.user.findUnique({ where: { id: currentUser.userId } });

    const kotItems = await this.prisma.kotItem.findMany({
      where: { kot: { sessionId }, status: { not: 'cancelled' } },
    });

    const subTotal = kotItems.reduce(
      (sum, item) => sum + Number(item.unitPrice) * item.quantity,
      0,
    );
    const discount = dto.discount ?? 0;

    // Matches the cashier screen's exact math: service charge is on the
    // full subtotal (before discount), discount is subtracted after, and
    // VAT applies to the post-service, post-discount amount. Both are
    // opt-in per bill (cashier toggles), off by default.
    const serviceCharge = dto.applyServiceCharge
      ? (subTotal * Number(branch.serviceChargeRate)) / 100
      : 0;
    const afterService = subTotal + serviceCharge - discount;
    const vatAmount = dto.applyVat ? (afterService * Number(branch.vatRate)) / 100 : 0;
    const totalAmount = afterService + vatAmount;
    const paymentMethod = dto.paymentMethod ?? 'cash';
    const amountPaid = dto.amountPaid ?? totalAmount;
    // A non-credit settle is 'paid' when the tender covers the total. The 0.01
    // tolerance absorbs client-side rounding (e.g. a service-charge computed to
    // a fraction of a paisa) so a full payment is never mis-flagged
    // 'partial_paid'. A genuinely short cash tender still records as partial.
    const paymentStatus =
      paymentMethod === 'credit'
        ? 'credit'
        : amountPaid >= totalAmount - 0.01
          ? 'paid'
          : 'partial_paid';

    const bill = await this.prisma.$transaction(async (tx) => {
      // Allocated atomically from a per-branch counter inside this transaction,
      // so concurrent settles get consecutive numbers — never a duplicate.
      const billNumber = await nextSequenceNumber(tx, session.branchId, 'BILL');
      const invoiceNumber = await nextSequenceNumber(tx, session.branchId, 'INV');

      const created = await tx.bill.create({
        data: {
          id: dto.id, // undefined → Prisma applies @default(uuid())
          // Offline bills carry the real sale time so reports credit the right day.
          ...(dto.soldAt ? { createdAt: new Date(dto.soldAt) } : {}),
          branchId: session.branchId,
          sessionId: session.id,
          tableId: session.tableId,
          billNumber,
          invoiceNumber,
          subTotal,
          discount,
          serviceCharge,
          vatAmount,
          totalAmount,
          amountPaid,
          changeAmount: paymentMethod === 'cash' ? Math.max(0, amountPaid - totalAmount) : 0,
          paymentMethod,
          paymentStatus,
          cashierId: currentUser.userId,
          cashierName: cashier?.fullName,
          customerName: dto.customerName,
          customerPhone: dto.customerPhone,
        },
      });

      // Payment is the single source of truth for "how much has been
      // paid" — record the initial tender captured at settle time here so
      // addPayment() (for partial/multi-tender top-ups) can just sum this
      // table rather than reconciling against Bill.amountPaid separately.
      if (amountPaid > 0 && paymentMethod !== 'credit') {
        await tx.payment.create({
          data: {
            billId: created.id,
            // Same reason as the bill above: an offline settle replays on
            // reconnect, so without this the payment is timestamped when the
            // internet came back rather than when the guest actually paid.
            ...(dto.soldAt ? { createdAt: new Date(dto.soldAt) } : {}),
            method: paymentMethod,
            amount: amountPaid,
            receivedById: currentUser.userId,
          },
        });
      }

      if (paymentMethod === 'credit') {
        await tx.creditRecord.create({
          data: {
            branchId: session.branchId,
            billId: created.id,
            customerId: session.customerId ?? session.id, // no separate customer record required for walk-in credit
            customerName: dto.customerName ?? 'Unknown',
            customerPhone: dto.customerPhone,
            creditAmount: totalAmount,
            paidAmount: 0,
            status: 'pending',
          },
        });
      }

      await tx.tableSession.update({
        where: { id: session.id },
        data: {
          status: 'billed',
          totalAmount,
          // An offline settle closed the table when the guest left, not when
          // the queue drained — otherwise table-turnaround reports read as if
          // every offline session ran until the connection returned.
          closedAt: dto.soldAt ? new Date(dto.soldAt) : new Date(),
        },
      });

      // Online / call-in orders have no table to free.
      if (session.tableId) {
        await tx.restaurantTable.update({
          where: { id: session.tableId },
          data: { status: 'available', currentSessionId: null, billRequested: false, billRequestedAt: null },
        });
      }

      return created;
    });

    this.realtime.billGenerated(session.branchId, bill);
    if (session.tableId) {
      this.realtime.tableStatusChanged(session.branchId, session.tableId, { status: 'available' });
    }
    this.auditLogs.record({
      branchId: session.branchId,
      userId: currentUser.userId,
      action: 'payment',
      tableName: 'bills',
      rowId: bill.id,
      newValues: { totalAmount, amountPaid, paymentMethod, paymentStatus },
    });
    return bill;
  }

  /** Adds an extra tender to an existing bill — covering the rest of a
   * partial payment, or splitting one bill across multiple methods. */
  async addPayment(billId: string, currentUser: CurrentUserPayload, dto: AddPaymentDto) {
    const bill = await this.findOne(billId);
    if (bill.paymentStatus === 'paid') {
      throw new BadRequestException('This bill is already fully paid');
    }

    await this.prisma.payment.create({
      data: {
        billId,
        method: dto.method,
        amount: dto.amount,
        referenceNumber: dto.referenceNumber,
        device: dto.device,
        receivedById: currentUser.userId,
      },
    });

    const payments = await this.prisma.payment.findMany({ where: { billId } });
    const totalPaid = payments.reduce((sum, p) => sum + Number(p.amount), 0);
    const paymentStatus = totalPaid >= Number(bill.totalAmount) ? 'paid' : 'partial_paid';

    const updated = await this.prisma.bill.update({
      where: { id: billId },
      data: {
        amountPaid: totalPaid,
        paymentStatus,
        changeAmount: Math.max(0, totalPaid - Number(bill.totalAmount)),
      },
    });

    if (paymentStatus === 'paid') {
      this.realtime.billPaid(bill.branchId, updated);
    }
    this.auditLogs.record({
      branchId: bill.branchId,
      userId: currentUser.userId,
      action: 'payment_added',
      tableName: 'bills',
      rowId: billId,
      newValues: { method: dto.method, amount: dto.amount, totalPaid, paymentStatus },
    });

    return updated;
  }

  /**
   * Reverses a settled bill — a manager-authorised void (raised in error) or
   * refund (money returned). One atomic action: records who/why on the bill,
   * flips the payment status, writes a negative "refund" Payment so the tender
   * ledger nets to zero, cancels any open credit record, and restocks the
   * recipe ingredients + bar pegs that were deducted at order time.
   */
  async refund(billId: string, currentUser: CurrentUserPayload, dto: RefundBillDto) {
    if (!REFUND_ROLES.includes(currentUser.role)) {
      throw new ForbiddenException('You do not have permission to void or refund a bill');
    }

    const bill = await this.findOne(billId);
    if (bill.paymentStatus === 'refunded' || bill.paymentStatus === 'voided') {
      throw new BadRequestException('This bill has already been reversed');
    }

    const actor = await this.prisma.user.findUnique({ where: { id: currentUser.userId } });
    const newStatus = dto.type === 'void' ? 'voided' : 'refunded';

    // Reverse only money that was actually tendered — i.e. the sum of real
    // Payment rows. A pure credit bill has none (the cash was never collected),
    // so nothing is refunded there beyond cancelling the credit record.
    const payments = await this.prisma.payment.findMany({ where: { billId } });
    const tendered = payments.reduce((sum, p) => sum + Number(p.amount), 0);

    const updated = await this.prisma.$transaction(async (tx) => {
      // Negative tender so payment history / shift totals net the money back out.
      if (tendered > 0) {
        await tx.payment.create({
          data: {
            billId,
            method: dto.refundMethod ?? bill.paymentMethod,
            amount: -tendered,
            referenceNumber: `${dto.type.toUpperCase()}: ${dto.reason}`.slice(0, 190),
            receivedById: currentUser.userId,
          },
        });
      }

      // Cancel any still-open credit raised by this bill.
      await tx.creditRecord.updateMany({
        where: { billId, status: { notIn: ['paid'] } },
        data: { status: 'cancelled' },
      });

      return tx.bill.update({
        where: { id: billId },
        data: {
          paymentStatus: newStatus,
          refundType: dto.type,
          refundReason: dto.reason,
          refundedById: currentUser.userId,
          refundedByName: actor?.fullName,
          refundedAt: new Date(),
        },
      });
    });

    // Restock outside the bill transaction: each item's restore is already its
    // own transaction (in kots.service), and a missing recipe/bar link must not
    // roll back a completed refund.
    if (bill.sessionId) {
      await this.kots.restockSessionItems(
        bill.sessionId,
        bill.branchId,
        `${dto.type} bill ${bill.billNumber}`,
      );
    }

    this.realtime.billRefunded(bill.branchId, updated);
    this.auditLogs.record({
      branchId: bill.branchId,
      userId: currentUser.userId,
      action: dto.type === 'void' ? 'bill_voided' : 'bill_refunded',
      tableName: 'bills',
      rowId: billId,
      oldValues: { paymentStatus: bill.paymentStatus, tendered },
      newValues: { paymentStatus: newStatus, reason: dto.reason },
    });

    return updated;
  }

  async update(id: string, dto: UpdateBillDto) {
    const bill = await this.findOne(id);
    const updated = await this.prisma.bill.update({ where: { id }, data: dto });
    if (dto.paymentStatus === 'paid') {
      this.realtime.billPaid(bill.branchId, updated);
    }
    return updated;
  }

  paymentHistory(currentUser: CurrentUserPayload, filter: BranchFilterDto) {
    return this.findAll(currentUser, filter);
  }

  // ── Purging payment records ──────────────────────────────────
  //
  // Managers and the super admin can permanently remove a window of settled
  // bills. This is deliberately irreversible: the caller asked for the records
  // to be gone, not hidden. What survives is an audit row holding the header of
  // every bill removed, so "who cleared the 12th, and what was in it" still has
  // an answer months later.

  /**
   * Resolves the branch and window a purge applies to, refusing anything
   * ambiguous. A super admin's token carries no branch, so an unscoped call
   * would otherwise mean "every branch at once" — never an implied default for
   * something that deletes settled money.
   *
   * Returns two filters: [window] is everything in range, [where] is the subset
   * that may actually be deleted. Both are needed so the preview can say what
   * is being kept and why.
   */
  private purgeScope(currentUser: CurrentUserPayload, dto: PaymentPurgeRangeDto) {
    const branchId = resolveBranchScope(currentUser, dto.branchId);
    if (!branchId) {
      throw new BadRequestException(
        'Choose a branch. A purge is never applied to every branch at once.',
      );
    }

    const start = new Date(dto.startDate);
    const end = new Date(dto.endDate);
    if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) {
      throw new BadRequestException('That date range could not be read.');
    }
    if (end <= start) {
      throw new BadRequestException('The end of the range must come after the start.');
    }

    const window = { branchId, createdAt: { gte: start, lt: end } };

    return {
      branchId,
      start,
      end,
      window,
      where: { ...window, paymentStatus: PURGEABLE_PAYMENT_STATUS },
    };
  }

  /**
   * Everything the caller is about to destroy, counted and totalled, so the
   * confirmation can state it in words before a single row is removed. Reads
   * only — safe to call as often as the date picker changes.
   */
  async previewPaymentPurge(currentUser: CurrentUserPayload, dto: PaymentPurgeRangeDto) {
    const { branchId, start, end, window, where } = this.purgeScope(currentUser, dto);

    const [bills, totals, taxInvoices, payments, billsInRange, keptByStatus] =
      await Promise.all([
        this.prisma.bill.count({ where }),
        this.prisma.bill.aggregate({ where, _sum: { totalAmount: true } }),
        this.prisma.bill.count({ where: { ...where, invoiceNumber: { not: null } } }),
        this.prisma.payment.count({ where: { bill: where } }),
        this.prisma.bill.count({ where: window }),
        // What the filter is holding back, broken down so the manager can see
        // WHY 40 bills in the range became 31 deletions instead of guessing
        // that something went wrong.
        this.prisma.bill.groupBy({
          by: ['paymentStatus'],
          where: { ...window, paymentStatus: { not: PURGEABLE_PAYMENT_STATUS } },
          _count: { _all: true },
        }),
      ]);

    return {
      branchId,
      startDate: start.toISOString(),
      endDate: end.toISOString(),
      bills,
      payments,
      taxInvoices,
      totalAmount: totals._sum.totalAmount?.toString() ?? '0',
      billsInRange,
      kept: keptByStatus.map((row) => ({
        status: row.paymentStatus,
        count: row._count._all,
      })),
    };
  }

  /**
   * Permanently deletes the FULLY-PAID bills in a window, along with the
   * payment rows the database cascades with them. Credit, part-paid, refunded
   * and voided bills in the same window are left exactly where they are — see
   * [PURGEABLE_PAYMENT_STATUS].
   */
  async purgePayments(currentUser: CurrentUserPayload, dto: PurgePaymentsDto) {
    const { branchId, start, end, where } = this.purgeScope(currentUser, dto);

    // Read the headers before deleting: once the rows are gone this is the only
    // description of them that exists anywhere.
    const bills = await this.prisma.bill.findMany({
      where,
      select: {
        id: true,
        billNumber: true,
        invoiceNumber: true,
        totalAmount: true,
        amountPaid: true,
        paymentMethod: true,
        paymentStatus: true,
        cashierName: true,
        customerName: true,
        createdAt: true,
      },
      orderBy: { createdAt: 'asc' },
    });

    if (bills.length === 0) {
      throw new NotFoundException(
        'There are no fully-paid payment records in that range. Credit, '
        + 'part-paid, refunded and voided bills are never removed.',
      );
    }

    const billIds = bills.map((bill) => bill.id);
    const payments = await this.prisma.payment.count({
      where: { billId: { in: billIds } },
    });

    const { count } = await this.prisma.bill.deleteMany({ where });

    this.auditLogs.record({
      branchId,
      userId: currentUser.userId,
      action: 'payment_records_purged',
      tableName: 'bills',
      oldValues: {
        startDate: start.toISOString(),
        endDate: end.toISOString(),
        paymentStatus: PURGEABLE_PAYMENT_STATUS,
        bills: count,
        payments,
        // Every header, not a sample: a purge is precisely the case where
        // "which ones?" is the question, and a bill header is a few hundred
        // bytes. Amounts are stringified because Prisma Decimal does not
        // survive JSON.stringify as a number.
        removed: bills.map((bill) => ({
          ...bill,
          totalAmount: bill.totalAmount.toString(),
          amountPaid: bill.amountPaid.toString(),
          createdAt: bill.createdAt.toISOString(),
        })),
      },
    });

    // Any till or report still showing this window is now wrong.
    this.realtime.dataChanged(branchId, 'bills', 'purged');

    return {
      deleted: count,
      payments,
      branchId,
      startDate: start.toISOString(),
      endDate: end.toISOString(),
    };
  }
}
