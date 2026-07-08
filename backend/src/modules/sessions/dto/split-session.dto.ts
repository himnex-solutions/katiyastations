import { ArrayMinSize, IsArray, IsInt, IsOptional, IsUUID, Min } from 'class-validator';

export class SplitSessionDto {
  @IsUUID()
  toTableId: string;

  @IsArray()
  @ArrayMinSize(1)
  @IsUUID('4', { each: true })
  kotIds: string[];

  @IsOptional()
  @IsInt()
  @Min(1)
  guestCount?: number;
}
