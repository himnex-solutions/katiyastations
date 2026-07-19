-- Three additive feature migrations, all nullable / defaulted so existing rows
-- stay valid and no backfill is required:
--
--   1. Bill void/refund — reverse a *settled* bill (money + credit + stock),
--      recording who did it and why. paymentStatus gains 'refunded' | 'voided'.
--   2. MenuItem → BarStock link — selling a bar item auto-deducts pegs from a
--      bottle (bar equivalent of a Recipe), via bar_stock_id + pegs_per_serving.
--   3. ShiftClosing reconciliation — opening float, counted vs expected cash and
--      the resulting over/short variance for a real end-of-day Z-report.

-- 1. Bill refund/void fields
ALTER TABLE "bills"
  ADD COLUMN "refund_type"      TEXT,
  ADD COLUMN "refund_reason"    TEXT,
  ADD COLUMN "refunded_by_id"   TEXT,
  ADD COLUMN "refunded_by_name" TEXT,
  ADD COLUMN "refunded_at"      TIMESTAMP(3);

ALTER TABLE "bills"
  ADD CONSTRAINT "bills_refunded_by_id_fkey"
  FOREIGN KEY ("refunded_by_id") REFERENCES "users"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

-- 2. MenuItem → BarStock link
ALTER TABLE "menu_items"
  ADD COLUMN "bar_stock_id"     TEXT,
  ADD COLUMN "pegs_per_serving" DECIMAL(65,30);

ALTER TABLE "menu_items"
  ADD CONSTRAINT "menu_items_bar_stock_id_fkey"
  FOREIGN KEY ("bar_stock_id") REFERENCES "bar_stock"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

-- 3. ShiftClosing reconciliation fields
ALTER TABLE "shift_closings"
  ADD COLUMN "opening_float" DECIMAL(65,30) NOT NULL DEFAULT 0.0,
  ADD COLUMN "counted_cash"  DECIMAL(65,30) NOT NULL DEFAULT 0.0,
  ADD COLUMN "expected_cash" DECIMAL(65,30) NOT NULL DEFAULT 0.0,
  ADD COLUMN "cash_variance" DECIMAL(65,30) NOT NULL DEFAULT 0.0,
  ADD COLUMN "notes"         TEXT;
