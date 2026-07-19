import { IsIn, IsOptional, IsString, MinLength } from 'class-validator';

/**
 * Reverses a *settled* bill. A "void" cancels a bill raised in error (before
 * money should have been kept); a "refund" returns money to a customer who was
 * already charged. Either way the money, any credit record, and the stock that
 * was deducted at order time are reversed — and the manager who did it plus the
 * reason are recorded on the bill and in the audit log.
 */
export class RefundBillDto {
  @IsIn(['void', 'refund'])
  type: 'void' | 'refund';

  @IsString()
  @MinLength(3)
  reason: string;

  /** Method the refund was paid back through (cash/card/…); only meaningful
   * for type 'refund'. Defaults to the bill's original payment method. */
  @IsOptional()
  @IsString()
  refundMethod?: string;
}
