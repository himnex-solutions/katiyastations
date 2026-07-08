import { IsIn, IsNumber, IsOptional, IsString, Min } from 'class-validator';

export const STOCK_MOVEMENT_TYPE_VALUES = ['in', 'out', 'adjustment', 'waste'] as const;

export class AdjustStockDto {
  @IsIn(STOCK_MOVEMENT_TYPE_VALUES)
  type: (typeof STOCK_MOVEMENT_TYPE_VALUES)[number];

  @IsNumber()
  @Min(0.0001)
  quantity: number;

  @IsOptional()
  @IsString()
  reason?: string;
}
