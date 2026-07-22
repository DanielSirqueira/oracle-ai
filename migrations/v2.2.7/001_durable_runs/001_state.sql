-- v2.2.7 — Durable execution frontier and fenced worker leases.
--
-- execution_state persists the scheduler queue/active step so gates, pauses and
-- worker crashes resume every pending branch instead of reconstructing only the
-- current step. lease_epoch is incremented on every claim and fences a stale
-- worker after another worker takes ownership.

ALTER TABLE flow_runs
    ADD COLUMN IF NOT EXISTS execution_state jsonb NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS lease_epoch bigint NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS parent_run_id uuid REFERENCES flow_runs(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_flow_runs_parent ON flow_runs(parent_run_id);

-- A killed/reclaimed attempt is explicitly abandoned instead of remaining
-- visually "running" forever.
ALTER TABLE flow_run_steps DROP CONSTRAINT IF EXISTS flow_run_steps_status_check;
ALTER TABLE flow_run_steps ADD CONSTRAINT flow_run_steps_status_check
    CHECK (status IN ('running','verifying','passed','failed','skipped','parked','abandoned'));

ALTER TABLE flow_run_events DROP CONSTRAINT IF EXISTS flow_run_events_kind_check;
ALTER TABLE flow_run_events ADD CONSTRAINT flow_run_events_kind_check
    CHECK (kind IN ('state','step_start','step_end','verifier','iteration',
                    'decision','gate','budget','error','info','route_error',
                    'preflight_failed','join_waiting'));
