import { IsInt, IsNumber, IsOptional, IsString, IsUUID, Min } from 'class-validator';

export class CreateShiftClosingDto {
  @IsUUID()
  branchId: string;

  @IsOptional()
  @IsString()
  cashierName?: string;

  @IsString()
  date: string;

  @IsOptional()
  @IsNumber()
  @Min(0)
  cashTotal?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  cardTotal?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  esewaTotal?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  khaltiTotal?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  fonepayTotal?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  creditTotal?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  refundTotal?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  totalRevenue?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  netRevenue?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  totalVat?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  totalDiscount?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  totalServiceCharge?: number;

  @IsOptional()
  @IsInt()
  @Min(0)
  billCount?: number;
}
