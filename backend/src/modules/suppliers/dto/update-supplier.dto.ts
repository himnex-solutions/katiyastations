import { PartialType, OmitType } from '@nestjs/swagger';
import { CreateSupplierDto } from './create-supplier.dto';

export class UpdateSupplierDto extends PartialType(OmitType(CreateSupplierDto, ['branchId'] as const)) {}
