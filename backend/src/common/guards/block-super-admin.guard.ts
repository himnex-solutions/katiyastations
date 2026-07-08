import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { BLOCK_SUPER_ADMIN_KEY } from '../decorators/block-super-admin.decorator';
import { CurrentUserPayload } from '../decorators/current-user.decorator';

/**
 * Enforced globally (see app.module.ts). Rejects any request made by a
 * super_admin to a route tagged with @BlockSuperAdmin(), regardless of
 * @Roles() configuration on that route.
 */
@Injectable()
export class BlockSuperAdminGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const isBlocked = this.reflector.getAllAndOverride<boolean>(BLOCK_SUPER_ADMIN_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (!isBlocked) return true;

    const { user } = context.switchToHttp().getRequest();
    const currentUser = user as CurrentUserPayload | undefined;

    if (currentUser?.role === 'super_admin') {
      throw new ForbiddenException('Super Admin cannot access financial or personal data');
    }
    return true;
  }
}
