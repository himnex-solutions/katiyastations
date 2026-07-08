import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { ReportFilterDto } from './dto/report-filter.dto';
import { CurrentUserPayload } from '../../common/decorators/current-user.decorator';
import { resolveBranchScope } from '../../common/utils/branch-scope.util';

function dateRange(filter: ReportFilterDto) {
  return {
    ...(filter.from || filter.to
      ? {
          createdAt: {
            ...(filter.from ? { gte: new Date(filter.from) } : {}),
            ...(filter.to ? { lte: new Date(filter.to) } : {}),
          },
        }
      : {}),
  };
}

@Injectable()
export class ReportsService {
  constructor(private readonly prisma: PrismaService) {}

  async dashboard(currentUser: CurrentUserPayload, filter: ReportFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = branchId ? { branchId } : {};

    const [billsAgg, openSessions, activeKots, inventoryItems, todaysBillCount] = await Promise.all([
      this.prisma.bill.aggregate({ where, _sum: { totalAmount: true } }),
      this.prisma.tableSession.count({ where: { ...where, status: 'open' } }),
      this.prisma.kot.count({ where: { ...where, status: { in: ['pending', 'preparing', 'ready'] } } }),
      this.prisma.inventoryItem.findMany({ where, select: { currentStock: true, reorderLevel: true } }),
      this.prisma.bill.count({
        where: { ...where, createdAt: { gte: new Date(new Date().toISOString().slice(0, 10)) } },
      }),
    ]);

    const lowStockCount = inventoryItems.filter(
      (item) => Number(item.currentStock) <= Number(item.reorderLevel),
    ).length;

    return {
      totalRevenue: Number(billsAgg._sum.totalAmount ?? 0),
      openSessions,
      activeKots,
      lowStockCount,
      todaysBillCount,
    };
  }

  /**
   * One-shot report summary for the Reports screen export (Daily / Weekly /
   * Monthly / Yearly). Aggregated server-side so totals are accurate for any
   * range regardless of row count. Role-aware: a cashier gets sales/collection
   * figures only; managers & accountants also get expenses, purchases and the
   * resulting net profit.
   */
  async summary(currentUser: CurrentUserPayload, filter: ReportFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = { ...(branchId ? { branchId } : {}), ...dateRange(filter) };

    const [byStatus, byMethod, totals] = await Promise.all([
      this.prisma.bill.groupBy({ by: ['paymentStatus'], where, _sum: { totalAmount: true }, _count: true }),
      this.prisma.bill.groupBy({ by: ['paymentMethod'], where, _sum: { totalAmount: true }, _count: true }),
      this.prisma.bill.aggregate({
        where,
        _sum: { subTotal: true, discount: true, serviceCharge: true, vatAmount: true, totalAmount: true },
        _count: true,
      }),
    ]);

    const sumFor = (status: string) =>
      Number(byStatus.find((r) => r.paymentStatus === status)?._sum.totalAmount ?? 0);

    const sales = sumFor('paid');
    const credit = sumFor('credit');
    const grossSales = Number(totals._sum.totalAmount ?? 0);

    const includesFinancials = currentUser.role !== 'cashier';
    let expenses = 0;
    let purchases = 0;
    if (includesFinancials) {
      const [expAgg, purAgg] = await Promise.all([
        this.prisma.expense.aggregate({ where, _sum: { amount: true } }),
        this.prisma.purchase.aggregate({ where, _sum: { totalAmount: true } }),
      ]);
      expenses = Number(expAgg._sum.amount ?? 0);
      purchases = Number(purAgg._sum.totalAmount ?? 0);
    }

    return {
      billCount: totals._count,
      grossSales,
      sales,
      credit,
      discount: Number(totals._sum.discount ?? 0),
      serviceCharge: Number(totals._sum.serviceCharge ?? 0),
      vatAmount: Number(totals._sum.vatAmount ?? 0),
      byPaymentMethod: byMethod
        .map((row) => ({
          paymentMethod: row.paymentMethod,
          count: row._count,
          totalAmount: Number(row._sum.totalAmount ?? 0),
        }))
        .sort((a, b) => b.totalAmount - a.totalAmount),
      includesFinancials,
      expenses,
      purchases,
      netProfit: sales - expenses - purchases,
    };
  }

  async sales(currentUser: CurrentUserPayload, filter: ReportFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = { ...(branchId ? { branchId } : {}), ...dateRange(filter) };

    const [totals, byPaymentMethod] = await Promise.all([
      this.prisma.bill.aggregate({
        where,
        _sum: { subTotal: true, discount: true, serviceCharge: true, vatAmount: true, totalAmount: true },
        _count: true,
      }),
      this.prisma.bill.groupBy({
        by: ['paymentMethod'],
        where,
        _sum: { totalAmount: true },
        _count: true,
      }),
    ]);

    return {
      billCount: totals._count,
      subTotal: Number(totals._sum.subTotal ?? 0),
      discount: Number(totals._sum.discount ?? 0),
      serviceCharge: Number(totals._sum.serviceCharge ?? 0),
      vatAmount: Number(totals._sum.vatAmount ?? 0),
      totalAmount: Number(totals._sum.totalAmount ?? 0),
      byPaymentMethod: byPaymentMethod.map((row) => ({
        paymentMethod: row.paymentMethod,
        count: row._count,
        totalAmount: Number(row._sum.totalAmount ?? 0),
      })),
    };
  }

