-- Guarantees bill/invoice numbers are unique, and switches their allocation to
-- an atomic sequential counter (see common/utils/sequence.util.ts:nextSequenceNumber).
--
-- Safe on existing data: any pre-existing duplicate numbers are de-duplicated
-- first, so adding the unique indexes can never fail on live rows.

-- 1. Sequence counters table (one row per branch + scope + day).
CREATE TABLE "counters" (
  "id"         TEXT NOT NULL,
  "branch_id"  TEXT NOT NULL,
  "scope"      TEXT NOT NULL,
  "period"     TEXT NOT NULL,
  "value"      INTEGER NOT NULL DEFAULT 0,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "counters_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "counters_branch_id_scope_period_key"
  ON "counters"("branch_id", "scope", "period");

-- 2. De-duplicate any historical collisions before enforcing uniqueness. The
--    oldest row keeps its number; newer duplicates get a "-Dn" suffix so no
--    real data is lost and the unique index below always applies cleanly.
UPDATE "bills" AS b
SET "bill_number" = b."bill_number" || '-D' || d.rn
FROM (
  SELECT "id",
         ROW_NUMBER() OVER (
           PARTITION BY "branch_id", "bill_number"
           ORDER BY "created_at", "id"
         ) AS rn
  FROM "bills"
) AS d
WHERE b."id" = d."id" AND d.rn > 1;

UPDATE "bills" AS b
SET "invoice_number" = b."invoice_number" || '-D' || d.rn
FROM (
  SELECT "id",
         ROW_NUMBER() OVER (
           PARTITION BY "branch_id", "invoice_number"
           ORDER BY "created_at", "id"
         ) AS rn
  FROM "bills"
  WHERE "invoice_number" IS NOT NULL
) AS d
WHERE b."id" = d."id" AND d.rn > 1;

-- 3. Enforce uniqueness per branch. NULL invoice numbers stay allowed
--    (Postgres treats NULLs as distinct in a unique index).
CREATE UNIQUE INDEX "bills_branch_id_bill_number_key"
  ON "bills"("branch_id", "bill_number");

CREATE UNIQUE INDEX "bills_branch_id_invoice_number_key"
  ON "bills"("branch_id", "invoice_number");
