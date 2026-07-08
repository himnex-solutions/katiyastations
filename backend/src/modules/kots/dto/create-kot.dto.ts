import { Type } from 'class-transformer';
import { ArrayMinSize, IsInt, IsOptional, IsString, IsUUID, Min, ValidateNested } from 'class-validator';

export class CreateKotItemDto {
  @IsUUID()
  menuItemId: string;

  @IsString()
  name: string;

  @IsInt()
  @Min(1)
  quantity: number;

  @IsOptional()
  @IsString()
  note?: string;
}

export class CreateKotDto {
  @IsUUID()
  sessionId: string;

  @IsOptional()
  @IsUUID()
  waiterId?: string;

  @ValidateNested({ each: true })
  @Type(() => CreateKotItemDto)
  @ArrayMinSize(1)
  items: CreateKotItemDto[];
}