  async inventory(currentUser: CurrentUserPayload, filter: ReportFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = branchId ? { branchId } : {};

    const items = await this.prisma.inventoryItem.findMany({ where });
    const lowStock = items.filter((item) => Number(item.currentStock) <= Number(item.reorderLevel));

    return {
      totalItems: items.length,
      lowStockCount: lowStock.length,
      lowStockItems: lowStock,
      totalValue: items.reduce(
        (sum, item) => sum + Number(item.currentStock) * Number(item.costPerUnit ?? 0),
        0,
      ),
    };
  }

  async staff(currentUser: CurrentUserPayload, filter: ReportFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = branchId ? { branchId } : {};

    const [staffCount, byRole, byStatus] = await Promise.all([
      this.prisma.staffMember.count({ where }),
      this.prisma.staffMember.groupBy({ by: ['role'], where, _count: true }),
      this.prisma.staffMember.groupBy({ by: ['status'], where, _count: true }),
    ]);

    return {
      staffCount,
      byRole: byRole.map((row) => ({ role: row.role, count: row._count })),
      byStatus: byStatus.map((row) => ({ status: row.status, count: row._count })),
    };
  }

  async revenue(currentUser: CurrentUserPayload, filter: ReportFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = { ...(branchId ? { branchId } : {}), ...dateRange(filter) };

    const [billsAgg, expensesAgg] = await Promise.all([
      this.prisma.bill.aggregate({ where, _sum: { totalAmount: true } }),
      this.prisma.expense.aggregate({ where, _sum: { amount: true } }),
    ]);

    const revenue = Number(billsAgg._sum.totalAmount ?? 0);
    const expenses = Number(expensesAgg._sum.amount ?? 0);

    return { revenue, expenses, netProfit: revenue - expenses };
  }

  /** Top-selling menu items by quantity, excluding cancelled items. */
  async popularItems(currentUser: CurrentUserPayload, filter: ReportFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const rows = await this.prisma.kotItem.groupBy({
      by: ['menuItemId', 'name'],
      where: {
        status: { not: 'cancelled' },
        kot: { ...(branchId ? { branchId } : {}), ...dateRange(filter) },
      },
      _sum: { quantity: true },
      _count: true,
    });

    return rows
      .map((row) => ({
        menuItemId: row.menuItemId,
        name: row.name,
        totalQuantity: row._sum.quantity ?? 0,
        orderCount: row._count,
      }))
      .sort((a, b) => b.totalQuantity - a.totalQuantity)
      .slice(0, 20);
  }

  /** Every cancelled KOT item in range, with the value that was voided. */
  async voidItems(currentUser: CurrentUserPayload, filter: ReportFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const items = await this.prisma.kotItem.findMany({
      where: {
        status: 'cancelled',
        kot: { ...(branchId ? { branchId } : {}), ...dateRange(filter) },
      },
      include: { kot: { select: { kotNumber: true, tableId: true, waiterId: true } } },
      orderBy: { createdAt: 'desc' },
      take: 200,
    });

    const totalValue = items.reduce((sum, item) => sum + Number(item.unitPrice) * item.quantity, 0);
    return { count: items.length, totalValue, items };
  }

