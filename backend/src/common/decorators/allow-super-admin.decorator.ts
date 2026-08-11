import { SetMetadata } from '@nestjs/common';
import { BLOCK_SUPER_ADMIN_KEY } from './block-super-admin.decorator';

/**
 * Re-opens ONE route on a controller that is otherwise @BlockSuperAdmin().
 *
 * BlockSuperAdminGuard resolves the flag with getAllAndOverride([handler,
 * class]), so handler metadata wins: this lets a single endpoint through
 * without weakening the class-level rule for any of its siblings.
 *
 * Use it sparingly, and say at the call site why the exception is justified.
 * The boundary exists so a system-operations account cannot read the
 * restaurant's takings, and every hole in it is a hole someone has to defend.
 */
export const AllowSuperAdmin = () => SetMetadata(BLOCK_SUPER_ADMIN_KEY, false);
