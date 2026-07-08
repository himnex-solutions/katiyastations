import { IsIn, IsOptional } from 'class-validator';
import { BranchFilterDto } from '../../../common/dto/branch-filter.dto';

export class FindSessionsDto extends BranchFilterDto {
  @IsOptional()
  @IsIn(['open', 'closed', 'billed'])
  status?: 'open' | 'closed' | 'billed';
}
