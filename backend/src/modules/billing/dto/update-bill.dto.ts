import { IsIn, IsOptional } from 'class-validator';
import { PAYMENT_METHOD_VALUES } from './generate-bill.dto';

export const PAYMENT_STATUS_VALUES = ['paid', 'partial_paid', 'credit', 'refunded'] as const;

export class UpdateBillDto {
  @IsOptional()
  @IsIn(PAYMENT_METHOD_VALUES)
  paymentMethod?: (typeof PAYMENT_METHOD_VALUES)[number];

  @IsOptional()
  @IsIn(PAYMENT_STATUS_VALUES)
  paymentStatus?: (typeof PAYMENT_STATUS_VALUES)[number];
}
