import { PartialType, OmitType } from '@nestjs/swagger';
import { CreateBarStockDto } from './create-bar-stock.dto';

export class UpdateBarStockDto extends PartialType(OmitType(CreateBarStockDto, ['branchId'] as const)) {}
