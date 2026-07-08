/*
  Warnings:

  - You are about to drop the column `amount` on the `credit_records` table. All the data in the column will be lost.
  - Added the required column `credit_amount` to the `credit_records` table without a default value. This is not possible if the table is not empty.

*/
-- AlterTable
ALTER TABLE "credit_records" DROP COLUMN "amount",
ADD COLUMN     "credit_amount" DECIMAL(65,30) NOT NULL;
