-- v2.2.6 — Loop Engineering: explicit deterministic fan-in (`join`).
-- The Flow Worker already schedules active branches before a fan-in target;
-- this kind makes that synchronization point visible and auditable.

ALTER TABLE flow_steps DROP CONSTRAINT IF EXISTS flow_steps_kind_check;
ALTER TABLE flow_steps ADD CONSTRAINT flow_steps_kind_check
    CHECK (kind IN ('agent','orchestrator','decision','rfc_create','rfc_review',
                    'rfc_consolidate','rfc_gate','subflow','join','command','human_gate'));
