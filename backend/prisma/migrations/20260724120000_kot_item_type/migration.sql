-- Adds the station type (food | drink | bar) to each KOT item so a sent order
-- can be split across printers — food to the kitchen printer, bar/drink to the
-- cashier's bar printer. Defaulted to 'food', so existing rows stay valid and
-- no backfill is needed.
--
-- Without this column, KOT creation was failing (the app writes `type` on every
-- item, and the column didn't exist).
ALTER TABLE "kot_items" ADD COLUMN "type" TEXT NOT NULL DEFAULT 'food';
