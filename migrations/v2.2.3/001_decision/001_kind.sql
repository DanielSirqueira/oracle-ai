-- =====================================================================
-- v2.2.3 — Loop Engineering: kind `decision` — o nó de DECISÃO genérico.
-- Um agente avalia o que a etapa mandar (rodar um teste, checar um critério…)
-- e OBRIGATORIAMENTE grava no blackboard a key "verdict" com EXATAMENTE um dos
-- valores das conexões de veredito que saem do nó — o runner roteia por ele.
-- Serve para bifurcar o fluxo em 2..N caminhos quantas vezes for preciso
-- (ex.: teste falhou → volta para as rodadas do RFC; passou → segue ao PR).
-- Recria o CHECK de flow_steps.kind.
-- =====================================================================

ALTER TABLE flow_steps DROP CONSTRAINT IF EXISTS flow_steps_kind_check;
ALTER TABLE flow_steps ADD CONSTRAINT flow_steps_kind_check
    CHECK (kind IN ('agent','orchestrator','decision','rfc_create','rfc_review',
                    'rfc_consolidate','rfc_gate','command','human_gate'));
