import { IsBoolean, IsIn, IsInt, IsOptional, IsString, IsUUID } from 'class-validator';

export const MENU_TYPE_VALUES = ['food', 'drink', 'bar'] as const;

export class CreateCategoryDto {
  @IsUUID()
  branchId: string;

  @IsString()
  name: string;

  @IsOptional()
  @IsIn(MENU_TYPE_VALUES)
  type?: (typeof MENU_TYPE_VALUES)[number];

  @IsOptional()
  @IsInt()
  sortOrder?: number;

  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}
