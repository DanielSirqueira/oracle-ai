-- =====================================================================
-- v2.0.0 — Restructure (8/8): token metrics per session.
-- Rolling aggregate of token usage per session (summed from message
-- token_count as the agent works), so the dashboard can roll tokens up
-- session -> module -> project -> organization.
-- =====================================================================

ALTER TABLE sessions ADD COLUMN IF NOT EXISTS input_tokens  bigint NOT NULL DEFAULT 0;
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS output_tokens bigint NOT NULL DEFAULT 0;
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS total_tokens  bigint NOT NULL DEFAULT 0;
