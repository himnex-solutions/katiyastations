import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { RealtimeService } from '../websocket/realtime.service';
import { AuditLogsService } from '../audit-logs/audit-logs.service';
import { NotificationsService } from '../notifications/notifications.service';
import { CreateKotDto } from './dto/create-kot.dto';
import { UpdateStatusDto } from './dto/update-status.dto';
import { UpdateItemQuantityDto } from './dto/update-item-quantity.dto';
import { FindKotsDto } from './dto/find-kots.dto';
import { ReturnItemDto } from './dto/return-item.dto';
import { CurrentUserPayload } from '../../common/decorators/current-user.decorator';
import { resolveBranchScope } from '../../common/utils/branch-scope.util';
import { generateSequenceNumber } from '../../common/utils/sequence.util';

const MANAGER_ROLES = ['branch_manager', 'super_admin'];

const KOT_INCLUDE = {
  items: true,
  waiter: { select: { fullName: true } },
  table: { select: { tableNumber: true } },
} as const;

/** Flattens the Kot response to match Kot.fromJson in the Flutter client. */
function toKotResponse(kot: any) {
  const { waiter, table, ...rest } = kot;
  return { ...rest, waiterName: waiter?.fullName ?? null, tableNumber: table?.tableNumber ?? null };
}

@Injectable()
export class KotsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: RealtimeService,
    private readonly auditLogs: AuditLogsService,
    private readonly notifications: NotificationsService,
  ) {}

  async findAll(currentUser: CurrentUserPayload, filter: FindKotsDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const statuses = filter.status?.split(',').map((s) => s.trim()).filter(Boolean);

    const kots = await this.prisma.kot.findMany({
      where: {
        ...(branchId ? { branchId } : {}),
        ...(statuses?.length ? { status: { in: statuses } } : {}),
      },
      include: KOT_INCLUDE,
      orderBy: { createdAt: 'asc' },
      take: filter.take,
      skip: filter.skip,
    });
    return kots.map(toKotResponse);
  }

  async findOne(id: string) {
    const kot = await this.prisma.kot.findUnique({ where: { id }, include: KOT_INCLUDE });
    if (!kot) throw new NotFoundException('KOT not found');
    return kot;
  }

  async findOneResponse(id: string) {
    return toKotResponse(await this.findOne(id));
  }

  async items(kotId: string) {
    await this.findOne(kotId);
    return this.prisma.kotItem.findMany({ where: { kotId }, orderBy: { createdAt: 'asc' } });
  }

  async bySession(sessionId: string) {
    const kots = await this.prisma.kot.findMany({
      where: { sessionId },
      include: KOT_INCLUDE,
      orderBy: { createdAt: 'asc' },
    });
    return kots.map(toKotResponse);
  }

  async create(currentUser: CurrentUserPayload, dto: CreateKotDto) {
    const session = await this.prisma.tableSession.findUnique({ where: { id: dto.sessionId } });
    if (!session) throw new NotFoundException('Session not found');

    const menuItems = await this.prisma.menuItem.findMany({
      where: { id: { in: dto.items.map((i) => i.menuItemId) } },
    });
    const priceById = new Map(menuItems.map((m) => [m.id, m.price]));

    const kot = await this.prisma.kot.create({
      data: {
        sessionId: session.id,
        branchId: session.branchId,
        tableId: session.tableId,
        kotNumber: generateSequenceNumber('KOT'),
        waiterId: dto.waiterId ?? currentUser.userId,
        itemsCount: dto.items.length,
        items: {
          create: dto.items.map((item) => ({
            menuItemId: item.menuItemId,
            name: item.name,
            quantity: item.quantity,
            unitPrice: priceById.get(item.menuItemId) ?? 0,
            note: item.note,
          })),
        },
      },
      include: KOT_INCLUDE,
    });

    await this.recalculateSessionTotal(session.id);
    await this.deductStockForItems(session.branchId, kot.kotNumber, dto.items);
    const response = toKotResponse(kot);
    this.realtime.kotNew(session.branchId, response);
    this.auditLogs.record({
      branchId: session.branchId,
      userId: currentUser.userId,
      action: 'item_added',
      tableName: 'table_sessions',
      rowId: session.id,
      newValues: { kotId: kot.id, kotNumber: kot.kotNumber, items: dto.items },
    });
    return response;
  }

  async updateStatus(id: string, dto: UpdateStatusDto, currentUser?: CurrentUserPayload) {
    const kot = await this.findOne(id);
    const becomingReady = dto.status === 'ready' && !kot.readyAt;
    const updated = await this.prisma.kot.update({
      where: { id },
      data: {
        status: dto.status,
        ...(becomingReady ? { readyAt: new Date(), preparedById: currentUser?.userId } : {}),
      },
    });

    // Bulk-progress child items alongside the parent ticket for the common
    // statuses; individual items can still be advanced independently.
    if (['preparing', 'ready', 'served', 'cancelled'].includes(dto.status)) {
      await this.prisma.kotItem.updateMany({
        where: { kotId: id, status: { notIn: ['cancelled'] } },
        data: { status: dto.status },
      });
    }

    if (dto.status === 'cancelled') {
      await this.recalculateSessionTotal(kot.sessionId);
    }

    const response = await this.findOneResponse(id);
    this.realtime.kotStatusChanged(updated.branchId, response);
    return response;
  }

  async updateItemStatus(
    kotId: string,
    itemId: string,
    currentUser: CurrentUserPayload,
    dto: UpdateStatusDto,
  ) {
    const kot = await this.findOne(kotId);
    const item = kot.items.find((i) => i.id === itemId);
    if (!item) throw new NotFoundException('KOT item not found');

    if (dto.status === 'cancelled' && kot.status !== 'pending' && !MANAGER_ROLES.includes(currentUser.role)) {
      throw new ForbiddenException(
        'This order has already been sent to the kitchen — ask a manager to cancel this item',
      );
    }

    const wasPending = item.status === 'pending';
    const updated = await this.prisma.kotItem.update({
      where: { id: itemId },
      data: { status: dto.status },
    });

    if (dto.status === 'cancelled' && wasPending) {
      await this.restoreStockForItem(kot.branchId, item);
    }

    const response = await this.findOneResponse(kotId);
    this.realtime.kotStatusChanged(kot.branchId, response);
    if (dto.status === 'cancelled') {
      this.realtime.orderItemCancelled(kot.branchId, response);
      this.auditLogs.record({
        branchId: kot.branchId,
        userId: currentUser.userId,
        action: 'item_cancelled',
        tableName: 'kots',
        rowId: kotId,
        oldValues: { itemId, name: item.name },
      });
    }
    return updated;
  }

  /** Changes an item's quantity, or cancels it when the new quantity is <= 0.
   * Freely editable while the parent KOT is still 'pending'; once the
   * kitchen has progressed it, only a manager/admin can still change it. */
  async updateItemQuantity(itemId: string, currentUser: CurrentUserPayload, dto: UpdateItemQuantityDto) {
    const item = await this.prisma.kotItem.findUnique({ where: { id: itemId } });
    if (!item) throw new NotFoundException('KOT item not found');

    const kot = await this.findOne(item.kotId);
    if (!kot) throw new BadRequestException('Parent KOT no longer exists');

    if (kot.status !== 'pending' && !MANAGER_ROLES.includes(currentUser.role)) {
      throw new ForbiddenException(
        'This order has already been sent to the kitchen — ask a manager to modify it',
      );
    }

    const wasPending = item.status === 'pending';
    const isCancel = dto.quantity <= 0;
    const updated = isCancel
      ? await this.prisma.kotItem.update({ where: { id: itemId }, data: { status: 'cancelled' } })
      : await this.prisma.kotItem.update({ where: { id: itemId }, data: { quantity: dto.quantity } });

    if (isCancel && wasPending) {
      await this.restoreStockForItem(kot.branchId, item);
    }

    await this.recalculateSessionTotal(kot.sessionId);
    const response = await this.findOneResponse(item.kotId);
    this.realtime.kotStatusChanged(kot.branchId, response);
    if (isCancel) {
      this.realtime.orderItemCancelled(kot.branchId, response);
    }
    this.auditLogs.record({
      branchId: kot.branchId,
      userId: currentUser.userId,
      action: isCancel ? 'item_cancelled' : 'quantity_changed',
      tableName: 'kots',
      rowId: kot.id,
      oldValues: { itemId, quantity: item.quantity },
      newValues: isCancel ? undefined : { itemId, quantity: dto.quantity },
    });
    return updated;
  }

  /** Only from a served item — records the return without touching stock
   * (the food was already prepared/served, unlike a pre-kitchen cancel). */
  async returnItem(kotId: string, itemId: string, currentUser: CurrentUserPayload, dto: ReturnItemDto) {
    const kot = await this.findOne(kotId);
    const item = kot.items.find((i) => i.id === itemId);
    if (!item) throw new NotFoundException('KOT item not found');
    if (item.status !== 'served') {
      throw new BadRequestException('Only a served item can be returned');
    }

    const updated = await this.prisma.kotItem.update({
      where: { id: itemId },
      data: { status: 'returned' },
    });

    const response = await this.findOneResponse(kotId);
    this.realtime.kotStatusChanged(kot.branchId, response);
    this.auditLogs.record({
      branchId: kot.branchId,
      userId: currentUser.userId,
      action: 'item_returned',
      tableName: 'kots',
      rowId: kotId,
      oldValues: { itemId, name: item.name, reason: dto.reason },
    });
    return updated;
  }

  /** Increments the print counter — first call is the original KOT print,
   * every call after is a reprint (surfaced distinctly in the audit log). */
  async recordPrint(id: string, currentUser?: CurrentUserPayload) {
    const kot = await this.findOne(id);
    const updated = await this.prisma.kot.update({
      where: { id },
      data: { printCount: { increment: 1 }, lastPrintedAt: new Date() },
    });
    this.auditLogs.record({
      branchId: kot.branchId,
      userId: currentUser?.userId,
      action: updated.printCount > 1 ? 'kot_reprinted' : 'kot_printed',
      tableName: 'kots',
      rowId: id,
      newValues: { printCount: updated.printCount },
    });
    return { printCount: updated.printCount, lastPrintedAt: updated.lastPrintedAt };
  }

  /** Recomputes total_amount from non-cancelled KOT items. Used after any KOT/item mutation. */
  async recalculateSessionTotal(sessionId: string) {
    const items = await this.prisma.kotItem.findMany({
      where: { kot: { sessionId, status: { not: 'cancelled' } }, status: { not: 'cancelled' } },
    });
    const total = items.reduce((sum, item) => sum + Number(item.quantity) * Number(item.unitPrice), 0);
    return this.prisma.tableSession.update({ where: { id: sessionId }, data: { totalAmount: total } });
  }

  /** Deducts recipe ingredients for every item on a newly-created KOT.
   * Silently skips items with no recipe defined yet (most MenuItems won't
   * have one) — this must never error out order creation over missing
   * costing data. */
  private async deductStockForItems(
    branchId: string,
    kotNumber: string,
    items: { menuItemId: string; quantity: number }[],
  ) {
    const recipes = await this.prisma.recipe.findMany({
      where: { menuItemId: { in: items.map((i) => i.menuItemId) } },
      include: { ingredients: true },
    });
    const recipeByMenuItem = new Map(recipes.map((r) => [r.menuItemId, r]));

    for (const orderItem of items) {
      const recipe = recipeByMenuItem.get(orderItem.menuItemId);
      if (!recipe || recipe.ingredients.length === 0) continue;

      for (const ingredient of recipe.ingredients) {
        const consumed = Number(ingredient.quantity) * orderItem.quantity;
        const [updatedStock] = await this.prisma.$transaction([
          this.prisma.inventoryItem.update({
            where: { id: ingredient.inventoryItemId },
            data: { currentStock: { decrement: consumed } },
          }),
          this.prisma.stockMovement.create({
            data: {
              branchId,
              itemId: ingredient.inventoryItemId,
              type: 'out',
              quantity: consumed,
              reason: `KOT ${kotNumber}`,
            },
          }),
        ]);

        if (Number(updatedStock.currentStock) <= Number(updatedStock.reorderLevel)) {
          this.realtime.lowStock(branchId, updatedStock);
          await this.notifications.lowStock(updatedStock);
        }
      }
    }
  }

  /** Reverses deductStockForItems for one cancelled item — only called
   * when that item's own status was still 'pending' (kitchen hadn't
   * started preparing it), matching the "restock if cancelled before
   * preparation" rule. */
  private async restoreStockForItem(
    branchId: string,
    item: { menuItemId: string; quantity: number },
  ) {
    const recipe = await this.prisma.recipe.findUnique({
      where: { menuItemId: item.menuItemId },
      include: { ingredients: true },
    });
    if (!recipe || recipe.ingredients.length === 0) return;

    for (const ingredient of recipe.ingredients) {
      const restored = Number(ingredient.quantity) * item.quantity;
      await this.prisma.$transaction([
        this.prisma.inventoryItem.update({
          where: { id: ingredient.inventoryItemId },
          data: { currentStock: { increment: restored } },
        }),
        this.prisma.stockMovement.create({
          data: {
            branchId,
            itemId: ingredient.inventoryItemId,
            type: 'in',
            quantity: restored,
            reason: 'KOT item cancelled',
          },
        }),
      ]);
    }
  }
}
