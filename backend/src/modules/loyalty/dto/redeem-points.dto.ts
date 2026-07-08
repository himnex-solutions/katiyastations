import { IsInt, IsOptional, IsString, Min } from 'class-validator';

export class RedeemPointsDto {
  @IsInt()
  @Min(1)
  points: number;

  @IsOptional()
  @IsString()
  notes?: string;
}
