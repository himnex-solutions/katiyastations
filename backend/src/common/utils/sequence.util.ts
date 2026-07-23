import { Prisma } from '@prisma/client';
import { randomUUID } from 'crypto';

/**
 * Generates a human-readable, collision-resistant sequence number
 * (e.g. KOT-20260702-4F82) for KOTs, bills, sessions, purchases, etc.
 * Not a strictly incrementing counter — avoids row-locking contention
 * under concurrent writes, which matters more for a busy POS than a
 * gapless sequence.
 */
export function generateSequenceNumber(prefix: string): string {
  const date = new Date().toISOString().slice(0, 10).replace(/-/g, '');
  const suffix = Math.random().toString(16).slice(2, 6).toUpperCase();
  return `${prefix}-${date}-${suffix}`;
}

/**
 * Atomically allocates the next SEQUENTIAL, GUARANTEED-UNIQUE number for
 * [scope] within a branch and day — e.g. "INV-20260723-0001", "INV-20260723-0002".
 *
 * Unlike generateSequenceNumber (random suffix, which can collide and has no
 * uniqueness guarantee), this increments a per-(branch, scope, day) Counter row
 * inside the caller's transaction. The row lock serialises concurrent settles,
 * so two cashiers pressing "Settle Bill" at the same moment get consecutive
 * numbers instead of a duplicate. Use this for bills and tax invoices.
 */
export async function nextSequenceNumber(
  tx: Prisma.TransactionClient,
  branchId: string,
  scope: string,
): Promise<string> {
  const period = new Date().toISOString().slice(0, 10).replace(/-/g, '');

  // Single-statement atomic upsert-and-increment: INSERT the day's first
  // number, or bump the existing counter, returning the new value. Postgres
  // takes a row lock on the conflicting key, so concurrent settles serialise
  // and can never read the same value twice.
  const rows = await tx.$queryRaw<Array<{ value: number }>>`
    INSERT INTO "counters" ("id", "branch_id", "scope", "period", "value", "updated_at")
    VALUES (${randomUUID()}, ${branchId}, ${scope}, ${period}, 1, now())
    ON CONFLICT ("branch_id", "scope", "period")
    DO UPDATE SET "value" = "counters"."value" + 1, "updated_at" = now()
    RETURNING "value"
  `;

  const value = Number(rows[0]?.value ?? 1);
  return `${scope}-${period}-${String(value).padStart(4, '0')}`;
}
