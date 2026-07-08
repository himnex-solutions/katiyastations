import { IsIn } from 'class-validator';

export const PURCHASE_STATUS_VALUES = ['pending', 'completed', 'cancelled'] as const;

export class UpdatePurchaseDto {
  @IsIn(PURCHASE_STATUS_VALUES)
  status: (typeof PURCHASE_STATUS_VALUES)[number];
}
