import { IsUUID } from 'class-validator';

export class TransferSessionDto {
  @IsUUID()
  toTableId: string;
}
