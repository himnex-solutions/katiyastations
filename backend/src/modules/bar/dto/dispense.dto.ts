import { IsIn, IsNumber, IsOptional, Min } from 'class-validator';

export const BAR_TRANSACTION_TYPE_VALUES = ['in', 'out', 'spill', 'audit'] as const;

export class DispenseDto {
  @IsOptional()
  @IsIn(BAR_TRANSACTION_TYPE_VALUES)
  type?: (typeof BAR_TRANSACTION_TYPE_VALUES)[number];

  /** Number of pegs poured (converted to bottle-fraction using the item's pegsMl / bottleCapacityMl). */
  @IsNumber()
  @Min(0.01)
  pegs: number;
}
