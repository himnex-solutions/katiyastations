import { IsInt, IsOptional, IsUUID, Min } from 'class-validator';

export class OpenSessionDto {
  @IsOptional()
  @IsInt()
  @Min(1)
  guestCount?: number;

  @IsOptional()
  @IsUUID()
  customerId?: string;

  /** Explicit waiter override — if omitted, the server assigns one
   * automatically (see TablesService.openSession). */
  @IsOptional()
  @IsUUID()
  waiterId?: string;
}
