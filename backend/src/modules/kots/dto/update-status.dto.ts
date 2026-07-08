import { IsIn } from 'class-validator';

export const KOT_STATUS_VALUES = ['pending', 'preparing', 'ready', 'served', 'cancelled'] as const;

export class UpdateStatusDto {
  @IsIn(KOT_STATUS_VALUES)
  status: (typeof KOT_STATUS_VALUES)[number];
}
