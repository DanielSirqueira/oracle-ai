-- =====================================================================
-- v2.2.0 — Loop Engineering (2/4): a DEFINIÇÃO do processo (o "workflow do n8n").
--   flows       — o processo versionado (padrão key + is_latest/supersedes, como
--                 rules/skills). orchestrator_agent é o agente que decide nos nós
--                 de julgamento; entry_step_key é o nó inicial do grafo.
--   flow_steps  — os nós; cada nó é um LOOP. kind seleciona o executor (agent,
--                 orchestrator, rfc_review, command, human_gate). exit_criteria são
--                 os verificadores que o RUNNER roda (fora do agente); output_schema
--                 é o contrato de saída (D7); permissions o menor privilégio (D8).
--   flow_edges  — as arestas (o "ligar os loops"); a condição roteia sobre o
--                 resultado dos verificadores ou o veredito do orquestrador.
-- Ver [[loop-engineering-plan]] §5.2–5.4.
-- =====================================================================

CREATE TABLE IF NOT EXISTS flows (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id     uuid REFERENCES organizations(id) ON DELETE CASCADE,
    project_id          uuid REFERENCES projects(id)      ON DELETE CASCADE,
    module_id           uuid REFERENCES modules(id)       ON DELETE CASCADE,
    key                 text NOT NULL,                    -- identidade estável (versiona por key)
    name                text NOT NULL,
    description         text NOT NULL DEFAULT '',
    orchestrator_agent  text NOT NULL DEFAULT 'claude-code',  -- o agente-orquestrador do processo
    entry_step_key      text NOT NULL DEFAULT '',          -- nó inicial do grafo
    budgets             jsonb NOT NULL DEFAULT '{}',       -- defaults: maxTotalTokens, maxWallMinutes…
    version_no          integer NOT NULL DEFAULT 1,
    is_latest           boolean NOT NULL DEFAULT true,
    supersedes          uuid REFERENCES flows(id) ON DELETE SET NULL,
    retired_at          timestamptz,
    retired_reason      text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT flows_owner_check
        CHECK (organization_id IS NOT NULL OR project_id IS NOT NULL OR module_id IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_flows_organization ON flows (organization_id);
CREATE INDEX IF NOT EXISTS idx_flows_project      ON flows (project_id);
CREATE INDEX IF NOT EXISTS idx_flows_module       ON flows (module_id);
-- Um "latest" por key por escopo (padrão uq_rules_*_latest).
CREATE UNIQUE INDEX IF NOT EXISTS uq_flows_org_latest
    ON flows (organization_id, key) WHERE is_latest AND organization_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_flows_project_latest
    ON flows (project_id, key) WHERE is_latest AND project_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_flows_module_latest
    ON flows (module_id, key) WHERE is_latest AND module_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS flow_steps (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    flow_id          uuid NOT NULL REFERENCES flows(id) ON DELETE CASCADE,
    step_key         text NOT NULL,                       -- identidade dentro do flow
    name             text NOT NULL DEFAULT '',
    kind             text NOT NULL DEFAULT 'agent'
                     CHECK (kind IN ('agent','orchestrator','rfc_review','command','human_gate')),
    agent            text,                                -- claude-code|codex|cursor|gemini|… (kind=agent)
    model            text,                                -- override opcional do modelo do harness
    role             text,                                -- persona: architect|implementer|security|docs|…
    prompt_template  text NOT NULL DEFAULT '',            -- placeholders {task} {context} {feedback}…
    command          text,                                -- kind=command
    output_schema    jsonb,                               -- JSON Schema do output da etapa (D7)
    permissions      jsonb NOT NULL DEFAULT '{}',         -- perfil de menor privilégio (D8)
    exit_criteria    jsonb NOT NULL DEFAULT '{}',         -- verificadores: {commands, reportChecks, rfc}
    max_iterations   integer NOT NULL DEFAULT 3,          -- o inner loop
    token_budget     bigint,
    timeout_minutes  integer NOT NULL DEFAULT 30,
    on_fail          text NOT NULL DEFAULT 'park'
                     CHECK (on_fail IN ('park','halt','continue')),
    config           jsonb NOT NULL DEFAULT '{}',         -- extras por kind (ex.: revisores do rfc_review)
    position         integer NOT NULL DEFAULT 0,          -- ordenação p/ exibição
    created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_flow_steps_key ON flow_steps (flow_id, step_key);
CREATE INDEX IF NOT EXISTS idx_flow_steps_flow ON flow_steps (flow_id, position);

CREATE TABLE IF NOT EXISTS flow_edges (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    flow_id        uuid NOT NULL REFERENCES flows(id)      ON DELETE CASCADE,
    from_step      uuid NOT NULL REFERENCES flow_steps(id) ON DELETE CASCADE,
    to_step        uuid NOT NULL REFERENCES flow_steps(id) ON DELETE CASCADE,
    condition      text NOT NULL DEFAULT 'success'
                   CHECK (condition IN ('success','failure','verdict','always')),
    verdict_value  text,                                  -- ex.: 'aprovado' | 'rejeitado' (condition=verdict)
    created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_flow_edges_flow ON flow_edges (flow_id);
CREATE INDEX IF NOT EXISTS idx_flow_edges_from ON flow_edges (from_step);
CREATE INDEX IF NOT EXISTS idx_flow_edges_to   ON flow_edges (to_step);
