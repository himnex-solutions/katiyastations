-- Closing a session used to park its table in 'cleaning', and nothing in the
-- app could ever move it out again — the table became permanently unbookable.
-- SessionsService.close now releases straight to 'available' (as paying a bill
-- and merging a table already did); this frees the ones already stranded.
--
-- Safe by construction: close() also nulls current_session_id, so a table in
-- 'cleaning' has no live session to clobber.
UPDATE "restaurant_tables"
SET "status" = 'available'
WHERE "status" = 'cleaning'
  AND "current_session_id" IS NULL;
