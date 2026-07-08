import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { CreatePurchaseDto } from './dto/create-purchase.dto';
import { UpdatePurchaseDto } from './dto/update-purchase.dto';
import { CurrentUserPayload } from '../../common/decorators/current-user.decorator';
import { resolveBranchScope } from '../../common/utils/branch-scope.util';
import { buildPaginationMeta } from '../../common/dto/pagination.dto';
import { BranchFilterDto } from '../../common/dto/branch-filter.dto';
import { RealtimeService } from '../websocket/realtime.service';

@Injectable()
export class PurchasesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: RealtimeService,
  ) {}

  async findAll(currentUser: CurrentUserPayload, filter: BranchFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = branchId ? { branchId } : {};

    const [items, total] = await Promise.all([
      this.prisma.purchase.findMany({
        where,
        include: { items: true, supplier: true },
        orderBy: { createdAt: 'desc' },
        skip: filter.skip,
        take: filter.take,
      }),
      this.prisma.purchase.count({ where }),
    ]);

    return { data: items, meta: buildPaginationMeta(total, filter.page ?? 1, filter.take) };
  }

  async findOne(id: string) {
    const purchase = await this.prisma.purchase.findUnique({
      where: { id },
      include: { items: true, supplier: true },
    });
    if (!purchase) throw new NotFoundException('Purchase not found');
    return purchase;
  }

  async items(purchaseId: string) {
    await this.findOne(purchaseId);
    return this.prisma.purchaseItem.findMany({ where: { purchaseId } });
  }

  async create(dto: CreatePurchaseDto) {
    const items = dto.items ?? [];
    const totalAmount = items.length
      ? items.reduce((sum, item) => sum + item.quantity * item.unitCost, 0)
      : (dto.totalAmount ?? 0);

    const purchase = await this.prisma.$transaction(async (tx) => {
      const created = await tx.purchase.create({
        data: {
          branchId: dto.branchId,
          supplierId: dto.supplierId,
          supplierName: dto.supplierName,
          notes: dto.notes,
          totalAmount,
          items: {
            create: items.map((item) => ({
              inventoryItemId: item.inventoryItemId,
              quantity: item.quantity,
              unitCost: item.unitCost,
            })),
          },
        },
        include: { items: true, supplier: true },
      });

      // Itemized purchases restock inventory; quick-logged totals (no
      // items) are a spend record only and don't touch stock levels.
      for (const item of items) {
        await tx.inventoryItem.update({
          where: { id: item.inventoryItemId },
          data: { currentStock: { increment: item.quantity } },
        });
        await tx.stockMovement.create({
          data: {
            branchId: dto.branchId,
            itemId: item.inventoryItemId,
            type: 'in',
            quantity: item.quantity,
            reason: `Purchase ${created.id}`,
          },
        });
      }

      return created;
    });

    // Push the new record to every device on this branch so open purchase
    // lists and the daily report update live (createdAt carries the exact
    // date & time the purchase was saved).
    this.realtime.purchaseCreated(dto.branchId, purchase);

    return purchase;
  }

  async update(id: string, dto: UpdatePurchaseDto) {
    await this.findOne(id);
    return this.prisma.purchase.update({ where: { id }, data: dto });
  }
}
