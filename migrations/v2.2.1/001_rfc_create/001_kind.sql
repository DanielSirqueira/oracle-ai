-- =====================================================================
-- v2.2.1 — Loop Engineering: novo kind de etapa `rfc_create`.
-- A etapa que CRIA a RFC (o agente publica a spec seccionada via
-- oracle_rfc_open e grava o rfc_id no blackboard), complementando o
-- `rfc_review` que a revisa. Recria o CHECK de flow_steps.kind.
-- =====================================================================

ALTER TABLE flow_steps DROP CONSTRAINT IF EXISTS flow_steps_kind_check;
ALTER TABLE flow_steps ADD CONSTRAINT flow_steps_kind_check
    CHECK (kind IN ('agent','orchestrator','rfc_create','rfc_review','command','human_gate'));
