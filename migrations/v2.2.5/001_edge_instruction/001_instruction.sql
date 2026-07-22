-- =====================================================================
-- v2.2.5 — Loop Engineering: decisão NAS CONEXÕES (vale para todos os nós).
-- Uma conexão de veredito ganha uma INSTRUÇÃO: "quando seguir por aqui"
-- (ex.: 'sem-achados' — "quando o RFC não tiver mais achados abertos").
-- O prompt do agente do nó lista cada rota com sua instrução; o agente grava
-- o veredito correspondente e o runner segue a conexão — sem precisar de um
-- nó de decisão dedicado (que continua existindo como avaliador leve).
-- =====================================================================

ALTER TABLE flow_edges ADD COLUMN IF NOT EXISTS instruction text;
