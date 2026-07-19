import { IsInt, IsOptional, IsUUID, Min } from 'class-validator';

export class OpenSessionDto {
  /** Client-supplied UUID for offline-first creation. When present, the
   * server persists this exact id and treats a repeated request with the
   * same id as a no-op (returns the existing session) — so replaying a
   * queued offline "open table" can never create a duplicate. */
  @IsOptional()
  @IsUUID()
  id?: string;

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
