import { CallHandler, ExecutionContext, Injectable, Logger, NestInterceptor } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Observable } from 'rxjs';
import { tap } from 'rxjs/operators';
import { PrismaService } from '../../prisma/prisma.service';
import { RealtimeService } from '../../modules/websocket/realtime.service';
import { CurrentUserPayload } from '../decorators/current-user.decorator';

/**
 * After every successful write this interceptor does two things:
 *
 *  1. Broadcasts `data:changed` to the acting user's branch room, so screens
 *     reading that entity reload without a manual refresh. Most feature
 *     modules never emitted anything of their own — credit, expenses,
 *     customers, reservations, loyalty, suppliers, staff, attendance, payroll
 *     and branches were all invisible to other devices until a page reload.
 *
 *  2. Records a Notification row and pushes `notification:new`, which is what
 *     lights the red badge on the bell.
 *
 * Notifications are written straight through Prisma rather than through
 * NotificationsService on purpose: that service also fans out an FCM push,
 * and a phone buzz for every KOT status tick would be unusable.
 */

/** Already publish a richer, targeted event. Emitting `data:changed` too would double every refetch on the app's hottest paths. */
const SELF_EMITTING = new Set(['kots', 'tables', 'sessions', 'billing', 'menu', 'users', 'purchases']);

/** Not branch data, or must never trigger a refetch. */
const IGNORED = new Set(['auth', 'uploads', 'super-admin', 'audit-logs', 'reports']);

/**
 * Never notify about writes to the notification store itself. Marking an
 * alert as read is a PATCH — recording *that* as a fresh unread alert would
 * mean the badge could never be cleared.
 */
const NEVER_NOTIFY = new Set([...IGNORED, 'notifications']);

/** entity path segment → human label used in the notification title. */
const ENTITY_LABELS: Record<string, string> = {
  attendance: 'Attendance',
  bar: 'Bar stock',
  billing: 'Bill',
  branches: 'Branch',
  credit: 'Credit',
  customers: 'Customer',
  expenses: 'Expense',
  inventory: 'Inventory',
  kots: 'Kitchen order',
  loyalty: 'Loyalty',
  menu: 'Menu',
  payroll: 'Payroll',
  purchases: 'Purchase',
  reservations: 'Reservation',
  sessions: 'Table session',
  'shift-closing': 'Shift',
  staff: 'Staff',
  suppliers: 'Supplier',
  tables: 'Table',
  users: 'User account',
};

const ACTION_VERBS: Record<string, string> = {
  POST: 'added',
  PUT: 'updated',
  PATCH: 'updated',
  DELETE: 'deleted',
};

@Injectable()
export class RealtimeChangeInterceptor implements NestInterceptor {
  private readonly logger = new Logger(RealtimeChangeInterceptor.name);
  private readonly prefixDepth: number;

  constructor(
    private readonly realtime: RealtimeService,
    private readonly prisma: PrismaService,
    configService: ConfigService,
  ) {
    const prefix = configService.get<string>('app.apiPrefix') ?? 'api/v1';
    this.prefixDepth = prefix.split('/').filter(Boolean).length;
  }

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const request = context.switchToHttp().getRequest();
    const method = String(request.method ?? '').toUpperCase();

    if (!ACTION_VERBS[method]) return next.handle();

    const entity = this.resolveEntity(request);
    if (!entity || IGNORED.has(entity)) return next.handle();

    const branchId = this.resolveBranchId(request);
    if (!branchId) return next.handle();

    const actor = request.user as CurrentUserPayload | undefined;

    // tap's next callback only fires on success, so a rejected write never
    // tells other devices to refetch, nor leaves a phantom notification.
    return next.handle().pipe(
      tap(() => {
        if (!SELF_EMITTING.has(entity)) {
          this.realtime.dataChanged(branchId, entity, method);
        }
        if (!NEVER_NOTIFY.has(entity)) {
          void this.recordNotification(branchId, entity, method, actor);
        }
      }),
    );
  }

  /**
   * Fire-and-forget: the caller's write already succeeded, so a failure to
   * log the bell notification must not turn their 200 into a 500.
   */
  private async recordNotification(
    branchId: string,
    entity: string,
    method: string,
    actor: CurrentUserPayload | undefined,
  ): Promise<void> {
    try {
      const label = ENTITY_LABELS[entity] ?? entity;
      const verb = ACTION_VERBS[method];
      const by = actor?.email ? ` by ${actor.email}` : '';

      const notification = await this.prisma.notification.create({
        data: {
          branchId,
          title: `${label} ${verb}`,
          body: `${label} was ${verb}${by}.`,
        },
      });
      this.realtime.notification(branchId, notification);
    } catch (error) {
      this.logger.warn(`Could not record activity notification: ${(error as Error).message}`);
    }
  }

  /** `/api/v1/credit/<id>/settle?x=1` → `credit` */
  private resolveEntity(request: { originalUrl?: string; url?: string }): string | null {
    const path = String(request.originalUrl ?? request.url ?? '').split('?')[0];
    const segments = path.split('/').filter(Boolean);
    return segments[this.prefixDepth] ?? null;
  }

  /**
   * Staff are pinned to one branch by their token. A super_admin's token
   * carries no branch, so fall back to whatever branch the request targets —
   * and stay silent if the write isn't branch-scoped at all.
   */
  private resolveBranchId(request: {
    user?: CurrentUserPayload;
    body?: Record<string, unknown>;
    query?: Record<string, unknown>;
  }): string | null {
    const fromToken = request.user?.branchId;
    if (fromToken) return fromToken;

    const fromBody = request.body?.branchId;
    if (typeof fromBody === 'string' && fromBody) return fromBody;

    const fromQuery = request.query?.branchId;
    if (typeof fromQuery === 'string' && fromQuery) return fromQuery;

    return null;
  }
}
