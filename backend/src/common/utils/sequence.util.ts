import { Prisma } from '@prisma/client';
import { randomUUID } from 'crypto';
import NepaliDate from 'nepali-date-converter';

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
 * The Nepali (Bikram Sambat) fiscal year for [date], e.g. "2083/84".
 *
 * Nepal's fiscal year runs Shrawan 1 → Ashadh end (roughly mid-July to
 * mid-July). Shrawan is Nepali month index 3 (Baishakh=0). A date in Shrawan or
 * later belongs to the fiscal year that starts that Bikram Sambat year; a date
 * before Shrawan (Baishakh/Jestha/Ashadh) still belongs to the year that
 * started the previous Shrawan.
 */
export function nepaliFiscalYear(date: Date = new Date()): string {
  const bs = new NepaliDate(date);
  const bsYear = bs.getYear();
  const bsMonth = bs.getMonth(); // 0-indexed: Baishakh=0 … Shrawan=3 … Chaitra=11
  const startYear = bsMonth >= 3 ? bsYear : bsYear - 1;
  return `${startYear}/${String((startYear + 1) % 100).padStart(2, '0')}`;
}

/**
 * Atomically allocates the next SEQUENTIAL, GUARANTEED-UNIQUE number for
 * [scope] within a branch and Nepali FISCAL YEAR — e.g. "INV-2083/84-000001",
 * "INV-2083/84-000002". One continuous, gap-free series that resets only at the
 * new fiscal year (Shrawan 1), matching what Nepal's IRD expects of a
 * tax-invoice sequence.
 *
 * Increments a per-(branch, scope, fiscal-year) Counter row inside the caller's
 * transaction. The row lock serialises concurrent settles, so two cashiers
 * pressing "Settle Bill" at the same moment get consecutive numbers instead of
 * a duplicate. If the settle transaction rolls back, the increment rolls back
 * with it — so a failed settle leaves no gap. Use this for bills and invoices.
 */
export async function nextSequenceNumber(
  tx: Prisma.TransactionClient,
  branchId: string,
  scope: string,
): Promise<string> {
  const period = nepaliFiscalYear(); // e.g. "2083/84" — resets only at the new fiscal year

  // Single-statement atomic upsert-and-increment: INSERT the year's first
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
  return `${scope}-${period}-${String(value).padStart(6, '0')}`;
}
