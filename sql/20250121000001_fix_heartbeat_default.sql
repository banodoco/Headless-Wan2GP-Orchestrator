-- Remove DEFAULT NOW() from last_heartbeat column
-- Workers should have NULL heartbeat until they actually send one.
-- The DEFAULT was causing newly created workers to appear to have heartbeated
-- when they hadn't, leading to premature health check failures.

ALTER TABLE workers ALTER COLUMN last_heartbeat DROP DEFAULT;

-- Also set any workers with heartbeat = created_at to NULL heartbeat
-- (these were set by the old default, not by actual heartbeats)
UPDATE workers 
SET last_heartbeat = NULL 
WHERE last_heartbeat IS NOT NULL 
  AND ABS(EXTRACT(EPOCH FROM (last_heartbeat - created_at))) < 5;