  /** Bills that had a discount applied, and the total discounted. */
  async discounts(currentUser: CurrentUserPayload, filter: ReportFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = { ...(branchId ? { branchId } : {}), ...dateRange(filter), discount: { gt: 0 } };

    const [agg, bills] = await Promise.all([
      this.prisma.bill.aggregate({ where, _sum: { discount: true }, _count: true }),
      this.prisma.bill.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        take: 100,
        select: {
          id: true,
          billNumber: true,
          invoiceNumber: true,
          discount: true,
          totalAmount: true,
          cashierName: true,
          createdAt: true,
        },
      }),
    ]);

    return { totalDiscount: Number(agg._sum.discount ?? 0), billCount: agg._count, bills };
  }

  /** Bill volume/revenue bucketed by hour-of-day — needs raw SQL since
   * Prisma's groupBy can't extract a date part. */
  async peakHours(currentUser: CurrentUserPayload, filter: ReportFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const conditions: Prisma.Sql[] = [];
    if (branchId) conditions.push(Prisma.sql`branch_id = ${branchId}`);
    if (filter.from) conditions.push(Prisma.sql`created_at >= ${new Date(filter.from)}`);
    if (filter.to) conditions.push(Prisma.sql`created_at <= ${new Date(filter.to)}`);
    const whereClause =
      conditions.length > 0 ? Prisma.sql`WHERE ${Prisma.join(conditions, ' AND ')}` : Prisma.empty;

    const rows = await this.prisma.$queryRaw<{ hour: number; bill_count: number; total: number }[]>(
      Prisma.sql`
        SELECT EXTRACT(HOUR FROM created_at)::int AS hour,
               COUNT(*)::int AS bill_count,
               COALESCE(SUM(total_amount), 0)::float AS total
        FROM bills
        ${whereClause}
        GROUP BY hour
        ORDER BY hour
      `,
    );

    return rows.map((r) => ({ hour: Number(r.hour), billCount: Number(r.bill_count), total: Number(r.total) }));
  }

  /** Sessions-per-table and average occupied duration, for billed sessions in range. */
  async tableTurnover(currentUser: CurrentUserPayload, filter: ReportFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const sessions = await this.prisma.tableSession.findMany({
      where: {
        ...(branchId ? { branchId } : {}),
        status: 'billed',
        closedAt: { not: null },
        ...dateRange(filter),
      },
      include: { table: { select: { tableNumber: true } } },
    });

    const byTable = new Map<string, { tableNumber: string; sessionCount: number; totalMinutes: number }>();
    for (const session of sessions) {
      if (!session.closedAt) continue;
      const minutes = (session.closedAt.getTime() - session.openedAt.getTime()) / 60000;
      const entry = byTable.get(session.tableId) ?? {
        tableNumber: session.table.tableNumber,
        sessionCount: 0,
        totalMinutes: 0,
      };
      entry.sessionCount += 1;
      entry.totalMinutes += minutes;
      byTable.set(session.tableId, entry);
    }

    return Array.from(byTable.entries())
      .map(([tableId, v]) => ({
        tableId,
        tableNumber: v.tableNumber,
        sessionCount: v.sessionCount,
        avgDurationMinutes: v.sessionCount ? Math.round(v.totalMinutes / v.sessionCount) : 0,
      }))
      .sort((a, b) => b.sessionCount - a.sessionCount);
  }

  /** Bills grouped by the waiter who ran the session — sales per waiter. */
  async waiterPerformance(currentUser: CurrentUserPayload, filter: ReportFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const bills = await this.prisma.bill.findMany({
      where: { ...(branchId ? { branchId } : {}), ...dateRange(filter) },
      select: {
        totalAmount: true,
        session: { select: { waiterId: true, waiter: { select: { fullName: true } } } },
      },
    });

    const byWaiter = new Map<string, { waiterName: string; billCount: number; totalSales: number }>();
    for (const bill of bills) {
      const waiterId = bill.session?.waiterId;
      if (!waiterId) continue;
      const entry = byWaiter.get(waiterId) ?? {
        waiterName: bill.session?.waiter?.fullName ?? 'Unknown',
        billCount: 0,
        totalSales: 0,
      };
      entry.billCount += 1;
      entry.totalSales += Number(bill.totalAmount);
      byWaiter.set(waiterId, entry);
    }

    return Array.from(byWaiter.entries())
      .map(([waiterId, v]) => ({ waiterId, ...v }))
      .sort((a, b) => b.totalSales - a.totalSales);
  }

  /** Average time from KOT creation to "ready", grouped by the kitchen
   * staff who marked it ready (Kot.preparedById / readyAt from Chunk 0/3). */
  async kitchenPerformance(currentUser: CurrentUserPayload, filter: ReportFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const kots = await this.prisma.kot.findMany({
      where: { ...(branchId ? { branchId } : {}), readyAt: { not: null }, ...dateRange(filter) },
      select: {
        readyAt: true,
        createdAt: true,
        preparedById: true,
        preparedBy: { select: { fullName: true } },
      },
    });

    const byChef = new Map<string, { chefName: string; kotCount: number; totalMinutes: number }>();
    let unassignedCount = 0;
    let unassignedMinutes = 0;

    for (const kot of kots) {
      if (!kot.readyAt) continue;
      const minutes = (kot.readyAt.getTime() - kot.createdAt.getTime()) / 60000;
      if (!kot.preparedById) {
        unassignedCount += 1;
        unassignedMinutes += minutes;
        continue;
      }
      const entry = byChef.get(kot.preparedById) ?? {
        chefName: kot.preparedBy?.fullName ?? 'Unknown',
        kotCount: 0,
        totalMinutes: 0,
      };
      entry.kotCount += 1;
      entry.totalMinutes += minutes;
      byChef.set(kot.preparedById, entry);
    }

    const result: { preparedById: string | null; chefName: string; kotCount: number; avgPrepMinutes: number }[] =
      Array.from(byChef.entries()).map(([preparedById, v]) => ({
        preparedById,
        chefName: v.chefName,
        kotCount: v.kotCount,
        avgPrepMinutes: v.kotCount ? Math.round(v.totalMinutes / v.kotCount) : 0,
      }));

    if (unassignedCount > 0) {
      result.push({
        preparedById: null,
        chefName: 'Unassigned',
        kotCount: unassignedCount,
        avgPrepMinutes: Math.round(unassignedMinutes / unassignedCount),
      });
    }

    return result.sort((a, b) => a.avgPrepMinutes - b.avgPrepMinutes);
  }
}
