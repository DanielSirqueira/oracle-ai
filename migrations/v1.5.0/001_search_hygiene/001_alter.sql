-- =====================================================================
-- Search hygiene: per-model embedding tagging on requests + a stored
-- full-text index for architectures.
-- Additive over the v1.0.0 baseline, forward-only. Every statement is
-- guarded (IF NOT EXISTS) so it is safe to re-run and cannot fail on an
-- already-populated database.
-- =====================================================================

-- Requests get an embedding_model, so request search (like memory/rule/
-- architecture search) can compare only same-model vectors — cross-model
-- cosine distances are meaningless once the provider changes.
ALTER TABLE requests ADD COLUMN IF NOT EXISTS embedding_model text;

-- architectures gains a STORED generated `fts` column + GIN index. The hybrid
-- search used to build the tsvector inline per row (a sequential scan + parse
-- on every query); the stored column lets the lexical leg use an index, like
-- rules and memories already do. Same 'english' dictionary as the old inline
-- expression, so ranking is unchanged — only faster.
ALTER TABLE architectures ADD COLUMN IF NOT EXISTS fts tsvector
    GENERATED ALWAYS AS
    (to_tsvector('english', coalesce(area, '') || ' ' || coalesce(content, ''))) STORED;
CREATE INDEX IF NOT EXISTS idx_architectures_fts ON architectures USING gin (fts);
