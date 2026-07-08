import { PartialType, OmitType } from '@nestjs/swagger';
import { IsBoolean, IsIn, IsOptional, IsString } from 'class-validator';
import { CreateTableDto } from './create-table.dto';

export const TABLE_STATUS_VALUES = [
  'available',
  'occupied',
  'reserved',
  'cleaning',
  'ready_for_billing',
  'closed',
] as const;

export class UpdateTableDto extends PartialType(OmitType(CreateTableDto, ['branchId'] as const)) {
  @IsOptional()
  @IsIn(TABLE_STATUS_VALUES)
  status?: (typeof TABLE_STATUS_VALUES)[number];

  @IsOptional()
  @IsString()
  description?: string;

  @IsOptional()
  @IsBoolean()
  isEnabled?: boolean;
}
