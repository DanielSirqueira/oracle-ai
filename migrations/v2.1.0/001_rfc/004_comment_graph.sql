-- =====================================================================
-- v2.1.0 — RFC (4/5): evidência, contestação e resolução de comentários.
--   rfc_comment_evidence     — fundamento verificável (o antídoto da alucinação):
--                              uma referência que o Oracle consegue RESOLVER
--                              (rule/memory/decision/arch/rfc por id, ou arquivo
--                              cujo excerpt bate). `resolved` é preenchido pela
--                              validação da tool, não pelo agente.
--   rfc_comment_relations    — grafo de argumentação tipado (supports/refutes/...).
--                              Refutar exige evidência tão forte quanto afirmar.
--   rfc_comment_resolutions  — desfecho + motivo (auditoria); pode citar a regra
--                              que invalidou o achado.
-- ref_id em evidence é POLIMÓRFICO (rule|memory|architecture|rfc) — sem FK rígida.
-- =====================================================================

CREATE TABLE IF NOT EXISTS rfc_comment_evidence (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    comment_id   uuid NOT NULL REFERENCES rfc_comments(id) ON DELETE CASCADE,
    kind         text NOT NULL
                 CHECK (kind IN ('rule','memory','decision','architecture','code',
                        'api_contract','test','log','data_model','diagram',
                        'business_req','prior_rfc')),
    ref_kind     text NOT NULL DEFAULT 'oracle_entity'
                 CHECK (ref_kind IN ('oracle_entity','file','external')),
    ref_id       uuid,                                    -- id polimórfico quando ref_kind = oracle_entity
    locator      text,                                    -- 'path:linhas' ou URI quando file/external
    excerpt      text,                                    -- trecho literal citado
    resolved     boolean NOT NULL DEFAULT false,          -- validado pela tool (existe / bate)
    resolved_at  timestamptz,
    created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rfc_evidence_comment  ON rfc_comment_evidence (comment_id);
CREATE INDEX IF NOT EXISTS idx_rfc_evidence_resolved ON rfc_comment_evidence (comment_id, resolved);

CREATE TABLE IF NOT EXISTS rfc_comment_relations (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    from_comment  uuid NOT NULL REFERENCES rfc_comments(id) ON DELETE CASCADE,
    to_comment    uuid NOT NULL REFERENCES rfc_comments(id) ON DELETE CASCADE,
    relation      text NOT NULL
                  CHECK (relation IN ('supports','refutes','duplicates',
                         'supersedes','refines','depends_on')),
    ground        text
                  CHECK (ground IS NULL OR ground IN ('architectural_conflict',
                         'business_rule','missing_evidence','out_of_scope',
                         'factual_error','redundant')),
    reason        text NOT NULL DEFAULT '',
    evidence      jsonb NOT NULL DEFAULT '[]',            -- refutar TAMBÉM exige evidência
    created_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT rfc_relations_no_self CHECK (from_comment <> to_comment)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_rfc_relations
    ON rfc_comment_relations (from_comment, to_comment, relation);
CREATE INDEX IF NOT EXISTS idx_rfc_relations_from ON rfc_comment_relations (from_comment);
CREATE INDEX IF NOT EXISTS idx_rfc_relations_to   ON rfc_comment_relations (to_comment);

CREATE TABLE IF NOT EXISTS rfc_comment_resolutions (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    comment_id      uuid NOT NULL REFERENCES rfc_comments(id) ON DELETE CASCADE,
    resolver_agent  text NOT NULL DEFAULT 'claude-code',
    decision        text NOT NULL
                    CHECK (decision IN ('accepted','rejected','deferred','duplicate')),
    ground          text,
    reason          text NOT NULL DEFAULT '',
    rule_id         uuid REFERENCES rules(id) ON DELETE SET NULL,  -- regra required que invalidou (opcional)
    decided_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rfc_resolutions_comment ON rfc_comment_resolutions (comment_id);
