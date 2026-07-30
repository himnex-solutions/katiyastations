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
  /** Client-supplied UUID for offline-first creation. When present, the
   * server persists this exact id and returns the existing KOT if it was
   * already created — making a replayed offline order idempotent (no
   * duplicate tickets / double stock deduction). */
  @IsOptional()
  @IsUUID()
  id?: string;

  @IsUUID()
  sessionId: string;

  @IsOptional()
  @IsUUID()
  waiterId?: string;

  /** Free-text note the waiter attaches to the whole order (e.g. "no onions",
   * "serve together"). Printed on the kitchen/bar KOT ticket. */
  @IsOptional()
  @IsString()
  notes?: string;

  @ValidateNested({ each: true })
  @Type(() => CreateKotItemDto)
  @ArrayMinSize(1)
  items: CreateKotItemDto[];
}
