-- =====================================================================
-- v2.2.4 — Loop Engineering: kind `subflow` — etapa que executa OUTRO processo
-- (como o "Execute Workflow" do n8n). O runner cria um run FILHO do processo
-- alvo (config.flowKey), copia o blackboard do pai para o filho, dirige o filho
-- INLINE no MESMO workspace/worktree do pai (mesma branch — um escritor) e, ao
-- concluir, mescla o blackboard do filho de volta no pai. Profundidade máxima 3.
-- Também permite o artefato kind 'run' (o vínculo pai -> run filho).
-- =====================================================================

ALTER TABLE flow_steps DROP CONSTRAINT IF EXISTS flow_steps_kind_check;
ALTER TABLE flow_steps ADD CONSTRAINT flow_steps_kind_check
    CHECK (kind IN ('agent','orchestrator','decision','rfc_create','rfc_review',
                    'rfc_consolidate','rfc_gate','subflow','command','human_gate'));

ALTER TABLE flow_artifacts DROP CONSTRAINT IF EXISTS flow_artifacts_kind_check;
ALTER TABLE flow_artifacts ADD CONSTRAINT flow_artifacts_kind_check
    CHECK (kind IN ('branch','commit','pr','rfc','doc','file','memory','run','other'));
