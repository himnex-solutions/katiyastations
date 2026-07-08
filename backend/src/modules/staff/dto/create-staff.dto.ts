import { IsNumber, IsOptional, IsString, IsUUID, Min } from 'class-validator';

export class CreateStaffDto {
  @IsUUID()
  branchId: string;

  @IsString()
  name: string;

  @IsString()
  role: string;

  @IsOptional()
  @IsString()
  phone?: string;

  @IsOptional()
  @IsNumber()
  @Min(0)
  salary?: number;

  /** Links this staff record to a login account for self-service attendance. */
  @IsOptional()
  @IsUUID()
  userId?: string;
}
