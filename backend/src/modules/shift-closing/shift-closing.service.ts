import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { RealtimeService } from '../websocket/realtime.service';
import { CreateShiftClosingDto } from './dto/create-shift-closing.dto';
import { CurrentUserPayload } from '../../common/decorators/current-user.decorator';
import { resolveBranchScope } from '../../common/utils/branch-scope.util';
import { BranchFilterDto } from '../../common/dto/branch-filter.dto';
import { buildPaginationMeta } from '../../common/dto/pagination.dto';

@Injectable()
export class ShiftClosingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: RealtimeService,
  ) {}

  async findAll(currentUser: CurrentUserPayload, filter: BranchFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = branchId ? { branchId } : {};

    const [items, total] = await Promise.all([
      this.prisma.shiftClosing.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: filter.skip,
        take: filter.take,
      }),
      this.prisma.shiftClosing.count({ where }),
    ]);

    return { data: items, meta: buildPaginationMeta(total, filter.page ?? 1, filter.take) };
  }

  async findOne(id: string) {
    const shift = await this.prisma.shiftClosing.findUnique({ where: { id } });
    if (!shift) throw new NotFoundException('Shift closing record not found');
    return shift;
  }

  /** Aggregates today's bills into the cashier's end-of-day summary. */
  async todaySummary(currentUser: CurrentUserPayload, requestedBranchId?: string) {
    const branchId = resolveBranchScope(currentUser, requestedBranchId);
    const now = new Date();
    const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const endOfDay = new Date(startOfDay.getTime() + 24 * 60 * 60 * 1000);

    const bills = await this.prisma.bill.findMany({
      where: {
        ...(branchId ? { branchId } : {}),
        createdAt: { gte: startOfDay, lt: endOfDay },
      },
    });

    const summary = {
      cash: 0,
      card: 0,
      esewa: 0,
      khalti: 0,
      fonepay: 0,
      credit: 0,
      refund: 0,
      totalRevenue: 0,
      totalVat: 0,
      totalDiscount: 0,
      totalServiceCharge: 0,
      billCount: 0,
      netRevenue: 0,
    };

    for (const bill of bills) {
      const amount = Number(bill.totalAmount);

      if (bill.paymentStatus === 'refunded') {
        summary.refund += amount;
        continue;
      }

      summary.totalRevenue += amount;
      summary.totalVat += Number(bill.vatAmount);
      summary.totalDiscount += Number(bill.discount);
      summary.totalServiceCharge += Number(bill.serviceCharge);
      summary.billCount++;

      if (bill.paymentMethod in summary) {
        (summary as any)[bill.paymentMethod] += amount;
      }
    }

    summary.netRevenue = summary.totalRevenue - summary.refund;
    return summary;
  }

  create(currentUser: CurrentUserPayload, dto: CreateShiftClosingDto) {
    return this.prisma.shiftClosing.create({
      data: {
        ...dto,
        cashierId: currentUser.userId,
        cashierName: dto.cashierName ?? currentUser.email,
      },
    });
  }

  private async setStatus(id: string, status: 'approved' | 'rejected') {
    const shift = await this.findOne(id);
    if (shift.status !== 'pending_approval') {
      throw new BadRequestException('This shift closing has already been reviewed');
    }

    const updated = await this.prisma.shiftClosing.update({ where: { id }, data: { status } });
    if (status === 'approved') {
      this.realtime.shiftApproved(shift.branchId, updated);
    } else {
      this.realtime.shiftClosed(shift.branchId, updated);
    }
    return updated;
  }

  approve(id: string) {
    return this.setStatus(id, 'approved');
  }

  reject(id: string) {
    return this.setStatus(id, 'rejected');
  }
}
