-- AlterTable
ALTER TABLE "bills" ADD COLUMN     "amount_paid" DECIMAL(65,30) NOT NULL DEFAULT 0.0,
ADD COLUMN     "cashier_name" TEXT,
ADD COLUMN     "change_amount" DECIMAL(65,30) NOT NULL DEFAULT 0.0,
ADD COLUMN     "customer_name" TEXT,
ADD COLUMN     "customer_phone" TEXT,
ADD COLUMN     "invoice_number" TEXT,
ADD COLUMN     "table_id" TEXT;

-- AlterTable
ALTER TABLE "credit_records" ADD COLUMN     "customer_name" TEXT,
ADD COLUMN     "customer_phone" TEXT,
ADD COLUMN     "paid_amount" DECIMAL(65,30) NOT NULL DEFAULT 0.0;

-- AlterTable
ALTER TABLE "kot_items" ADD COLUMN     "unit_price" DECIMAL(65,30) NOT NULL DEFAULT 0.0;

-- AlterTable
ALTER TABLE "kots" ADD COLUMN     "notes" TEXT,
ADD COLUMN     "table_id" TEXT;

-- AlterTable
ALTER TABLE "restaurant_tables" ADD COLUMN     "bill_requested" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "bill_requested_at" TIMESTAMP(3),
ADD COLUMN     "description" TEXT,
ADD COLUMN     "is_enabled" BOOLEAN NOT NULL DEFAULT true;

-- AlterTable
ALTER TABLE "table_sessions" ADD COLUMN     "bill_requested" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "bill_requested_at" TIMESTAMP(3),
ADD COLUMN     "hold_reason" TEXT,
ADD COLUMN     "notes" TEXT,
ADD COLUMN     "on_hold" BOOLEAN NOT NULL DEFAULT false;

-- AddForeignKey
ALTER TABLE "kots" ADD CONSTRAINT "kots_table_id_fkey" FOREIGN KEY ("table_id") REFERENCES "restaurant_tables"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bills" ADD CONSTRAINT "bills_table_id_fkey" FOREIGN KEY ("table_id") REFERENCES "restaurant_tables"("id") ON DELETE SET NULL ON UPDATE CASCADE;
