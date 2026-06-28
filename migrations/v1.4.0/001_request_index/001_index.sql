-- ============================================================
-- Performance: back the hot capture path with a composite index.
-- Additive, forward-only (no down migration). Safe to re-run: the DROP is
-- guarded and the CREATE is the single source of truth for the final shape.
-- ============================================================
-- `latestRequest` (ORDER BY created_at DESC LIMIT 1) runs on EVERY Stop /
-- PostToolUse to find the request a message belongs to; `sessionRequests` lists
-- a session's demands newest-first. A plain (session_id) index forced a sort on
-- created_at for both. (session_id, created_at DESC) resolves them straight from
-- the index — O(1) for latestRequest, no sort for the listing.
DROP INDEX IF EXISTS idx_requests_session;
CREATE INDEX idx_requests_session ON requests (session_id, created_at DESC);
