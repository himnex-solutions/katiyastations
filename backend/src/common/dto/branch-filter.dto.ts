import { IsDateString, IsOptional, IsUUID } from 'class-validator';
import { PaginationDto } from './pagination.dto';

export class BranchFilterDto extends PaginationDto {
  @IsOptional()
  @IsUUID()
  branchId?: string;

  /** Optional inclusive lower bound on createdAt (ISO 8601). Callers that want
   * a date-scoped list (e.g. payment history for a past day) send this so the
   * server filters by date instead of the client sifting a capped recent page.
   * Ignored by endpoints that don't read it. */
  @IsOptional()
  @IsDateString()
  startDate?: string;

  /** Optional exclusive upper bound on createdAt (ISO 8601). */
  @IsOptional()
  @IsDateString()
  endDate?: string;
}
