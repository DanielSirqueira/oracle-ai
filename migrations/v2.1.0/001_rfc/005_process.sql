-- =====================================================================
-- v2.1.0 — RFC (5/5): rodadas, decisões e participantes.
--   rfc_rounds        — cada ciclo de revisão; novelty_score (fração de
--                       comentários não-duplicados, via embedding) alimenta a
--                       terminação multi-critério e a detecção de não-progresso.
--   rfc_decisions     — decisões importantes (inclui as de produto, com
--                       human_approved) + write-back: memory_id liga a decisão à
--                       memory gravada, fechando o ciclo de aprendizado.
--   rfc_participants  — (agent, role, model) por RFC; substrato de CALIBRAÇÃO
--                       (advisory) — nunca gate. Peso vai na evidência, não na
--                       identidade. Ver [[rfc-feature]].
-- =====================================================================

CREATE TABLE IF NOT EXISTS rfc_rounds (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rfc_id         uuid NOT NULL REFERENCES rfcs(id) ON DELETE CASCADE,
    version_id     uuid REFERENCES rfc_versions(id) ON DELETE SET NULL,
    round_no       integer NOT NULL,
    participants   text[] NOT NULL DEFAULT '{}',          -- agentes/roles que revisaram
    new_criticals  integer NOT NULL DEFAULT 0,
    new_majors     integer NOT NULL DEFAULT 0,
    novelty_score  real,                                  -- 0..1; fração não-duplicada da rodada
    started_at     timestamptz NOT NULL DEFAULT now(),
    ended_at       timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_rfc_rounds_no ON rfc_rounds (rfc_id, round_no);
CREATE INDEX IF NOT EXISTS idx_rfc_rounds_rfc ON rfc_rounds (rfc_id);

CREATE TABLE IF NOT EXISTS rfc_decisions (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rfc_id          uuid NOT NULL REFERENCES rfcs(id) ON DELETE CASCADE,
    question        text NOT NULL DEFAULT '',
    chosen_option   text NOT NULL DEFAULT '',
    rationale       text NOT NULL DEFAULT '',
    comment_ids     jsonb NOT NULL DEFAULT '[]',          -- rastreabilidade: achados que a motivaram
    human_approved  boolean NOT NULL DEFAULT false,       -- gate humano p/ decisão de produto
    memory_id       uuid REFERENCES memories(id) ON DELETE SET NULL,  -- write-back -> memories(kind=decision)
    created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rfc_decisions_rfc ON rfc_decisions (rfc_id);

CREATE TABLE IF NOT EXISTS rfc_participants (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rfc_id            uuid NOT NULL REFERENCES rfcs(id) ON DELETE CASCADE,
    agent             text NOT NULL,
    role              text,                               -- architect|critic|consolidator|...
    model             text,                               -- opus|codex|gemini|...
    comments_posted   integer NOT NULL DEFAULT 0,
    accepted          integer NOT NULL DEFAULT 0,         -- calibração (advisory)
    invalidated       integer NOT NULL DEFAULT 0,
    created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_rfc_participants ON rfc_participants (rfc_id, agent, role);
CREATE INDEX IF NOT EXISTS idx_rfc_participants_rfc ON rfc_participants (rfc_id);
