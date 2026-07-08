import { SetMetadata } from '@nestjs/common';

export const BLOCK_SUPER_ADMIN_KEY = 'blockSuperAdmin';

/**
 * Marks a route as off-limits to the super_admin role.
 * Super Admin is a system-operations role and must never see financial
 * or personal data (billing, credit, reports, payroll, customers).
 */
export const BlockSuperAdmin = () => SetMetadata(BLOCK_SUPER_ADMIN_KEY, true);
