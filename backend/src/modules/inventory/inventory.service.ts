import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { RealtimeService } from '../websocket/realtime.service';
import { NotificationsService } from '../notifications/notifications.service';
import { CreateInventoryItemDto } from './dto/create-inventory-item.dto';
import { UpdateInventoryItemDto } from './dto/update-inventory-item.dto';
import { AdjustStockDto } from './dto/adjust-stock.dto';
import { CurrentUserPayload } from '../../common/decorators/current-user.decorator';
import { resolveBranchScope } from '../../common/utils/branch-scope.util';
import { buildPaginationMeta } from '../../common/dto/pagination.dto';
import { BranchFilterDto } from '../../common/dto/branch-filter.dto';

@Injectable()
export class InventoryService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: RealtimeService,
    private readonly notifications: NotificationsService,
  ) {}

  async findAll(currentUser: CurrentUserPayload, filter: BranchFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = {
      ...(branchId ? { branchId } : {}),
      ...(filter.search ? { name: { contains: filter.search, mode: 'insensitive' as const } } : {}),
    };

    const [items, total] = await Promise.all([
      this.prisma.inventoryItem.findMany({ where, orderBy: { name: 'asc' }, skip: filter.skip, take: filter.take }),
      this.prisma.inventoryItem.count({ where }),
    ]);

    return { data: items, meta: buildPaginationMeta(total, filter.page ?? 1, filter.take) };
  }

  async findOne(id: string) {
    const item = await this.prisma.inventoryItem.findUnique({ where: { id } });
    if (!item) throw new NotFoundException('Inventory item not found');
    return item;
  }

  create(dto: CreateInventoryItemDto) {
    return this.prisma.inventoryItem.create({ data: dto });
  }

  async update(id: string, dto: UpdateInventoryItemDto) {
    await this.findOne(id);
    return this.prisma.inventoryItem.update({ where: { id }, data: dto });
  }

  async remove(id: string) {
    await this.findOne(id);
    await this.prisma.inventoryItem.delete({ where: { id } });
    return { deleted: true };
  }

  async movements(currentUser: CurrentUserPayload, filter: BranchFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = branchId ? { branchId } : {};

    const [items, total] = await Promise.all([
      this.prisma.stockMovement.findMany({
        where,
        include: { item: true },
        orderBy: { createdAt: 'desc' },
        skip: filter.skip,
        take: filter.take,
      }),
      this.prisma.stockMovement.count({ where }),
    ]);

    return { data: items, meta: buildPaginationMeta(total, filter.page ?? 1, filter.take) };
  }

  async adjustStock(id: string, dto: AdjustStockDto) {
    const item = await this.findOne(id);
    const delta = dto.type === 'in' ? dto.quantity : -dto.quantity;
    const newStock = Number(item.currentStock) + delta;

    const [updated] = await this.prisma.$transaction([
      this.prisma.inventoryItem.update({ where: { id }, data: { currentStock: newStock } }),
      this.prisma.stockMovement.create({
        data: {
          branchId: item.branchId,
          itemId: item.id,
          type: dto.type,
          quantity: dto.quantity,
          reason: dto.reason,
        },
      }),
    ]);

    if (Number(updated.currentStock) <= Number(updated.reorderLevel)) {
      this.realtime.lowStock(item.branchId, updated);
      await this.notifications.lowStock(updated);
    }

    return updated;
  }
}
