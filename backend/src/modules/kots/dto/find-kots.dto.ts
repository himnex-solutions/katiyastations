import { IsOptional, IsString, IsUUID } from 'class-validator';
import { PaginationDto } from '../../../common/dto/pagination.dto';

export class FindKotsDto extends PaginationDto {
  @IsOptional()
  @IsUUID()
  branchId?: string;

  /** Comma-separated list of statuses, e.g. "pending,preparing,ready" */
  @IsOptional()
  @IsString()
  status?: string;
}
