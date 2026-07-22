-- =====================================================================
-- v2.2.0 — Loop Engineering (3/4): a EXECUÇÃO (a instância em andamento).
--   flow_runs       — uma execução de um flow para uma task. Pina a versão do flow
--                     (ON DELETE RESTRICT). O worker reivindica com claimed_by +
--                     heartbeat_at (lease); todo o estado vive aqui, então um run
--                     órfão (heartbeat vencido) é retomável do último evento.
--   flow_run_steps  — cada ITERAÇÃO de cada etapa (o inner loop). A costura-chave:
--                     session_id -> sessions liga a sessão CAPTURADA pelos hooks à
--                     etapa que a gerou (auditoria/replay sem captura nova).
--                     claim_token é a identidade da etapa nas tools (D8).
-- Ver [[loop-engineering-plan]] §5.5–5.6.
-- =====================================================================

CREATE TABLE IF NOT EXISTS flow_runs (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    flow_id          uuid NOT NULL REFERENCES flows(id) ON DELETE RESTRICT,   -- versão pinada
    task_id          uuid REFERENCES tasks(id) ON DELETE SET NULL,
    project_id       uuid REFERENCES projects(id) ON DELETE CASCADE,          -- escopo de execução
    status           text NOT NULL DEFAULT 'queued'
                     CHECK (status IN ('queued','running','awaiting_human','paused',
                                       'stalled','completed','failed','cancelled')),
    current_step_id  uuid REFERENCES flow_steps(id) ON DELETE SET NULL,
    branch_name      text,
    worktree_path    text,
    budgets          jsonb NOT NULL DEFAULT '{}',         -- efetivos (flow defaults + overrides)
    tokens_used      bigint NOT NULL DEFAULT 0,           -- somado das sessions das etapas
    started_by       text NOT NULL DEFAULT 'human',
    claimed_by       text,                                -- id do worker (lease)
    heartbeat_at     timestamptz,                         -- worker vivo? (retomada de run órfão)
    error            text,
    created_at       timestamptz NOT NULL DEFAULT now(),
    started_at       timestamptz,
    ended_at         timestamptz
);

CREATE INDEX IF NOT EXISTS idx_flow_runs_claim   ON flow_runs (status, created_at);
CREATE INDEX IF NOT EXISTS idx_flow_runs_flow    ON flow_runs (flow_id);
CREATE INDEX IF NOT EXISTS idx_flow_runs_task    ON flow_runs (task_id);
CREATE INDEX IF NOT EXISTS idx_flow_runs_project ON flow_runs (project_id, created_at);

CREATE TABLE IF NOT EXISTS flow_run_steps (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id          uuid NOT NULL REFERENCES flow_runs(id)  ON DELETE CASCADE,
    step_id         uuid NOT NULL REFERENCES flow_steps(id) ON DELETE CASCADE,
    iteration       integer NOT NULL DEFAULT 1,           -- 1..max_iterations (o inner loop)
    status          text NOT NULL DEFAULT 'running'
                    CHECK (status IN ('running','verifying','passed','failed','skipped','parked')),
    agent           text,
    session_id      uuid REFERENCES sessions(id) ON DELETE SET NULL,  -- <- a sessão CAPTURADA da etapa
    claim_token     text,                                 -- identidade da etapa nas tools (D8)
    rendered_prompt text,                                 -- o prompt final enviado (auditoria)
    report          jsonb,                                -- o step report estruturado do agente
    verifier        jsonb,                                -- resultados dos verificadores
    tokens_used     bigint NOT NULL DEFAULT 0,
    started_at      timestamptz NOT NULL DEFAULT now(),
    ended_at        timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_flow_run_steps ON flow_run_steps (run_id, step_id, iteration);
CREATE INDEX IF NOT EXISTS idx_flow_run_steps_run     ON flow_run_steps (run_id, started_at);
CREATE INDEX IF NOT EXISTS idx_flow_run_steps_session ON flow_run_steps (session_id);
