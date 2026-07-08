import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { RealtimeService } from '../websocket/realtime.service';
import { FcmService } from './fcm.service';
import { CreateNotificationDto } from './dto/create-notification.dto';
import { RegisterDeviceTokenDto } from './dto/register-device-token.dto';
import { CurrentUserPayload } from '../../common/decorators/current-user.decorator';
import { resolveBranchScope } from '../../common/utils/branch-scope.util';
import { buildPaginationMeta } from '../../common/dto/pagination.dto';
import { BranchFilterDto } from '../../common/dto/branch-filter.dto';

@Injectable()
export class NotificationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: RealtimeService,
    private readonly fcm: FcmService,
  ) {}

  async findAll(currentUser: CurrentUserPayload, filter: BranchFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = branchId ? { branchId } : {};

    const [items, total] = await Promise.all([
      this.prisma.notification.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: filter.skip,
        take: filter.take,
      }),
      this.prisma.notification.count({ where }),
    ]);

    return { data: items, meta: buildPaginationMeta(total, filter.page ?? 1, filter.take) };
  }

  async create(dto: CreateNotificationDto) {
    const notification = await this.prisma.notification.create({ data: dto });
    this.realtime.notification(dto.branchId, notification);

    const tokens = await this.prisma.deviceToken.findMany({
      where: { user: { branchId: dto.branchId } },
      select: { token: true },
    });
    await this.fcm.sendToTokens(tokens.map((t) => t.token), dto.title, dto.body);

    return notification;
  }

  /**
   * Persists a low/out-of-stock alert and pushes it live (realtime + FCM).
   * De-duped by title: while an alert of the same severity for the same item
   * is still unread, repeated triggers (every order that consumes it) won't
   * spam a fresh one — acknowledging it (mark-read) re-arms the alert.
   */
  async lowStock(item: {
    branchId: string;
    name: string;
    unit?: string | null;
    currentStock: unknown;
    reorderLevel: unknown;
  }) {
    const qty = Number(item.currentStock);
    const isOut = qty <= 0;
    const title = isOut ? `Out of stock: ${item.name}` : `Low stock: ${item.name}`;

    const existing = await this.prisma.notification.findFirst({
      where: { branchId: item.branchId, title, isRead: false },
    });
    if (existing) return existing;

    const unit = item.unit ? ` ${item.unit}` : '';
    const body = isOut
      ? `${item.name} is OUT of stock — reorder now.`
      : `${item.name} is running low: ${qty}${unit} left (reorder level ${Number(item.reorderLevel)}).`;

    return this.create({ branchId: item.branchId, title, body });
  }

  async markRead(id: string) {
    const notification = await this.prisma.notification.findUnique({ where: { id } });
    if (!notification) throw new NotFoundException('Notification not found');
    return this.prisma.notification.update({ where: { id }, data: { isRead: true } });
  }

  async markAllRead(currentUser: CurrentUserPayload, branchId?: string) {
    const scopedBranchId = resolveBranchScope(currentUser, branchId);
    await this.prisma.notification.updateMany({
      where: { ...(scopedBranchId ? { branchId: scopedBranchId } : {}), isRead: false },
      data: { isRead: true },
    });
    return { updated: true };
  }

  async registerDeviceToken(userId: string, dto: RegisterDeviceTokenDto) {
    return this.prisma.deviceToken.upsert({
      where: { token: dto.token },
      update: { userId, platform: dto.platform },
      create: { userId, token: dto.token, platform: dto.platform },
    });
  }
}
