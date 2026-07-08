import { IsString } from 'class-validator';

export class RestoreDto {
  @IsString()
  filename: string;
}
