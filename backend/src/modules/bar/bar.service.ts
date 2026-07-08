import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { RealtimeService } from '../websocket/realtime.service';
import { CreateBarStockDto } from './dto/create-bar-stock.dto';
import { UpdateBarStockDto } from './dto/update-bar-stock.dto';
import { DispenseDto } from './dto/dispense.dto';
import { CurrentUserPayload } from '../../common/decorators/current-user.decorator';
import { resolveBranchScope } from '../../common/utils/branch-scope.util';
import { buildPaginationMeta } from '../../common/dto/pagination.dto';
import { BranchFilterDto } from '../../common/dto/branch-filter.dto';

@Injectable()
export class BarService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: RealtimeService,
  ) {}

  async findAllStock(currentUser: CurrentUserPayload, filter: BranchFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = branchId ? { branchId } : {};

    const [items, total] = await Promise.all([
      this.prisma.barStock.findMany({ where, orderBy: { name: 'asc' }, skip: filter.skip, take: filter.take }),
      this.prisma.barStock.count({ where }),
    ]);

    return { data: items, meta: buildPaginationMeta(total, filter.page ?? 1, filter.take) };
  }

  async findStock(id: string) {
    const stock = await this.prisma.barStock.findUnique({ where: { id } });
    if (!stock) throw new NotFoundException('Bar stock item not found');
    return stock;
  }

  createStock(dto: CreateBarStockDto) {
    return this.prisma.barStock.create({ data: dto });
  }

  async updateStock(id: string, dto: UpdateBarStockDto) {
    await this.findStock(id);
    return this.prisma.barStock.update({ where: { id }, data: dto });
  }

  async removeStock(id: string) {
    await this.findStock(id);
    await this.prisma.barStock.delete({ where: { id } });
    return { deleted: true };
  }

  async transactions(currentUser: CurrentUserPayload, filter: BranchFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = branchId ? { branchId } : {};

    const [items, total] = await Promise.all([
      this.prisma.barTransaction.findMany({
        where,
        include: { item: true },
        orderBy: { createdAt: 'desc' },
        skip: filter.skip,
        take: filter.take,
      }),
      this.prisma.barTransaction.count({ where }),
    ]);

    return { data: items, meta: buildPaginationMeta(total, filter.page ?? 1, filter.take) };
  }

  async dispense(id: string, dto: DispenseDto) {
    const stock = await this.findStock(id);
    const bottleFraction = (dto.pegs * Number(stock.pegsMl)) / Number(stock.bottleCapacityMl);
    const type = dto.type ?? 'out';
    const delta = type === 'in' ? bottleFraction : -bottleFraction;
    const newBottles = Number(stock.currentBottles) + delta;

    const [updated] = await this.prisma.$transaction([
      this.prisma.barStock.update({ where: { id }, data: { currentBottles: newBottles } }),
      this.prisma.barTransaction.create({
        data: {
          branchId: stock.branchId,
          itemId: stock.id,
          type,
          quantity: bottleFraction,
        },
      }),
    ]);

    if (Number(updated.currentBottles) <= 1) {
      this.realtime.lowStock(stock.branchId, updated);
    }

    return updated;
  }
}
