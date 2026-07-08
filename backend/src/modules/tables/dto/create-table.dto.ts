import { IsInt, IsOptional, IsString, IsUUID, Min } from 'class-validator';

export class CreateTableDto {
  @IsUUID()
  branchId: string;

  @IsString()
  tableNumber: string;

  @IsOptional()
  @IsString()
  section?: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  capacity?: number;
}
