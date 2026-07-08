import { ForbiddenException } from '@nestjs/common';
import { CurrentUserPayload } from '../decorators/current-user.decorator';

/**
 * Enforces branch data isolation (mirrors the RLS policies from the
 * original Supabase schema): super_admin may query any branch (or all
 * branches when none is given); every other role is pinned to their
 * own branch and may not request another one.
 */
export function resolveBranchScope(user: CurrentUserPayload, requestedBranchId?: string): string | undefined {
  if (user.role === 'super_admin') {
    return requestedBranchId;
  }

  if (!user.branchId) {
    throw new ForbiddenException('Your account is not assigned to a branch');
  }

  if (requestedBranchId && requestedBranchId !== user.branchId) {
    throw new ForbiddenException('You cannot access data from another branch');
  }

  return user.branchId;
}
