import { IsOptional, IsUUID } from 'class-validator';
import { PaginationDto } from './pagination.dto';

export class BranchFilterDto extends PaginationDto {
  @IsOptional()
  @IsUUID()
  branchId?: string;
}
