import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { RealtimeService } from '../websocket/realtime.service';
import { AuditLogsService } from '../audit-logs/audit-logs.service';
import { KotsService } from '../kots/kots.service';
import { CloseSessionDto } from './dto/close-session.dto';
import { HoldSessionDto } from './dto/hold-session.dto';
import { MergeSessionDto } from './dto/merge-session.dto';
import { SplitSessionDto } from './dto/split-session.dto';
import { FindSessionsDto } from './dto/find-sessions.dto';
import { ReassignWaiterDto } from './dto/reassign-waiter.dto';
import { CurrentUserPayload } from '../../common/decorators/current-user.decorator';
import { resolveBranchScope } from '../../common/utils/branch-scope.util';
import { generateSequenceNumber } from '../../common/utils/sequence.util';

function toSessionResponse(session: any) {
  const { waiter, ...rest } = session;
  return { ...rest, waiterName: waiter?.fullName ?? null };
}

@Injectable()
export class SessionsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: RealtimeService,
    private readonly kotsService: KotsService,
    private readonly auditLogs: AuditLogsService,
  ) {}

  async findAll(currentUser: CurrentUserPayload, filter: FindSessionsDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const sessions = await this.prisma.tableSession.findMany({
      where: {
        ...(branchId ? { branchId } : {}),
        ...(filter.status ? { status: filter.status } : {}),
      },
      include: { waiter: { select: { fullName: true } } },
      orderBy: { openedAt: 'desc' },
    });
    return sessions.map(toSessionResponse);
  }

  async findOne(id: string) {
    const session = await this.prisma.tableSession.findUnique({ where: { id } });
    if (!session) throw new NotFoundException('Session not found');
    return session;
  }

  async kots(sessionId: string) {
    await this.findOne(sessionId);
    return this.kotsService.bySession(sessionId);
  }

  async close(id: string, dto: CloseSessionDto, currentUser?: CurrentUserPayload) {
    const session = await this.findOne(id);
    if (session.status === 'closed') {
      throw new BadRequestException('This session is already closed');
    }

    const [updated] = await this.prisma.$transaction([
      this.prisma.tableSession.update({
        where: { id },
        data: { status: 'closed', closedAt: new Date() },
      }),
      this.prisma.restaurantTable.update({
        where: { id: session.tableId },
        data: { status: 'cleaning', currentSessionId: null, billRequested: false, billRequestedAt: null },
      }),
    ]);

    this.realtime.sessionClosed(session.branchId, updated);
    this.realtime.tableStatusChanged(session.branchId, session.tableId, { status: 'cleaning' });
    this.auditLogs.record({
      branchId: session.branchId,
      userId: currentUser?.userId,
      action: 'session_closed',
      tableName: 'table_sessions',
      rowId: id,
    });

    return updated;
  }

  async hold(id: string, dto: HoldSessionDto, currentUser?: CurrentUserPayload) {
    await this.findOne(id);
    const updated = await this.prisma.tableSession.update({
      where: { id },
      data: { onHold: true, holdReason: dto.reason },
    });
    this.realtime.sessionOpened(updated.branchId, updated); // reuse: triggers a session refresh on clients
    this.auditLogs.record({
      branchId: updated.branchId,
      userId: currentUser?.userId,
      action: 'session_held',
      tableName: 'table_sessions',
      rowId: id,
      newValues: { reason: dto.reason },
    });
    return updated;
  }

  async unhold(id: string, currentUser?: CurrentUserPayload) {
    await this.findOne(id);
    const updated = await this.prisma.tableSession.update({
      where: { id },
      data: { onHold: false, holdReason: null },
    });
    this.realtime.sessionOpened(updated.branchId, updated);
    this.auditLogs.record({
      branchId: updated.branchId,
      userId: currentUser?.userId,
      action: 'session_unheld',
      tableName: 'table_sessions',
      rowId: id,
    });
    return updated;
  }

  /** Manager-only reassignment of an existing session's waiter — distinct
   * from transferSession (which moves the table/location, not identity). */
  async reassignWaiter(id: string, currentUser: CurrentUserPayload, dto: ReassignWaiterDto) {
    const session = await this.findOne(id);
    if (session.status !== 'open') {
      throw new BadRequestException('Can only reassign the waiter on an open session');
    }

    const waiter = await this.prisma.user.findUnique({ where: { id: dto.waiterId } });
    if (!waiter || waiter.role !== 'waiter' || waiter.branchId !== session.branchId || !waiter.isActive) {
      throw new BadRequestException('waiterId must be an active waiter in this branch');
    }

    const oldWaiterId = session.waiterId;
    const updated = await this.prisma.tableSession.update({
      where: { id },
      data: { waiterId: dto.waiterId },
    });

    this.realtime.waiterAssigned(session.branchId, {
      sessionId: id,
      tableId: session.tableId,
      waiterId: dto.waiterId,
      waiterName: waiter.fullName,
    });
    this.auditLogs.record({
      branchId: session.branchId,
      userId: currentUser.userId,
      action: 'waiter_reassigned',
      tableName: 'table_sessions',
      rowId: id,
      oldValues: { waiterId: oldWaiterId },
      newValues: { waiterId: dto.waiterId },
    });

    return updated;
  }

  async recalculateTotal(sessionId: string) {
    return this.kotsService.recalculateSessionTotal(sessionId);
  }

  /** Moves all KOTs from this session into another and closes this one, freeing its table. */
  async merge(id: string, dto: MergeSessionDto, currentUser?: CurrentUserPayload) {
    const source = await this.findOne(id);
    const destination = await this.findOne(dto.intoSessionId);
    if (source.id === destination.id) {
      throw new BadRequestException('Cannot merge a session into itself');
    }

    await this.prisma.$transaction([
      this.prisma.kot.updateMany({
        where: { sessionId: source.id },
        data: { sessionId: destination.id, tableId: destination.tableId },
      }),
      this.prisma.tableSession.update({
        where: { id: source.id },
        data: { status: 'closed', closedAt: new Date() },
      }),
      this.prisma.restaurantTable.update({
        where: { id: source.tableId },
        data: { status: 'available', currentSessionId: null, billRequested: false, billRequestedAt: null },
      }),
    ]);

    await this.recalculateTotal(destination.id);

    this.realtime.tableStatusChanged(source.branchId, source.tableId, { status: 'available' });
    this.realtime.sessionOpened(destination.branchId, await this.findOne(destination.id));
    this.auditLogs.record({
      branchId: source.branchId,
      userId: currentUser?.userId,
      action: 'merge',
      tableName: 'table_sessions',
      rowId: destination.id,
      oldValues: { mergedFromSessionId: source.id },
    });
    return { merged: true };
  }

  /** Moves the given KOTs to a brand-new session on another table. */
  async split(id: string, currentUser: CurrentUserPayload, dto: SplitSessionDto) {
    const source = await this.findOne(id);
    const toTable = await this.prisma.restaurantTable.findUnique({ where: { id: dto.toTableId } });
    if (!toTable) throw new NotFoundException('Destination table not found');
    if (toTable.currentSessionId) {
      throw new BadRequestException('Destination table already has an active session');
    }

    const newSession = await this.prisma.$transaction(async (tx) => {
      const created = await tx.tableSession.create({
        data: {
          tableId: toTable.id,
          branchId: source.branchId,
          sessionNumber: generateSequenceNumber('SESS'),
          waiterId: currentUser.role === 'waiter' ? currentUser.userId : source.waiterId,
          guestCount: dto.guestCount ?? 1,
        },
      });

      await tx.restaurantTable.update({
        where: { id: toTable.id },
        data: { status: 'occupied', currentSessionId: created.id },
      });

      await tx.kot.updateMany({
        where: { id: { in: dto.kotIds }, sessionId: source.id },
        data: { sessionId: created.id, tableId: toTable.id },
      });

      return created;
    });

    await this.recalculateTotal(source.id);
    await this.recalculateTotal(newSession.id);

    this.realtime.sessionOpened(source.branchId, await this.findOne(newSession.id));
    this.realtime.tableStatusChanged(source.branchId, toTable.id, { status: 'occupied' });
    this.auditLogs.record({
      branchId: source.branchId,
      userId: currentUser.userId,
      action: 'split',
      tableName: 'table_sessions',
      rowId: source.id,
      newValues: { splitIntoSessionId: newSession.id, kotIds: dto.kotIds },
    });
    return this.findOne(newSession.id);
  }
}
