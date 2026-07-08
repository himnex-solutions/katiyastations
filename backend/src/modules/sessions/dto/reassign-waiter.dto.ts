import { IsUUID } from 'class-validator';

export class ReassignWaiterDto {
  @IsUUID()
  waiterId: string;
}
