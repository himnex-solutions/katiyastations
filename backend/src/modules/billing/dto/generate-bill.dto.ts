import { IsBoolean, IsIn, IsNumber, IsOptional, IsString, Min } from 'class-validator';

export const PAYMENT_METHOD_VALUES = [
  'cash',
  'card',
  'esewa',
  'khalti',
  'fonepay',
  'qr',
  'upi',
  'bank_transfer',
  'credit',
] as const;

export class GenerateBillDto {
  @IsOptional()
  @IsNumber()
  @Min(0)
  discount?: number;

  @IsOptional()
  @IsIn(PAYMENT_METHOD_VALUES)
  paymentMethod?: (typeof PAYMENT_METHOD_VALUES)[number];

  @IsOptional()
  @IsNumber()
  @Min(0)
  amountPaid?: number;

  @IsOptional()
  @IsString()
  customerName?: string;

  @IsOptional()
  @IsString()
  customerPhone?: string;

  /** Both default false — service charge/VAT are opt-in per bill, matching the cashier UI toggles. */
  @IsOptional()
  @IsBoolean()
  applyServiceCharge?: boolean;

  @IsOptional()
  @IsBoolean()
  applyVat?: boolean;
}
