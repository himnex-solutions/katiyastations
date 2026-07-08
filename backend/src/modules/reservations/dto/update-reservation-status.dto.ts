import { IsIn } from 'class-validator';

export const RESERVATION_STATUS_VALUES = [
  'pending',
  'confirmed',
  'arrived',
  'completed',
  'cancelled',
  'no_show',
] as const;

export class UpdateReservationStatusDto {
  @IsIn(RESERVATION_STATUS_VALUES)
  status: (typeof RESERVATION_STATUS_VALUES)[number];
}
