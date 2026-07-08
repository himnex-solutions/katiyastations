import { PartialType, OmitType } from '@nestjs/swagger';
import { CreateMenuItemDto } from './create-menu-item.dto';

export class UpdateMenuItemDto extends PartialType(OmitType(CreateMenuItemDto, ['branchId'] as const)) {}
