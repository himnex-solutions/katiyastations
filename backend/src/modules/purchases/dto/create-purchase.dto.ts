import { Type } from 'class-transformer';
import { IsArray, IsNumber, IsOptional, IsString, IsUUID, Min, ValidateNested } from 'class-validator';

export class CreatePurchaseItemDto {
  @IsUUID()
  inventoryItemId: string;

  @IsNumber()
  @Min(0.0001)
  quantity: number;

  @IsNumber()
  @Min(0)
  unitCost: number;
}

export class CreatePurchaseDto {
  @IsUUID()
  branchId: string;

  @IsOptional()
  @IsUUID()
  supplierId?: string;

  /** Free-text supplier name, used when no linked Supplier record is selected. */
  @IsOptional()
  @IsString()
  supplierName?: string;

  @IsOptional()
  @IsString()
  notes?: string;

  /** When quick-logging a purchase total without itemized stock, omit or leave empty. */
  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CreatePurchaseItemDto)
  items?: CreatePurchaseItemDto[];

  /** Required when items is omitted (quick-log flow computes its own total otherwise). */
  @IsOptional()
  @IsNumber()
  @Min(0)
  totalAmount?: number;
}
