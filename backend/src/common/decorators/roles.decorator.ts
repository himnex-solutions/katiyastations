import { SetMetadata } from '@nestjs/common';

export const ROLES_KEY = 'roles';

export type Role =
  | 'super_admin'
  | 'branch_manager'
  | 'cashier'
  | 'waiter'
  | 'kitchen'
  | 'inventory'
  | 'accountant';

export const Roles = (...roles: Role[]) => SetMetadata(ROLES_KEY, roles);
