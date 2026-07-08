import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { CreateCreditDto } from './dto/create-credit.dto';
import { SettleCreditDto } from './dto/settle-credit.dto';
import { CurrentUserPayload } from '../../common/decorators/current-user.decorator';
import { resolveBranchScope } from '../../common/utils/branch-scope.util';
import { buildPaginationMeta } from '../../common/dto/pagination.dto';
import { BranchFilterDto } from '../../common/dto/branch-filter.dto';

@Injectable()
export class CreditService {
  constructor(private readonly prisma: PrismaService) {}

  async findAll(currentUser: CurrentUserPayload, filter: BranchFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = branchId ? { branchId } : {};

    const [items, total] = await Promise.all([
      this.prisma.creditRecord.findMany({
        where,
        include: { bill: true },
        orderBy: { createdAt: 'desc' },
        skip: filter.skip,
        take: filter.take,
      }),
      this.prisma.creditRecord.count({ where }),
    ]);

    return { data: items, meta: buildPaginationMeta(total, filter.page ?? 1, filter.take) };
  }

  async findOne(id: string) {
    const record = await this.prisma.creditRecord.findUnique({ where: { id }, include: { bill: true } });
    if (!record) throw new NotFoundException('Credit record not found');
    return record;
  }

  async create(dto: CreateCreditDto) {
    const bill = await this.prisma.bill.findUnique({ where: { id: dto.billId } });
    if (!bill) throw new NotFoundException('Bill not found');

    return this.prisma.creditRecord.create({
      data: {
        branchId: bill.branchId,
        billId: dto.billId,
        customerId: dto.customerId,
        creditAmount: dto.amount,
        dueDate: dto.dueDate ? new Date(dto.dueDate) : undefined,
      },
    });
  }

  /** "Collect Payment": adds to paid_amount (never mutates the fixed credit_amount). */
  async settle(id: string, dto: SettleCreditDto) {
    const record = await this.findOne(id);
    if (record.status === 'paid') {
      throw new BadRequestException('This credit record is already fully paid');
    }

    const creditAmount = Number(record.creditAmount);
    const currentPaid = Number(record.paidAmount);
    const outstanding = creditAmount - currentPaid;
    const collected = dto.amount ?? outstanding;
    if (collected <= 0) throw new BadRequestException('Settlement amount must be greater than zero');
    if (collected > outstanding) {
      throw new BadRequestException('Settlement amount cannot exceed the outstanding balance');
    }

    const newPaid = currentPaid + collected;
    return this.prisma.creditRecord.update({
      where: { id },
      data: {
        paidAmount: newPaid,
        status: newPaid >= creditAmount ? 'paid' : 'partial_paid',
      },
    });
  }
}
