import { IsArray, IsIn, IsOptional, IsString, IsUUID } from 'class-validator';
import { Role } from '../../../common/decorators/roles.decorator';

const ROLES: Role[] = [
  'super_admin',
  'branch_manager',
  'cashier',
  'waiter',
  'kitchen',
  'inventory',
  'accountant',
];

export class CreateNotificationDto {
  @IsUUID()
  branchId: string;

  @IsString()
  title: string;

  @IsString()
  body: string;

  /** Roles whose bell should ring. Omit (or leave empty) to alert the whole branch. */
  @IsOptional()
  @IsArray()
  @IsIn(ROLES, { each: true })
  audience?: Role[];

  /** The user who caused this. Their own bell stays silent. */
  @IsOptional()
  @IsUUID()
  actorId?: string;
}
