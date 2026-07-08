import { IsOptional, IsString } from 'class-validator';

export class ReturnItemDto {
  @IsOptional()
  @IsString()
  reason?: string;
}
