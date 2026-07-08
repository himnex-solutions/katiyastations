import { IsNumber, IsOptional, IsString, IsUUID, Min } from 'class-validator';

export class CreateBarStockDto {
  @IsUUID()
  branchId: string;

  @IsString()
  name: string;

  @IsOptional()
  @IsString()
  category?: string;

  @IsOptional()
  @IsNumber()
  @Min(1)
  bottleCapacityMl?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  currentBottles?: number;

  @IsOptional()
  @IsNumber()
  @Min(1)
  pegsMl?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  pricePerPeg?: number;
}
