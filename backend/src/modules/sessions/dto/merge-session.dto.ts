import { IsUUID } from 'class-validator';

export class MergeSessionDto {
  /** The session this one's KOTs and total will be merged into. */
  @IsUUID()
  intoSessionId: string;
}
