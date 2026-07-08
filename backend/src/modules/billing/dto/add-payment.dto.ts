import { IsIn, IsNumber, IsOptional, IsString, Min } from 'class-validator';
import { PAYMENT_METHOD_VALUES } from './generate-bill.dto';

/** Records an additional tender against an existing bill — either to
 * cover the remainder of a partial payment, or to split one bill across
 * multiple payment methods (e.g. half cash + half card). */
export class AddPaymentDto {
  @IsIn(PAYMENT_METHOD_VALUES)
  method: (typeof PAYMENT_METHOD_VALUES)[number];

  @IsNumber()
  @Min(0.01)
  amount: number;

  @IsOptional()
  @IsString()
  referenceNumber?: string;

  @IsOptional()
  @IsString()
  device?: string;
}
