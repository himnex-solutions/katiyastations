import { IsNumber, IsOptional, Min } from 'class-validator';

export class GenerateSalaryDto {
  @IsOptional()
  @IsNumber()
  @Min(0)
  amount?: number;
}
