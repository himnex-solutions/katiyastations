import { IsOptional, IsString } from 'class-validator';

export class HoldSessionDto {
  @IsOptional()
  @IsString()
  reason?: string;
}
