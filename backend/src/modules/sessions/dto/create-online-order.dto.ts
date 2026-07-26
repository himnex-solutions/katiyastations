import { IsOptional, IsString } from 'class-validator';

export class CreateOnlineOrderDto {
  /** Optional client-generated id for idempotent create. */
  @IsOptional()
  @IsString()
  id?: string;

  @IsOptional()
  @IsString()
  branchId?: string;

  @IsString()
  customerName: string;

  @IsOptional()
  @IsString()
  customerPhone?: string;

  @IsOptional()
  @IsString()
  customerAddress?: string;
}
