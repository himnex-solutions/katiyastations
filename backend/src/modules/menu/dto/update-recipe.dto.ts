import { IsOptional, IsString } from 'class-validator';

export class UpdateRecipeDto {
  @IsOptional()
  @IsString()
  instructions?: string;
}
