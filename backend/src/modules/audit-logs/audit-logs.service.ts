import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { CurrentUserPayload } from '../../common/decorators/current-user.decorator';
import { resolveBranchScope } from '../../common/utils/branch-scope.util';
import { buildPaginationMeta } from '../../common/dto/pagination.dto';
import { AuditLogFilterDto } from './dto/audit-log-filter.dto';

@Injectable()
export class AuditLogsService {
  constructor(private readonly prisma: PrismaService) {}

  async findAll(currentUser: CurrentUserPayload, filter: AuditLogFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = {
      ...(branchId ? { branchId } : {}),
      ...(filter.tableName ? { tableName: filter.tableName } : {}),
      ...(filter.rowId ? { rowId: filter.rowId } : {}),
      ...(filter.action ? { action: filter.action } : {}),
    };

    const [rows, total] = await Promise.all([
      this.prisma.auditLog.findMany({
        where,
        include: { user: { select: { fullName: true, role: true } } },
        orderBy: { createdAt: 'desc' },
        skip: filter.skip,
        take: filter.take,
      }),
      this.prisma.auditLog.count({ where }),
    ]);

    const items = rows.map(({ user, ...log }) => ({
      ...log,
      userName: user?.fullName ?? 'System',
      userRole: user?.role ?? '',
      module: log.tableName,
    }));

    return { data: items, meta: buildPaginationMeta(total, filter.page ?? 1, filter.take) };
  }

  /** Called by other services to record a mutation for the audit trail. */
  record(params: {
    branchId?: string;
    userId?: string;
    action: string;
    tableName: string;
    rowId?: string;
    oldValues?: unknown;
    newValues?: unknown;
    ipAddress?: string;
    device?: string;
  }) {
    return this.prisma.auditLog.create({
      data: {
        branchId: params.branchId,
        userId: params.userId,
        action: params.action,
        tableName: params.tableName,
        rowId: params.rowId,
        oldValues: params.oldValues as any,
        newValues: params.newValues as any,
        ipAddress: params.ipAddress,
        device: params.device,
      },
    });
  }
}
