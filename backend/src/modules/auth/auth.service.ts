import {
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import * as argon2 from 'argon2';
import { randomUUID } from 'crypto';
import { PrismaService } from '../../prisma/prisma.service';
import { LoginDto } from './dto/login.dto';
import { ChangePasswordDto } from './dto/change-password.dto';
import { AccessTokenPayload, RefreshTokenPayload } from './interfaces/jwt-payload.interface';
import { toSnakeCase } from '../../common/utils/case.util';
import { AuditLogsService } from '../audit-logs/audit-logs.service';

export interface RequestMeta {
  ipAddress?: string;
  device?: string;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
    private readonly auditLogs: AuditLogsService,
  ) {}

  async login(dto: LoginDto, meta: RequestMeta = {}) {
    const email = dto.email.trim().toLowerCase();
    const user = await this.prisma.user.findUnique({ where: { email } });

    if (!user || !(await argon2.verify(user.passwordHash, dto.password))) {
      await this.auditLogs.record({
        userId: user?.id,
        branchId: user?.branchId ?? undefined,
        action: 'login_failed',
        tableName: 'users',
        rowId: user?.id,
        newValues: { email },
        ...meta,
      });
      throw new UnauthorizedException('Invalid email or password');
    }

    if (!user.isActive) {
      await this.auditLogs.record({
        userId: user.id,
        branchId: user.branchId ?? undefined,
        action: 'login_failed',
        tableName: 'users',
        rowId: user.id,
        newValues: { reason: 'deactivated' },
        ...meta,
      });
      throw new ForbiddenException('Your account has been deactivated. Contact your administrator.');
    }

    const tokens = await this.issueTokens(user.id, user.email, user.role, user.branchId);

    await this.auditLogs.record({
      userId: user.id,
      branchId: user.branchId ?? undefined,
      action: 'login',
      tableName: 'users',
      rowId: user.id,
      ...meta,
    });

    // accessToken/refreshToken stay camelCase; `user` is snake_cased to
    // match UserProfile.fromJson. See @RawResponse() on AuthController.
    return {
      ...tokens,
      user: toSnakeCase({
        id: user.id,
        fullName: user.fullName,
        role: user.role,
        branchId: user.branchId,
        phone: user.phone,
        avatarUrl: user.avatarUrl,
        isActive: user.isActive,
        createdAt: user.createdAt,
      }),
    };
  }

  async refresh(refreshToken: string) {
    let payload: RefreshTokenPayload;
    try {
      payload = await this.jwtService.verifyAsync<RefreshTokenPayload>(refreshToken, {
        secret: this.configService.get<string>('jwt.refreshSecret'),
      });
    } catch {
      throw new UnauthorizedException('Invalid or expired refresh token');
    }

    const stored = await this.prisma.refreshToken.findUnique({ where: { id: payload.jti } });
    if (!stored || stored.revoked || stored.userId !== payload.sub || stored.expiresAt < new Date()) {
      throw new UnauthorizedException('Refresh token is no longer valid');
    }

    const user = await this.prisma.user.findUnique({ where: { id: payload.sub } });
    if (!user || !user.isActive) {
      throw new UnauthorizedException('User not found or deactivated');
    }

    // Rotate: revoke the used refresh token and issue a new pair
    await this.prisma.refreshToken.update({
      where: { id: stored.id },
      data: { revoked: true },
    });

    return this.issueTokens(user.id, user.email, user.role, user.branchId);
  }

  /** Logs the user out of all sessions (all outstanding refresh tokens revoked). */
  async logout(userId: string, meta: RequestMeta = {}) {
    await this.prisma.refreshToken.updateMany({
      where: { userId, revoked: false },
      data: { revoked: true },
    });
    await this.auditLogs.record({
      userId,
      action: 'logout',
      tableName: 'users',
      rowId: userId,
      ...meta,
    });
  }

  async me(userId: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new UnauthorizedException('User not found');

    return {
      id: user.id,
      fullName: user.fullName,
      role: user.role,
      branchId: user.branchId,
      phone: user.phone,
      avatarUrl: user.avatarUrl,
      isActive: user.isActive,
      createdAt: user.createdAt,
    };
  }

  async changePassword(userId: string, dto: ChangePasswordDto) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new UnauthorizedException('User not found');

    if (!(await argon2.verify(user.passwordHash, dto.currentPassword))) {
      throw new UnauthorizedException('Current password is incorrect');
    }

    const passwordHash = await argon2.hash(dto.newPassword);
    await this.prisma.user.update({ where: { id: userId }, data: { passwordHash } });

    // Force re-login everywhere on password change
    await this.prisma.refreshToken.updateMany({
      where: { userId, revoked: false },
      data: { revoked: true },
    });
  }

  async forgotPassword(email: string) {
    const user = await this.prisma.user.findUnique({ where: { email: email.trim().toLowerCase() } });
    // Always respond success to avoid leaking which emails are registered.
    if (!user) return;

    const token = randomUUID();
    const tokenHash = await argon2.hash(token);
    await this.prisma.passwordResetToken.create({
      data: {
        userId: user.id,
        tokenHash,
        expiresAt: new Date(Date.now() + 60 * 60 * 1000), // 1 hour
      },
    });

    // TODO: wire to an email provider once one is chosen; for now the
    // token must be relayed to the user out-of-band (e.g. by an admin).
    return { token };
  }

  async resetPassword(token: string, newPassword: string) {
    const candidates = await this.prisma.passwordResetToken.findMany({
      where: { used: false, expiresAt: { gt: new Date() } },
      orderBy: { createdAt: 'desc' },
    });

    const match = await this.findMatchingToken(candidates, token);
    if (!match) throw new UnauthorizedException('Invalid or expired reset token');

    const passwordHash = await argon2.hash(newPassword);
    await this.prisma.$transaction([
      this.prisma.user.update({ where: { id: match.userId }, data: { passwordHash } }),
      this.prisma.passwordResetToken.update({ where: { id: match.id }, data: { used: true } }),
      this.prisma.refreshToken.updateMany({
        where: { userId: match.userId, revoked: false },
        data: { revoked: true },
      }),
    ]);
  }

  private async findMatchingToken<T extends { tokenHash: string }>(
    candidates: T[],
    plainToken: string,
  ): Promise<T | undefined> {
    for (const candidate of candidates) {
      if (await argon2.verify(candidate.tokenHash, plainToken)) return candidate;
    }
    return undefined;
  }

  private async issueTokens(userId: string, email: string, role: string, branchId: string | null) {
    const accessPayload: AccessTokenPayload = { sub: userId, email, role, branchId };
    const accessToken = await this.jwtService.signAsync(accessPayload, {
      secret: this.configService.get<string>('jwt.accessSecret'),
      expiresIn: this.configService.get<string>('jwt.accessExpiresIn'),
    });

    const refreshExpiresIn = this.configService.get<string>('jwt.refreshExpiresIn') ?? '30d';
    const record = await this.prisma.refreshToken.create({
      data: {
        userId,
        expiresAt: addDuration(new Date(), refreshExpiresIn),
      },
    });

    const refreshPayload: RefreshTokenPayload = { sub: userId, jti: record.id };
    const refreshToken = await this.jwtService.signAsync(refreshPayload, {
      secret: this.configService.get<string>('jwt.refreshSecret'),
      expiresIn: refreshExpiresIn,
    });

    return { accessToken, refreshToken };
  }
}

function addDuration(date: Date, duration: string): Date {
  const match = /^(\d+)([smhd])$/.exec(duration);
  if (!match) return new Date(date.getTime() + 30 * 24 * 60 * 60 * 1000); // default 30d
  const amount = parseInt(match[1], 10);
  const unitMs = { s: 1000, m: 60_000, h: 3_600_000, d: 86_400_000 }[match[2]]!;
  return new Date(date.getTime() + amount * unitMs);
}
