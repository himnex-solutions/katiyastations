import { IsDateString, IsIn, IsOptional, IsUUID } from 'class-validator';

/**
 * The window a payment purge applies to.
 *
 * [startDate] is inclusive and [endDate] exclusive — the same half-open window
 * BillingService.findAll uses, so a day boundary belongs to exactly one day and
 * a purge of the 12th cannot also take the first instant of the 13th.
 *
 * Both are full ISO instants, not calendar dates: the client picks a day on the
 * Nepal calendar and converts it, exactly as the payment-history list already
 * does. Sending instants keeps the record that gets deleted identical to the
 * record the manager was shown.
 */
export class PaymentPurgeRangeDto {
  @IsOptional()
  @IsUUID()
  branchId?: string;

  @IsDateString()
  startDate!: string;

  @IsDateString()
  endDate!: string;
}

export class PurgePaymentsDto extends PaymentPurgeRangeDto {
  /** Must be the literal word DELETE. A destructive call should never be one
   * malformed request away from succeeding. */
  @IsIn(['DELETE'])
  confirm!: string;
}
