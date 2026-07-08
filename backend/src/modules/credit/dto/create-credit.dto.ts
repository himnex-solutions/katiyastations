import { IsDateString, IsNumber, IsOptional, IsUUID, Min } from 'class-validator';

export class CreateCreditDto {
  @IsUUID()
  billId: string;

  @IsUUID()
  customerId: string;

  @IsNumber()
  @Min(0)
  amount: number;

  @IsOptional()
  @IsDateString()
  dueDate?: string;
}
