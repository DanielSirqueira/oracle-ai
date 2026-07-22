-- =====================================================================
-- v2.2.2 — Loop Engineering: o LOOP DE RODADAS do RFC no processo.
--   rfc_consolidate — agente que analisa os achados da rodada, resolve
--                     comentários, REVISA a RFC (oracle_rfc_revise) e escreve o
--                     plano de implementação no blackboard.
--   rfc_gate        — portão DETERMINÍSTICO (sem IA): consulta o motor RFC
--                     (status + contagens) e roteia por veredito:
--                     'continuar' (nova rodada), 'concluir' (sem achados
--                     bloqueantes/novos) ou 'limite' (máx. de rodadas).
-- Recria o CHECK de flow_steps.kind.
-- =====================================================================

ALTER TABLE flow_steps DROP CONSTRAINT IF EXISTS flow_steps_kind_check;
ALTER TABLE flow_steps ADD CONSTRAINT flow_steps_kind_check
    CHECK (kind IN ('agent','orchestrator','rfc_create','rfc_review',
                    'rfc_consolidate','rfc_gate','command','human_gate'));
