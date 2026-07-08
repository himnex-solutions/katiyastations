import { IsNumber, IsOptional, Min } from 'class-validator';

export class SettleCreditDto {
  /** Amount being paid now; omit to mark the full remaining balance paid. */
  @IsOptional()
  @IsNumber()
  @Min(0)
  amount?: number;
}
