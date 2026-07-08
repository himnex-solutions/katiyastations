import { ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import * as argon2 from 'argon2';
import { PrismaService } from '../../prisma/prisma.service';
import { CreateUserDto } from './dto/create-user.dto';
import { UpdateUserDto } from './dto/update-user.dto';
import { ResetPasswordDto } from './dto/reset-password.dto';
import { BranchFilterDto } from '../../common/dto/branch-filter.dto';
import { buildPaginationMeta } from '../../common/dto/pagination.dto';
import { CurrentUserPayload } from '../../common/decorators/current-user.decorator';
import { resolveBranchScope } from '../../common/utils/branch-scope.util';
import { AuditLogsService } from '../audit-logs/audit-logs.service';
import { RealtimeService } from '../websocket/realtime.service';

const SAFE_SELECT = {
  id: true,
  email: true,
  fullName: true,
  role: true,
  branchId: true,
  phone: true,
  avatarUrl: true,
  isActive: true,
  createdAt: true,
  updatedAt: true,
  branch: { select: { name: true } },
};

function toResponse(user: any) {
  const { branch, ...rest } = user;
  return { ...rest, branchName: branch?.name ?? null };
}

@Injectable()
export class UsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditLogs: AuditLogsService,
    private readonly realtime: RealtimeService,
  ) {}

  /**
   * A branch_manager may only create/edit/block/delete accounts that live in
   * their own branch, and may never touch a super_admin (whose branchId is
   * null and therefore never matches). super_admin may manage anyone.
   */
  private assertCanManage(currentUser: CurrentUserPayload, targetBranchId: string | null) {
    if (currentUser.role === 'super_admin') return;
    if (!currentUser.branchId) {
      throw new ForbiddenException('Your account is not assigned to a branch');
    }
    if (targetBranchId !== currentUser.branchId) {
      throw new ForbiddenException('You can only manage users in your own branch');
    }
  }

  /** Only a super_admin may create or promote another super_admin. */
  private assertCanAssignRole(currentUser: CurrentUserPayload, role?: string) {
    if (role === 'super_admin' && currentUser.role !== 'super_admin') {
      throw new ForbiddenException('Only a super admin can grant the super admin role');
    }
  }

  /** Push a fresh copy of the user to everyone watching that branch's room. */
  private emitUserChanged(user: { branchId: string | null } & Record<string, any>) {
    if (user.branchId) {
      this.realtime.userChanged(user.branchId, toResponse(user));
    }
  }

  async findAll(currentUser: CurrentUserPayload, filter: BranchFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = {
      ...(branchId ? { branchId } : {}),
      ...(filter.search
        ? {
            OR: [
              { fullName: { contains: filter.search, mode: 'insensitive' as const } },
              { email: { contains: filter.search, mode: 'insensitive' as const } },
            ],
          }
        : {}),
    };

    const [rows, total] = await Promise.all([
      this.prisma.user.findMany({
        where,
        select: SAFE_SELECT,
        skip: filter.skip,
        take: filter.take,
        orderBy: { fullName: 'asc' },
      }),
      this.prisma.user.count({ where }),
    ]);

    return { data: rows.map(toResponse), meta: buildPaginationMeta(total, filter.page ?? 1, filter.take) };
  }

  async findOne(id: string) {
    const user = await this.prisma.user.findUnique({ where: { id }, select: SAFE_SELECT });
    if (!user) throw new NotFoundException('User not found');
    return toResponse(user);
  }

  async create(currentUser: CurrentUserPayload, dto: CreateUserDto) {
    // A manager can only ever create inside their own branch; resolveBranchScope
    // both pins the branch and rejects an attempt to target another one.
    const branchId = resolveBranchScope(currentUser, dto.branchId);
    if (currentUser.role !== 'super_admin' && !branchId) {
      throw new ForbiddenException('Your account is not assigned to a branch');
    }
    this.assertCanAssignRole(currentUser, dto.role);

    const existing = await this.prisma.user.findUnique({ where: { email: dto.email.trim().toLowerCase() } });
    if (existing) throw new ConflictException('A user with this email already exists');

    const passwordHash = await argon2.hash(dto.password);
    const user = await this.prisma.user.create({
      data: {
        email: dto.email.trim().toLowerCase(),
        passwordHash,
        fullName: dto.fullName,
        role: dto.role,
        branchId: branchId ?? null,
        phone: dto.phone,
        avatarUrl: dto.avatarUrl,
        isActive: dto.isActive ?? true,
      },
      select: SAFE_SELECT,
    });

    await this.auditLogs.record({
      branchId: user.branchId ?? undefined,
      userId: currentUser.userId,
      action: 'created',
      tableName: 'users',
      rowId: user.id,
      newValues: { fullName: user.fullName, role: user.role },
    });

    this.emitUserChanged(user);
    return toResponse(user);
  }

  async update(id: string, currentUser: CurrentUserPayload, dto: UpdateUserDto) {
    const before = await this.findOne(id);
    this.assertCanManage(currentUser, before.branchId);
    this.assertCanAssignRole(currentUser, dto.role);

    // Never let a manager move a user into (or out of) another branch.
    const data: UpdateUserDto = { ...dto };
    if (data.branchId !== undefined) {
      data.branchId = resolveBranchScope(currentUser, data.branchId) ?? undefined;
    }

    const updated = await this.prisma.user.update({ where: { id }, data, select: SAFE_SELECT });

    if (dto.role && dto.role !== before.role) {
      await this.auditLogs.record({
        branchId: updated.branchId ?? undefined,
        userId: currentUser.userId,
        action: 'role_changed',
        tableName: 'users',
        rowId: id,
        oldValues: { role: before.role },
        newValues: { role: dto.role },
      });
    }

    this.emitUserChanged(updated);
    return toResponse(updated);
  }

  async toggleActive(id: string, currentUser: CurrentUserPayload) {
    const user = await this.findOne(id);
    this.assertCanManage(currentUser, user.branchId);
    if (id === currentUser.userId) {
      throw new ForbiddenException('You cannot block your own account');
    }

    const updated = await this.prisma.user.update({
      where: { id },
      data: { isActive: !user.isActive },
      select: SAFE_SELECT,
    });

    if (!updated.isActive) {
      // A blocked user must not keep an active session anywhere.
      await this.prisma.refreshToken.updateMany({
        where: { userId: id, revoked: false },
        data: { revoked: true },
      });
    }

    await this.auditLogs.record({
      branchId: updated.branchId ?? undefined,
      userId: currentUser.userId,
      action: updated.isActive ? 'unblocked' : 'blocked',
      tableName: 'users',
      rowId: id,
    });

    this.emitUserChanged(updated);
    return toResponse(updated);
  }

  /**
   * Permanently deletes a user account. Operational history (bills, KOTs,
   * sessions, payments, audit logs) is preserved — those foreign keys are
   * ON DELETE SET NULL — while login/device/reset tokens cascade away. A
   * manager may only delete users in their own branch and never themselves.
   */
  async remove(id: string, currentUser: CurrentUserPayload) {
    const target = await this.findOne(id);
    this.assertCanManage(currentUser, target.branchId);
    if (id === currentUser.userId) {
      throw new ForbiddenException('You cannot delete your own account');
    }

    await this.prisma.user.delete({ where: { id } });

    await this.auditLogs.record({
      branchId: target.branchId ?? undefined,
      userId: currentUser.userId,
      action: 'deleted',
      tableName: 'users',
      rowId: id,
      oldValues: { fullName: target.fullName, email: target.email, role: target.role },
    });

    // Signal removal so watching clients drop the row from their list.
    if (target.branchId) {
      this.realtime.userChanged(target.branchId, { id, deleted: true });
    }
    return { success: true };
  }

  /**
   * Admin password reset — no current password required. super_admin may
   * target any user; branch_manager may only target users in their own
   * branch (also true for super_admins, whose branchId is null and so
   * never matches, keeping them out of a manager's reach).
   */
  async resetPassword(id: string, currentUser: CurrentUserPayload, dto: ResetPasswordDto) {
    const target = await this.findOne(id);
    this.assertCanManage(currentUser, target.branchId);

    const passwordHash = await argon2.hash(dto.newPassword);
    await this.prisma.user.update({ where: { id }, data: { passwordHash } });

    // Force re-login everywhere, same as a self-service password change.
    await this.prisma.refreshToken.updateMany({
      where: { userId: id, revoked: false },
      data: { revoked: true },
    });

    await this.auditLogs.record({
      branchId: target.branchId ?? undefined,
      userId: currentUser.userId,
      action: 'password_reset',
      tableName: 'users',
      rowId: id,
    });

    return { success: true };
  }
}
