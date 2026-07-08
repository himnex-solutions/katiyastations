import { IsBoolean, IsEmail, IsIn, IsOptional, IsString, IsUUID, MinLength } from 'class-validator';
import { Role } from '../../../common/decorators/roles.decorator';

export const ROLE_VALUES: Role[] = [
  'super_admin',
  'branch_manager',
  'cashier',
  'waiter',
  'kitchen',
  'inventory',
  'accountant',
];

export class CreateUserDto {
  @IsEmail()
  email: string;

  @IsString()
  @MinLength(8)
  password: string;

  @IsString()
  fullName: string;

  @IsIn(ROLE_VALUES)
  role: Role;

  @IsOptional()
  @IsUUID()
  branchId?: string;

  @IsOptional()
  @IsString()
  phone?: string;

  @IsOptional()
  @IsString()
  avatarUrl?: string;

  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}
