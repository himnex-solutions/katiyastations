import { Decimal } from '@prisma/client/runtime/library';

function camelToSnake(key: string): string {
  return key.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`);
}

/**
 * Recursively converts object keys from camelCase (Prisma/TS convention)
 * to snake_case (the wire format the Flutter client was built against,
 * inherited from Postgres column names via the old PostgREST API).
 * Dates and Prisma Decimals are treated as leaf values.
 */
export function toSnakeCase<T = unknown>(value: unknown): T {
  if (value instanceof Decimal) {
    return value.toNumber() as unknown as T;
  }
  if (value instanceof Date) {
    return value.toISOString() as unknown as T;
  }
  if (Array.isArray(value)) {
    return value.map((item) => toSnakeCase(item)) as unknown as T;
  }
  if (value !== null && typeof value === 'object') {
    const result: Record<string, unknown> = {};
    for (const [key, val] of Object.entries(value)) {
      result[camelToSnake(key)] = toSnakeCase(val);
    }
    return result as unknown as T;
  }
  return value as T;
}
