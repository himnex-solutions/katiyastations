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
