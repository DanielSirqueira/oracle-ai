-- ============================================================
-- Mutation layer: rule priority + lifecycle (retire / forget).
-- Additive over the v1.0.0 baseline. The migration ledger guarantees
-- one-time application; IF NOT EXISTS is defense-in-depth.
-- ============================================================

-- Rule priority. Ranks rules WITHIN the same severity in `rulesForTask` and as
-- a tiebreaker in search. 0..100, default 50 (neutral). This is a SEPARATE axis
-- from `severity` (required vs recommended = hard vs soft): priority is about
-- ordering/relevance, severity is about obligation. Agents can re-rank a rule
-- in place without superseding it (see set_rule_priority).
ALTER TABLE rules ADD COLUMN IF NOT EXISTS priority integer NOT NULL DEFAULT 50;

-- Lifecycle / soft-delete (retire). A retired row has is_latest=false AND
-- retired_at IS NOT NULL — which distinguishes it from a row that is merely
-- superseded by a newer version (is_latest=false, retired_at IS NULL). Recall
-- already filters on is_latest, so retiring drops a row out of every recall
-- path while keeping it for audit. `retired_reason` records WHY (corporate,
-- auditable memory). Hard delete (purge) removes the row entirely instead.
ALTER TABLE rules         ADD COLUMN IF NOT EXISTS retired_at     timestamptz;
ALTER TABLE rules         ADD COLUMN IF NOT EXISTS retired_reason text;
ALTER TABLE architectures ADD COLUMN IF NOT EXISTS retired_at     timestamptz;
ALTER TABLE architectures ADD COLUMN IF NOT EXISTS retired_reason text;
ALTER TABLE memories      ADD COLUMN IF NOT EXISTS retired_at     timestamptz;
ALTER TABLE memories      ADD COLUMN IF NOT EXISTS retired_reason text;
