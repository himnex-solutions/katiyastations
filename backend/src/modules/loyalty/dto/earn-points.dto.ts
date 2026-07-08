import { IsInt, IsNumber, IsOptional, IsString, Min } from 'class-validator';

export class EarnPointsDto {
  @IsInt()
  @Min(1)
  points: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  purchaseAmount?: number;

  @IsOptional()
  @IsString()
  notes?: string;
}
