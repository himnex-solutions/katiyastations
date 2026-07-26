-- Online / call-in orders: a table session that has no table, carrying the
-- caller's contact details. Reuses the whole session → KOT → bill → payment
-- flow, so online sales land in the same reports. All additive / defaulted, so
-- existing dine-in sessions stay valid.
ALTER TABLE "table_sessions"
  ADD COLUMN "type"             TEXT DEFAULT 'dine_in' NOT NULL,
  ADD COLUMN "customer_name"    TEXT,
  ADD COLUMN "customer_phone"   TEXT,
  ADD COLUMN "customer_address" TEXT,
  ALTER COLUMN "table_id" DROP NOT NULL;
