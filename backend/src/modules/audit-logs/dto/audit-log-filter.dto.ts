import { IsOptional, IsString } from 'class-validator';
import { BranchFilterDto } from '../../../common/dto/branch-filter.dto';

/** Adds the filters needed for a per-record audit timeline (e.g. every
 * action logged against one table_sessions row) on top of the existing
 * branch/pagination filter. */
export class AuditLogFilterDto extends BranchFilterDto {
  @IsOptional()
  @IsString()
  tableName?: string;

  @IsOptional()
  @IsString()
  rowId?: string;

  @IsOptional()
  @IsString()
  action?: string;
}
