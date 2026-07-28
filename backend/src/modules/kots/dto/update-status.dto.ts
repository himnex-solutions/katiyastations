import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';

export const KOT_STATUS_VALUES = ['pending', 'preparing', 'ready', 'served', 'cancelled'] as const;

export class UpdateStatusDto {
  @IsIn(KOT_STATUS_VALUES)
  status: (typeof KOT_STATUS_VALUES)[number];

  /** Why the order was cancelled — captured only for a cashier-driven cancel so
   * the void is accountable in the audit log. Ignored for other transitions. */
  @IsOptional()
  @IsString()
  @MaxLength(500)
  reason?: string;
}
