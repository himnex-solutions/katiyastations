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
import { CurrentUserPayload } from '../../common/decorators/current-user.decorator';
import { resolveBranchScope } from '../../common/utils/branch-scope.util';
import { buildPaginationMeta } from '../../common/dto/pagination.dto';
import { BranchFilterDto } from '../../common/dto/branch-filter.dto';
import { nextSequenceNumber } from '../../common/utils/sequence.util';

/** Only a manager (or the accountant who owns the books) may reverse settled
 * money — a cashier can take payment but not undo one. */
const REFUND_ROLES = ['branch_manager', 'accountant'];

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
    const where = branchId ? { branchId } : {};

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
    // Was previously hardcoded 'paid' for any non-credit method, even if
    // amountPaid was less than totalAmount — compute it properly so a
    // cashier settling for less than the total (partial tender) is
    // correctly tracked as partial_paid, not silently marked paid.
    const paymentStatus =
      paymentMethod === 'credit' ? 'credit' : amountPaid >= totalAmount ? 'paid' : 'partial_paid';

    const bill = await this.prisma.$transaction(async (tx) => {
      // Allocated atomically from a per-branch counter inside this transaction,
      // so concurrent settles get consecutive numbers — never a duplicate.
      const billNumber = await nextSequenceNumber(tx, session.branchId, 'BILL');
      const invoiceNumber = await nextSequenceNumber(tx, session.branchId, 'INV');

      const created = await tx.bill.create({
        data: {
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
        data: { status: 'billed', totalAmount, closedAt: new Date() },
      });

      await tx.restaurantTable.update({
        where: { id: session.tableId },
        data: { status: 'available', currentSessionId: null, billRequested: false, billRequestedAt: null },
      });

      return created;
    });

    this.realtime.billGenerated(session.branchId, bill);
    this.realtime.tableStatusChanged(session.branchId, session.tableId, { status: 'available' });
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
      throw new ForbiddenException('Only a manager or accountant can void or refund a bill');
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
}
