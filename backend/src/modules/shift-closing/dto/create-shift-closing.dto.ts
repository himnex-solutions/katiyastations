import { IsInt, IsNumber, IsOptional, IsString, IsUUID, Min } from 'class-validator';

export class CreateShiftClosingDto {
  @IsUUID()
  branchId: string;

  @IsOptional()
  @IsString()
  cashierName?: string;

  @IsString()
  date: string;

  // Human-observed inputs — the only figures the cashier actually supplies.
  // Everything below (cashTotal … billCount) is recomputed server-side and
  // kept optional purely for backward compatibility with older clients.
  @IsOptional()
  @IsNumber()
  @Min(0)
  openingFloat?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  countedCash?: number;

  @IsOptional()
  @IsString()
  notes?: string;

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
