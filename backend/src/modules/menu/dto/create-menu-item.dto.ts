import { IsBoolean, IsIn, IsNumber, IsOptional, IsString, IsUUID } from 'class-validator';
import { MENU_TYPE_VALUES } from './create-category.dto';

export class CreateMenuItemDto {
  @IsUUID()
  branchId: string;

  @IsUUID()
  categoryId: string;

  @IsString()
  name: string;

  @IsNumber()
  price: number;

  @IsOptional()
  @IsNumber()
  costPrice?: number;

  @IsOptional()
  @IsNumber()
  taxRate?: number;

  @IsOptional()
  @IsString()
  description?: string;

  @IsOptional()
  @IsString()
  imageUrl?: string;

  @IsOptional()
  @IsBoolean()
  isAvailable?: boolean;

  @IsOptional()
  @IsIn(MENU_TYPE_VALUES)
  type?: (typeof MENU_TYPE_VALUES)[number];

  // Bar link: when set, selling this item auto-deducts `pegsPerServing` pegs
  // from the given BarStock bottle on KOT create. Send null to unlink.
  @IsOptional()
  @IsUUID()
  barStockId?: string | null;

  @IsOptional()
  @IsNumber()
  pegsPerServing?: number | null;
}
