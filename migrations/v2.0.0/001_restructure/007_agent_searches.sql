-- =====================================================================
-- v2.0.0 — Restructure (7/8): agent search history.
-- Every recall an agent makes is logged: the tool, the query, the scope it was
-- run under, the filters, and what came back (ids + scores). Lets us audit
-- whether retrieval is actually delivering what the agent asked for.
-- =====================================================================

CREATE TABLE IF NOT EXISTS agent_searches (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id  uuid REFERENCES sessions(id) ON DELETE CASCADE,
    request_id  uuid REFERENCES requests(id) ON DELETE CASCADE,
    tool        text NOT NULL,                       -- memory | rule | skill | architecture
    query       text NOT NULL,
    scope       jsonb NOT NULL DEFAULT '{}',         -- {organizationId, projectId, moduleId}
    filters     jsonb NOT NULL DEFAULT '{}',
    results     jsonb NOT NULL DEFAULT '[]',         -- [{id, score}, ...]
    hits        integer NOT NULL DEFAULT 0,
    latency_ms  integer,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_agent_searches_session ON agent_searches (session_id, created_at);
CREATE INDEX IF NOT EXISTS idx_agent_searches_request ON agent_searches (request_id);
CREATE INDEX IF NOT EXISTS idx_agent_searches_tool    ON agent_searches (tool, created_at);
