-- AlterTable
ALTER TABLE "staff_members" ADD COLUMN "user_id" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "staff_members_user_id_key" ON "staff_members"("user_id");
