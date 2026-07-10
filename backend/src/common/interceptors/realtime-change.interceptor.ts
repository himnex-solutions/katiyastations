import { CallHandler, ExecutionContext, Injectable, Logger, NestInterceptor } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Observable } from 'rxjs';
import { tap } from 'rxjs/operators';
import { PrismaService } from '../../prisma/prisma.service';
import { RealtimeService } from '../../modules/websocket/realtime.service';
import { CurrentUserPayload } from '../decorators/current-user.decorator';
import { Role } from '../decorators/roles.decorator';

/**
 * After every successful write this interceptor does two things:
 *
 *  1. Broadcasts `data:changed` to the acting user's branch room, so screens
 *     reading that entity reload without a manual refresh. Most feature
 *     modules never emitted anything of their own — credit, expenses,
 *     customers, reservations, loyalty, suppliers, staff, attendance, payroll
 *     and branches were all invisible to other devices until a page reload.
 *     This half is unconditional and silent: refreshing a list is cheap and
 *     nobody's bell rings for it.
 *
 *  2. For the handful of writes that another *role* needs to know about, it
 *     records a Notification and pushes `notification:new` to that role only.
 *
 * Notifications are written straight through Prisma rather than through
 * NotificationsService on purpose: that service also fans out an FCM push,
 * and a phone buzz for every KOT status tick would be unusable.
 */

/** Already publish a richer, targeted event. Emitting `data:changed` too would double every refetch on the app's hottest paths. */
const SELF_EMITTING = new Set([
  'kots',
  'tables',
  'sessions',
  'billing',
  'menu',
  'users',
  'purchases',
  // NotificationsService emits its own `data:changed` on clear, and it knows
  // the branch even when a super_admin's token doesn't carry one.
  'notifications',
]);

/** Not branch data, or must never trigger a refetch. */
const IGNORED = new Set(['auth', 'uploads', 'super-admin', 'audit-logs', 'reports']);

const ACTION_VERBS: Record<string, string> = {
  POST: 'added',
  PUT: 'updated',
  PATCH: 'updated',
  DELETE: 'deleted',
};

interface NotifyRule {
  /** Bell headline, written as the event — e.g. "New reservation". */
  title: string;
  /** Second line. `by` is " by <email>" or empty. */
  body: (by: string) => string;
  /** Roles whose bell should ring. The user who made the change is excluded. */
  audience: Role[];
  /** Restrict to specific HTTP methods. Omit to notify on all four. */
  methods?: string[];
}

/**
 * The whole notification policy, in one deliberately tiny table.
 *
 * A bell rings only when a *specific person is waiting to act on this exact
 * event* — never for routine record-keeping. Editing the menu, adding a
 * customer, recording an expense, restocking a shelf: all still broadcast
 * `data:changed` so the relevant screen refreshes live, but none of them
 * writes a Notification row. That day-to-day churn was what filled the table
 * and made the badge meaningless, so it is intentionally absent here.
 *
 * The one operational alarm that matters most — low / out of stock — is not in
 * this table at all: InventoryService raises it through
 * NotificationsService.lowStock() with its own wording and dedup.
 *
 * The bar for adding an entry: a named role is blocked or waiting until they
 * respond to *this* write. "Nice to know" is not enough — leave it out.
 */
const NOTIFY_RULES: Record<string, NotifyRule> = {
  // A new booking: the floor has to hold and prepare a table at a set time.
  // Only a fresh reservation — edits and cancellations aren't someone waiting.
  reservations: {
    title: 'New reservation',
    body: (by) => `A table has been reserved${by}. Check the Reservations tab.`,
    audience: ['cashier', 'waiter', 'branch_manager'],
    methods: ['POST'],
  },

  // A submitted shift closing blocks the cashier from leaving until the
  // manager reviews and approves it.
  'shift-closing': {
    title: 'Shift closing to review',
    body: (by) => `A shift closing was submitted${by} and is waiting for your approval.`,
    audience: ['branch_manager'],
    methods: ['POST'],
  },
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

        const rule = NOTIFY_RULES[entity];
        if (rule && (rule.methods ?? Object.keys(ACTION_VERBS)).includes(method)) {
          void this.recordNotification(branchId, rule, actor);
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
    rule: NotifyRule,
    actor: CurrentUserPayload | undefined,
  ): Promise<void> {
    try {
      const by = actor?.email ? ` by ${actor.email}` : '';

      // Someone whose only role is the audience *and* who made the change
      // would be told about their own click. Drop the write entirely rather
      // than store a row nobody will ever be shown.
      const audience = rule.audience.filter((role) => role !== actor?.role);
      if (audience.length === 0) return;

      const notification = await this.prisma.notification.create({
        data: {
          branchId,
          title: rule.title,
          body: rule.body(by),
          audience,
          actorId: actor?.userId ?? null,
        },
      });
      this.realtime.notification(branchId, notification, audience);
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
