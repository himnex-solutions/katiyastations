import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { RealtimeService } from '../websocket/realtime.service';
import { FcmService } from './fcm.service';
import { CreateNotificationDto } from './dto/create-notification.dto';
import { RegisterDeviceTokenDto } from './dto/register-device-token.dto';
import { CurrentUserPayload } from '../../common/decorators/current-user.decorator';
import { resolveBranchScope } from '../../common/utils/branch-scope.util';
import { buildPaginationMeta } from '../../common/dto/pagination.dto';
import { BranchFilterDto } from '../../common/dto/branch-filter.dto';

/**
 * How long an alert stays on the bell. Anything older is purged, so a bell
 * left unattended overnight is empty in the morning rather than showing a
 * week of history nobody will read.
 */
export const NOTIFICATION_TTL_HOURS = 12;

const ttlCutoff = () => new Date(Date.now() - NOTIFICATION_TTL_HOURS * 60 * 60 * 1000);

@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: RealtimeService,
    private readonly fcm: FcmService,
  ) {}

  /**
   * What this user is allowed to see: their branch, alerts addressed to their
   * role (or to nobody in particular), never their own actions, never expired.
   *
   * A super_admin isn't part of any branch's role roster, so scoping by
   * audience would hand them an empty list — they see the branch's alerts raw.
   */
  private visibleTo(currentUser: CurrentUserPayload, branchId?: string): Prisma.NotificationWhereInput {
    if (currentUser.role === 'super_admin') {
      return { ...(branchId ? { branchId } : {}), createdAt: { gte: ttlCutoff() } };
    }

    return {
      // Never widen to "all branches" just because no branch was requested:
      // markRead/markAllRead reach this without going through resolveBranchScope.
      branchId: currentUser.branchId ?? '',
      createdAt: { gte: ttlCutoff() },
      AND: [
        // Addressed to this role, or to the branch at large.
        { OR: [{ audience: { isEmpty: true } }, { audience: { has: currentUser.role } }] },
        // Not something this user did themselves. Spelled out rather than
        // written as `NOT: { actorId }`, because a system alert (low stock)
        // has no actor and `actor_id <> $1` is NULL — never true — for it.
        { OR: [{ actorId: null }, { actorId: { not: currentUser.userId } }] },
      ],
    };
  }

  async findAll(currentUser: CurrentUserPayload, filter: BranchFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = this.visibleTo(currentUser, branchId);

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
    const audience = dto.audience ?? [];
    const notification = await this.prisma.notification.create({
      data: {
        branchId: dto.branchId,
        title: dto.title,
        body: dto.body,
        audience,
        actorId: dto.actorId ?? null,
      },
    });
    this.realtime.notification(dto.branchId, notification, audience);

    // The push has to respect the same audience the bell does, or a waiter's
    // phone buzzes for the accountant's alert.
    const tokens = await this.prisma.deviceToken.findMany({
      where: {
        user: {
          branchId: dto.branchId,
          ...(audience.length > 0 ? { role: { in: audience } } : {}),
          ...(dto.actorId ? { id: { not: dto.actorId } } : {}),
        },
      },
      select: { token: true },
    });
    await this.fcm.sendToTokens(tokens.map((t) => t.token), dto.title, dto.body);

    return notification;
  }

  /**
   * Persists a low/out-of-stock alert and pushes it live (realtime + FCM).
   * De-duped by title: while an alert for the same item is still on the bell,
   * repeated triggers (every order that consumes it) won't spam a fresh one —
   * clearing it, or letting it expire, re-arms the alert.
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
      where: { branchId: item.branchId, title, createdAt: { gte: ttlCutoff() } },
    });
    if (existing) return existing;

    const unit = item.unit ? ` ${item.unit}` : '';
    const body = isOut
      ? `${item.name} is OUT of stock — reorder now.`
      : `${item.name} is running low: ${qty}${unit} left (reorder level ${Number(item.reorderLevel)}).`;

    return this.create({
      branchId: item.branchId,
      title,
      body,
      audience: ['inventory', 'branch_manager', 'cashier', 'accountant'],
    });
  }

  /**
   * Reading an alert destroys it — there is no read flag to set. Scoped to
   * what the caller can actually see so one branch can't clear another's, and
   * so a stale id from a since-purged alert 404s instead of silently no-oping.
   */
  async markRead(currentUser: CurrentUserPayload, id: string) {
    const notification = await this.prisma.notification.findFirst({
      where: { id, ...this.visibleTo(currentUser) },
    });
    if (!notification) throw new NotFoundException('Notification not found');

    await this.prisma.notification.delete({ where: { id } });
    this.realtime.dataChanged(notification.branchId, 'notifications', 'DELETE');
    return { deleted: true };
  }

  /**
   * Clears only the alerts this user can see. A waiter emptying their bell
   * must not wipe the manager's queue.
   */
  async markAllRead(currentUser: CurrentUserPayload, branchId?: string) {
    const scopedBranchId = resolveBranchScope(currentUser, branchId);
    const { count } = await this.prisma.notification.deleteMany({
      where: this.visibleTo(currentUser, scopedBranchId),
    });

    if (scopedBranchId) {
      this.realtime.dataChanged(scopedBranchId, 'notifications', 'DELETE');
    }
    return { deleted: count };
  }

  async registerDeviceToken(userId: string, dto: RegisterDeviceTokenDto) {
    return this.prisma.deviceToken.upsert({
      where: { token: dto.token },
      update: { userId, platform: dto.platform },
      create: { userId, token: dto.token, platform: dto.platform },
    });
  }

  /**
   * The 12-hour reset. `findAll` already hides expired rows, so this is about
   * keeping the table small rather than about what anyone sees.
   */
  @Cron(CronExpression.EVERY_30_MINUTES)
  async purgeExpired(): Promise<void> {
    try {
      const { count } = await this.prisma.notification.deleteMany({
        where: { createdAt: { lt: ttlCutoff() } },
      });
      if (count > 0) {
        this.logger.log(`Purged ${count} notification(s) older than ${NOTIFICATION_TTL_HOURS}h`);
      }
    } catch (error) {
      this.logger.warn(`Notification purge failed: ${(error as Error).message}`);
    }
  }
}
