-- =====================================================================
-- v2.2.0 — Loop Engineering (4/4): o BLACKBOARD, os artefatos e a timeline.
--   flow_run_context  — chave->valor (jsonb) do run; o quadro-negro que as etapas
--                       leem e escrevem (plan, rfc_id, findings_summary…). O
--                       próximo agente depende do que foi ESTRUTURADAMENTE gravado,
--                       nunca do transcript do anterior (anti context-rot).
--   flow_artifacts    — o que o run produziu (branch, commit, PR, RFC, doc, memory),
--                       por referência (locator), como rfc_comment_evidence.
--   flow_run_events   — timeline append-only (auditoria + Studio); toda transição
--                       de estado, verificador, decisão, gate e orçamento.
-- Ver [[loop-engineering-plan]] §5.7–5.9.
-- =====================================================================

CREATE TABLE IF NOT EXISTS flow_run_context (
    run_id      uuid NOT NULL REFERENCES flow_runs(id) ON DELETE CASCADE,
    key         text NOT NULL,                            -- 'plan' | 'rfc_id' | 'findings_summary' | …
    value       jsonb NOT NULL DEFAULT '{}'::jsonb,
    updated_by  uuid REFERENCES flow_run_steps(id) ON DELETE SET NULL,
    updated_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (run_id, key)
);

CREATE INDEX IF NOT EXISTS idx_flow_run_context_run ON flow_run_context (run_id);

CREATE TABLE IF NOT EXISTS flow_artifacts (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id       uuid NOT NULL REFERENCES flow_runs(id) ON DELETE CASCADE,
    run_step_id  uuid REFERENCES flow_run_steps(id) ON DELETE SET NULL,
    kind         text NOT NULL
                 CHECK (kind IN ('branch','commit','pr','rfc','doc','file','memory','other')),
    locator      text NOT NULL,                           -- URL, path, id — como rfc_comment_evidence
    meta         jsonb NOT NULL DEFAULT '{}',
    created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_flow_artifacts_run  ON flow_artifacts (run_id, created_at);
CREATE INDEX IF NOT EXISTS idx_flow_artifacts_step ON flow_artifacts (run_step_id);

CREATE TABLE IF NOT EXISTS flow_run_events (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id       uuid NOT NULL REFERENCES flow_runs(id) ON DELETE CASCADE,
    run_step_id  uuid REFERENCES flow_run_steps(id) ON DELETE SET NULL,
    kind         text NOT NULL
                 CHECK (kind IN ('state','step_start','step_end','verifier','iteration',
                                 'decision','gate','budget','error','info')),
    payload      jsonb NOT NULL DEFAULT '{}',
    created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_flow_run_events_run ON flow_run_events (run_id, created_at);
