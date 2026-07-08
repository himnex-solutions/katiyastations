import { PartialType, OmitType } from '@nestjs/swagger';
import { IsIn, IsOptional } from 'class-validator';
import { CreateStaffDto } from './create-staff.dto';

export const STAFF_STATUS_VALUES = ['active', 'inactive', 'terminated'] as const;

export class UpdateStaffDto extends PartialType(OmitType(CreateStaffDto, ['branchId'] as const)) {
  @IsOptional()
  @IsIn(STAFF_STATUS_VALUES)
  status?: (typeof STAFF_STATUS_VALUES)[number];
}
