-- =====================================================================
-- v2.1.0 — RFC (3/5): rfc_comments (achado técnico estruturado).
-- O coração da funcionalidade. Um comentário NÃO é chat: é um achado tipado,
-- com severidade, ancorado numa seção (âncora forte via section_id), e
-- vetorizado para dedup/novidade (reusa a mesma mecânica de nearestByEmbedding).
-- `verified` marca se há ao menos uma evidência resolvível (ver 004); achado
-- crítico não-verificado é rebaixado e NÃO trava a conclusão.
-- =====================================================================

CREATE TABLE IF NOT EXISTS rfc_comments (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rfc_id             uuid NOT NULL REFERENCES rfcs(id) ON DELETE CASCADE,
    version_id         uuid NOT NULL REFERENCES rfc_versions(id) ON DELETE CASCADE,
    section_id         uuid REFERENCES rfc_sections(id) ON DELETE SET NULL,
    author_agent       text NOT NULL DEFAULT 'claude-code',
    reviewer_role      text,                              -- architect|dba|security|backend|frontend|ux|infra|qa|domain|critic|consolidator
    type               text NOT NULL DEFAULT 'improvement'
                       CHECK (type IN ('gap','inconsistency','risk','bug',
                              'question','improvement','blocker','nit')),
    severity           text NOT NULL DEFAULT 'info'
                       CHECK (severity IN ('critical','major','minor','info')),
    area               text,                              -- data|api|ui|sec|infra|domain|...
    anchor_quote       text,                              -- trecho citado da seção
    problem            text NOT NULL DEFAULT '',
    rationale          text NOT NULL DEFAULT '',
    impact             text NOT NULL DEFAULT '',
    proposed_solution  text NOT NULL DEFAULT '',          -- obrigatório na app p/ gap|inconsistency|bug|blocker
    alternatives       jsonb NOT NULL DEFAULT '[]',       -- [{option, tradeoff}]
    confidence         real NOT NULL DEFAULT 0.5,         -- 0..1 auto-declarado, calibrado a posteriori
    status             text NOT NULL DEFAULT 'open'
                       CHECK (status IN ('open','accepted','rejected','deferred',
                              'duplicate','superseded','resolved')),
    parent_comment_id  uuid REFERENCES rfc_comments(id) ON DELETE SET NULL,
    verified           boolean NOT NULL DEFAULT false,    -- tem evidência resolvida?
    round_no           integer NOT NULL DEFAULT 0,
    embedding          vector(1024),
    embedding_model    text,
    fts                tsvector GENERATED ALWAYS AS
                       (to_tsvector('english',
                          coalesce(problem, '') || ' ' ||
                          coalesce(rationale, '') || ' ' ||
                          coalesce(proposed_solution, ''))) STORED,
    is_latest          boolean NOT NULL DEFAULT true,
    supersedes         uuid REFERENCES rfc_comments(id) ON DELETE SET NULL,
    created_at         timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rfc_comments_rfc      ON rfc_comments (rfc_id, status);
CREATE INDEX IF NOT EXISTS idx_rfc_comments_version  ON rfc_comments (version_id);
CREATE INDEX IF NOT EXISTS idx_rfc_comments_section  ON rfc_comments (section_id);
CREATE INDEX IF NOT EXISTS idx_rfc_comments_severity ON rfc_comments (rfc_id, severity, status);
CREATE INDEX IF NOT EXISTS idx_rfc_comments_fts ON rfc_comments USING gin (fts);
CREATE INDEX IF NOT EXISTS idx_rfc_comments_embedding ON rfc_comments
    USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);
