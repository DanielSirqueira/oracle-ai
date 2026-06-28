-- ============================================================
-- Measurement harness: per-session token & compaction metrics.
-- ============================================================
-- One row per (project, agent session, experiment label). Updated incrementally
-- from the hooks: each Stop adds that turn's token usage (parsed from the
-- transcript) + 1 turn; each PostToolUse adds 1 tool use; each PostCompact adds
-- 1 compaction. Because deltas are ADDED as events arrive, a later compaction
-- truncating the transcript never loses already-recorded turns. The `label`
-- (from ORACLE_METRICS_LABEL) lets you A/B compare runs (e.g. oracle vs baseline).
CREATE TABLE session_metrics (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id            uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    external_id           text NOT NULL,                     -- the agent's session id
    label                 text NOT NULL DEFAULT 'default',   -- experiment / mode tag
    input_tokens          bigint  NOT NULL DEFAULT 0,        -- fresh (uncached) input
    output_tokens         bigint  NOT NULL DEFAULT 0,
    cache_creation_tokens bigint  NOT NULL DEFAULT 0,        -- cache writes (full price)
    cache_read_tokens     bigint  NOT NULL DEFAULT 0,        -- cached reads (~10x cheaper)
    compactions           integer NOT NULL DEFAULT 0,
    tool_uses             integer NOT NULL DEFAULT 0,
    turns                 integer NOT NULL DEFAULT 0,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    UNIQUE (project_id, external_id, label)
);

CREATE INDEX idx_session_metrics_label   ON session_metrics (label);
CREATE INDEX idx_session_metrics_project ON session_metrics (project_id);
