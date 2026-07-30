import { IsBoolean, IsDateString, IsIn, IsNumber, IsOptional, IsString, Min } from 'class-validator';

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
  /** Client-generated bill id. Lets a bill settled OFFLINE sync idempotently —
   * replaying it returns the existing bill instead of creating a duplicate. */
  @IsOptional()
  @IsString()
  id?: string;

  /** When the sale actually happened (ISO). For an offline bill synced later,
   * this keeps the sale on the day it was made in reports, not the sync day. */
  @IsOptional()
  @IsDateString()
  soldAt?: string;

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
