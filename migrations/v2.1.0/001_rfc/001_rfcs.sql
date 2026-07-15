-- =====================================================================
-- v2.1.0 — RFC (1/5): rfcs (cabeçalho da solicitação de comentários).
-- Uma RFC é uma spec técnica publicada para revisão multiagente. Ancora em
-- exatamente um nível de escopo (organization / project / module), igual a
-- rules/memories, e aponta para a versão corrente do documento. O ciclo de
-- vida vive em `status`; a linhagem de substituição (uma RFC que troca outra)
-- em `supersedes`. Ver [[rfc-feature]] / oracle-v2-plan.
-- =====================================================================

CREATE TABLE IF NOT EXISTS rfcs (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id    uuid REFERENCES organizations(id) ON DELETE CASCADE,
    project_id         uuid REFERENCES projects(id)      ON DELETE CASCADE,
    module_id          uuid REFERENCES modules(id)       ON DELETE CASCADE,
    title              text NOT NULL,
    rfc_type           text NOT NULL DEFAULT 'generic',    -- perfil de checklist: backend|frontend|fullstack|data|infra|generic
    status             text NOT NULL DEFAULT 'draft'
                       CHECK (status IN ('draft','open_for_comments','in_review',
                              'in_consolidation','awaiting_human','stalled',
                              'approved','rejected','superseded','obsolete')),
    current_version_id uuid,                               -- FK -> rfc_versions (adicionada em 002, evita ciclo)
    author_agent       text NOT NULL DEFAULT 'claude-code',
    round_count        integer NOT NULL DEFAULT 0,
    supersedes         uuid REFERENCES rfcs(id) ON DELETE SET NULL,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT rfcs_owner_check
        CHECK (organization_id IS NOT NULL OR project_id IS NOT NULL OR module_id IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_rfcs_organization ON rfcs (organization_id);
CREATE INDEX IF NOT EXISTS idx_rfcs_project      ON rfcs (project_id);
CREATE INDEX IF NOT EXISTS idx_rfcs_module       ON rfcs (module_id);
CREATE INDEX IF NOT EXISTS idx_rfcs_status       ON rfcs (status, updated_at);
