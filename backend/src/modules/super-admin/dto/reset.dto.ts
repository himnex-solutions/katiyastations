import { IsString } from 'class-validator';

export class ResetDto {
  /** Must be the literal word "RESET" — a typed guard against accidental wipes. */
  @IsString()
  confirm: string;
}
