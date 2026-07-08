import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { RealtimeService } from '../websocket/realtime.service';
import { AuditLogsService } from '../audit-logs/audit-logs.service';
import { CreateTableDto } from './dto/create-table.dto';
import { UpdateTableDto } from './dto/update-table.dto';
import { OpenSessionDto } from './dto/open-session.dto';
import { TransferSessionDto } from './dto/transfer-session.dto';
import { CurrentUserPayload } from '../../common/decorators/current-user.decorator';
import { resolveBranchScope } from '../../common/utils/branch-scope.util';
import { generateSequenceNumber } from '../../common/utils/sequence.util';

@Injectable()
export class TablesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: RealtimeService,
    private readonly auditLogs: AuditLogsService,
  ) {}

  async findAll(currentUser: CurrentUserPayload, requestedBranchId?: string) {
    const branchId = resolveBranchScope(currentUser, requestedBranchId);
    return this.prisma.restaurantTable.findMany({
      where: branchId ? { branchId } : {},
      orderBy: [{ section: 'asc' }, { tableNumber: 'asc' }],
    });
  }

  async findOne(id: string) {
    const table = await this.prisma.restaurantTable.findUnique({ where: { id } });
    if (!table) throw new NotFoundException('Table not found');
    return table;
  }

  async create(dto: CreateTableDto) {
    const table = await this.prisma.restaurantTable.create({
      data: {
        branchId: dto.branchId,
        tableNumber: dto.tableNumber,
        section: dto.section ?? 'Main',
        capacity: dto.capacity ?? 4,
      },
    });
    this.realtime.tableStatusChanged(table.branchId, table.id, table);
    return table;
  }

  async update(id: string, dto: UpdateTableDto) {
    await this.findOne(id);
    const table = await this.prisma.restaurantTable.update({ where: { id }, data: dto });
    this.realtime.tableStatusChanged(table.branchId, table.id, table);
    return table;
  }

  async remove(id: string) {
    const table = await this.findOne(id);
    await this.prisma.restaurantTable.delete({ where: { id } });
    this.realtime.tableStatusChanged(table.branchId, table.id, { ...table, deleted: true });
    return { deleted: true };
  }

  async sessions(tableId: string) {
    await this.findOne(tableId);
    return this.prisma.tableSession.findMany({
      where: { tableId },
      orderBy: { openedAt: 'desc' },
    });
  }

  async currentSession(tableId: string) {
    const table = await this.findOne(tableId);
    if (!table.currentSessionId) return null;
    return this.prisma.tableSession.findUnique({ where: { id: table.currentSessionId } });
  }

  async openSession(tableId: string, currentUser: CurrentUserPayload, dto: OpenSessionDto) {
    const table = await this.findOne(tableId);

    if (table.status === 'occupied' && table.currentSessionId) {
      throw new BadRequestException('This table already has an open session');
    }

    const waiterId = await this.resolveWaiterId(table.branchId, currentUser, dto.waiterId);

    const session = await this.prisma.$transaction(async (tx) => {
      const created = await tx.tableSession.create({
        data: {
          tableId: table.id,
          branchId: table.branchId,
          sessionNumber: generateSequenceNumber('SESS'),
          waiterId,
          customerId: dto.customerId,
          guestCount: dto.guestCount ?? 1,
        },
      });

      await tx.restaurantTable.update({
        where: { id: table.id },
        data: { status: 'occupied', currentSessionId: created.id },
      });

      return created;
    });

    this.realtime.sessionOpened(table.branchId, session);
    this.realtime.tableStatusChanged(table.branchId, table.id, { ...table, status: 'occupied' });
    this.auditLogs.record({
      branchId: table.branchId,
      userId: currentUser.userId,
      action: 'order_created',
      tableName: 'table_sessions',
      rowId: session.id,
      newValues: { tableId: table.id, waiterId, guestCount: session.guestCount },
    });

    return session;
  }

  /** Explicit waiterId wins; a waiter opening their own table self-assigns
   * (as before); otherwise auto-pick whichever branch waiter currently has
   * the fewest open sessions — a simple "lowest workload" heuristic that
   * needs no live-presence tracking, just the existing session data. */
  private async resolveWaiterId(
    branchId: string,
    currentUser: CurrentUserPayload,
    explicitWaiterId?: string,
  ): Promise<string | undefined> {
    if (explicitWaiterId) {
      const waiter = await this.prisma.user.findUnique({ where: { id: explicitWaiterId } });
      if (!waiter || waiter.role !== 'waiter' || waiter.branchId !== branchId || !waiter.isActive) {
        throw new BadRequestException('waiterId must be an active waiter in this branch');
      }
      return explicitWaiterId;
    }

    if (currentUser.role === 'waiter') {
      return currentUser.userId;
    }

    const waiters = await this.prisma.user.findMany({
      where: { branchId, role: 'waiter', isActive: true },
      select: { id: true },
    });
    if (waiters.length === 0) return undefined;

    const workloads = await this.prisma.tableSession.groupBy({
      by: ['waiterId'],
      where: { branchId, status: 'open', waiterId: { in: waiters.map((w) => w.id) } },
      _count: { waiterId: true },
    });
    const openCountByWaiter = new Map(workloads.map((w) => [w.waiterId, w._count.waiterId]));

    let leastBusy = waiters[0].id;
    let lowestCount = Infinity;
    for (const w of waiters) {
      const count = openCountByWaiter.get(w.id) ?? 0;
      if (count < lowestCount) {
        lowestCount = count;
        leastBusy = w.id;
      }
    }
    return leastBusy;
  }

  async requestBill(tableId: string) {
    const table = await this.findOne(tableId);
    if (!table.currentSessionId) {
      throw new BadRequestException('This table has no active session');
    }

    const now = new Date();
    const [updatedTable] = await this.prisma.$transaction([
      this.prisma.restaurantTable.update({
        where: { id: tableId },
        data: { status: 'ready_for_billing', billRequested: true, billRequestedAt: now },
      }),
      this.prisma.tableSession.update({
        where: { id: table.currentSessionId },
        data: { billRequested: true, billRequestedAt: now },
      }),
    ]);

    this.realtime.tableStatusChanged(table.branchId, tableId, updatedTable);
    this.auditLogs.record({
      branchId: table.branchId,
      action: 'bill_requested',
      tableName: 'table_sessions',
      rowId: table.currentSessionId,
    });
    return updatedTable;
  }

  async transferSession(fromTableId: string, dto: TransferSessionDto, currentUser?: CurrentUserPayload) {
    const fromTable = await this.findOne(fromTableId);
    const toTable = await this.findOne(dto.toTableId);
    if (!fromTable.currentSessionId) {
      throw new BadRequestException('Source table has no active session to transfer');
    }
    if (toTable.currentSessionId) {
      throw new BadRequestException('Destination table already has an active session');
    }

    const sessionId = fromTable.currentSessionId;
    await this.prisma.$transaction([
      this.prisma.tableSession.update({ where: { id: sessionId }, data: { tableId: toTable.id } }),
      this.prisma.kot.updateMany({ where: { sessionId }, data: { tableId: toTable.id } }),
      this.prisma.restaurantTable.update({
        where: { id: fromTableId },
        data: { status: 'available', currentSessionId: null, billRequested: false, billRequestedAt: null },
      }),
      this.prisma.restaurantTable.update({
        where: { id: toTable.id },
        data: { status: fromTable.status, currentSessionId: sessionId },
      }),
    ]);

    this.realtime.tableStatusChanged(fromTable.branchId, fromTableId, { status: 'available' });
    this.realtime.tableStatusChanged(fromTable.branchId, toTable.id, { status: fromTable.status });
    this.realtime.tableTransferred(fromTable.branchId, {
      sessionId,
      fromTableId,
      fromTableNumber: fromTable.tableNumber,
      toTableId: toTable.id,
      toTableNumber: toTable.tableNumber,
    });
    this.auditLogs.record({
      branchId: fromTable.branchId,
      userId: currentUser?.userId,
      action: 'transfer',
      tableName: 'table_sessions',
      rowId: sessionId,
      oldValues: { tableId: fromTableId, tableNumber: fromTable.tableNumber },
      newValues: { tableId: toTable.id, tableNumber: toTable.tableNumber },
    });
    return { transferred: true };
  }
}
