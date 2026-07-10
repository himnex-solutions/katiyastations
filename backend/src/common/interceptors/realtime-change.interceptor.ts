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
  /** Human label used in the notification title. */
  label: string;
  /** Roles whose bell should ring. The user who made the change is excluded. */
  audience: Role[];
  /** Restrict to specific HTTP methods. Omit to notify on all four. */
  methods?: string[];
}

/**
 * The whole notification policy, in one table.
 *
 * An entity that isn't listed here never writes a bell notification — it still
 * broadcasts `data:changed`, so screens showing it stay live. That is the
 * point: `kots`, `tables`, `sessions` and `billing` change many times a
 * minute and already have dedicated live screens (kitchen board, table grid,
 * cashier till). Ringing every bell for each of those ticks is the noise this
 * table exists to kill.
 *
 * The rule for adding an entry: would a person in `audience` have to *do*
 * something because of this write? If not, leave it out.
 */
const NOTIFY_RULES: Record<string, NotifyRule> = {
  // Stock someone has to go count, reorder, or restock.
  inventory: { label: 'Inventory', audience: ['inventory', 'branch_manager'] },
  bar: { label: 'Bar stock', audience: ['inventory', 'branch_manager'] },
  suppliers: { label: 'Supplier', audience: ['inventory', 'branch_manager'] },
  purchases: {
    label: 'Purchase',
    audience: ['inventory', 'branch_manager', 'accountant'],
    methods: ['POST', 'DELETE'],
  },

  // Money someone has to reconcile.
  expenses: { label: 'Expense', audience: ['accountant', 'branch_manager'] },
  credit: { label: 'Credit', audience: ['cashier', 'accountant', 'branch_manager'] },
  'shift-closing': { label: 'Shift', audience: ['branch_manager', 'cashier'] },

  // Front-of-house work handed to the floor.
  reservations: { label: 'Reservation', audience: ['cashier', 'waiter', 'branch_manager'] },
  customers: { label: 'Customer', audience: ['cashier', 'branch_manager'], methods: ['POST', 'DELETE'] },
  loyalty: { label: 'Loyalty', audience: ['cashier', 'branch_manager'] },

  // A changed menu invalidates what the floor and the kitchen can sell/cook.
  menu: { label: 'Menu', audience: ['cashier', 'waiter', 'kitchen', 'branch_manager'] },

  // People and pay — the manager's problem, nobody else's.
  staff: { label: 'Staff', audience: ['branch_manager'] },
  users: { label: 'User account', audience: ['branch_manager'] },
  attendance: { label: 'Attendance', audience: ['branch_manager'] },
  payroll: { label: 'Payroll', audience: ['branch_manager', 'accountant'] },
  branches: { label: 'Branch', audience: ['branch_manager'] },
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
          void this.recordNotification(branchId, rule, method, actor);
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
    method: string,
    actor: CurrentUserPayload | undefined,
  ): Promise<void> {
    try {
      const verb = ACTION_VERBS[method];
      const by = actor?.email ? ` by ${actor.email}` : '';

      // Someone whose only role is the audience *and* who made the change
      // would be told about their own click. Drop the write entirely rather
      // than store a row nobody will ever be shown.
      const audience = rule.audience.filter((role) => role !== actor?.role);
      if (audience.length === 0) return;

      const notification = await this.prisma.notification.create({
        data: {
          branchId,
          title: `${rule.label} ${verb}`,
          body: `${rule.label} was ${verb}${by}.`,
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
