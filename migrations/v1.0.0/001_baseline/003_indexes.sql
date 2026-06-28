-- Oracle AI — baseline / indexes
-- HNSW for vector recall, GIN for full-text (tsvector) and tags, btree for FKs.
-- Runtime knobs (not here): SET hnsw.ef_search = 100; SET hnsw.iterative_scan = 'relaxed_order';

-- projects
CREATE INDEX idx_projects_product ON projects (product_id);

-- architectures
CREATE UNIQUE INDEX uq_architectures_latest ON architectures (project_id, area) WHERE is_latest;
CREATE INDEX idx_architectures_embedding
    ON architectures USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);

-- rules
CREATE UNIQUE INDEX uq_rules_project_latest
    ON rules (project_id, key) WHERE is_latest AND project_id IS NOT NULL;
CREATE UNIQUE INDEX uq_rules_product_latest
    ON rules (product_id, key) WHERE is_latest AND project_id IS NULL AND product_id IS NOT NULL;
CREATE INDEX idx_rules_project ON rules (project_id);
CREATE INDEX idx_rules_product ON rules (product_id);
CREATE INDEX idx_rules_scope   ON rules (scope);
CREATE INDEX idx_rules_embedding
    ON rules USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);
CREATE INDEX idx_rules_fts  ON rules USING gin (fts);
CREATE INDEX idx_rules_tags ON rules USING gin (tags);

-- sessions
CREATE INDEX idx_sessions_project ON sessions (project_id, created_at);

-- requests
CREATE INDEX idx_requests_session ON requests (session_id);
CREATE INDEX idx_requests_embedding
    ON requests USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);
CREATE INDEX idx_requests_fts ON requests USING gin (fts);

-- messages (belong to a request)
CREATE INDEX idx_messages_request ON messages (request_id, created_at);
CREATE INDEX idx_messages_embedding
    ON messages USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);

-- agent_events
CREATE INDEX idx_agent_events_request ON agent_events (request_id, position);
CREATE INDEX idx_agent_events_kind    ON agent_events (kind);
CREATE INDEX idx_agent_events_embedding
    ON agent_events USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);

-- memories
CREATE INDEX idx_memories_project   ON memories (project_id) WHERE is_latest;
CREATE INDEX idx_memories_product   ON memories (product_id) WHERE is_latest;
CREATE INDEX idx_memories_tier_kind ON memories (tier, kind);
CREATE INDEX idx_memories_embedding
    ON memories USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);
CREATE INDEX idx_memories_fts  ON memories USING gin (fts);
CREATE INDEX idx_memories_tags ON memories USING gin (tags);

-- handoffs
CREATE INDEX idx_handoffs_project_status ON handoffs (project_id, status);
