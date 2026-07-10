-- Role-targeted, self-expiring notifications.
--
-- `is_read` is gone: reading a notification now deletes it, so an unread row
-- is the only kind of row there is. Any rows still sitting in the table are
-- dropped rather than migrated — they carry no audience and would show up for
-- every role on the next login.

-- AlterTable
ALTER TABLE "notifications" DROP COLUMN "is_read",
ADD COLUMN     "actor_id" TEXT,
ADD COLUMN     "audience" TEXT[] DEFAULT ARRAY[]::TEXT[];

-- CreateIndex
CREATE INDEX "notifications_branch_id_created_at_idx" ON "notifications"("branch_id", "created_at");

-- Clear the backlog written by the old blanket "notify on every write" rule.
DELETE FROM "notifications";
