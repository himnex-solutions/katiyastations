import { PartialType, OmitType } from '@nestjs/swagger';
import { CreateReservationDto } from './create-reservation.dto';

export class UpdateReservationDto extends PartialType(
  OmitType(CreateReservationDto, ['branchId'] as const),
) {}
