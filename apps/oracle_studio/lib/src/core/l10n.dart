import 'package:flutter/foundation.dart';

/// Lightweight runtime localization (pt/en). The whole app listens to [l10n]
/// at the MaterialApp root, so switching language rebuilds every screen.
final l10n = L10n();

class L10n extends ChangeNotifier {
  String code = 'pt';

  void set(String c) {
    if (c == code) return;
    code = c;
    notifyListeners();
  }

  String t(String key) =>
      (code == 'pt' ? _pt[key] : _en[key]) ?? _pt[key] ?? key;
}

const _pt = <String, String>{
  // app / connection
  'app.connecting': 'Conectando ao banco de memória…',
  'app.connectFailTitle': 'Não foi possível conectar',
  'app.retry': 'Tentar novamente',
  'app.noEnv':
      'Nenhum .env encontrado — usando defaults (localhost:5432). Defina ORACLE_ENV_PATH ou coloque um .env na raiz do projeto.',
  'app.config': 'Configuração',
  'records.search': 'Buscar registros…',
  'records.clearSearch': 'Limpar busca',
  'records.result': 'resultado',
  'records.results': 'resultados',
  'records.all': 'Todos',
  'records.noMatch': 'Nenhum registro corresponde aos filtros',
  'records.noMatchHint': 'Tente ajustar a busca ou remover algum filtro.',
  'sess.requests': 'Demandas',
  'sess.messages': 'Mensagens',
  'hist.recordUnavailable': 'Registro não disponível',
  'hist.recordUnavailableHint':
      'O registro original foi removido e este histórico antigo guardava somente o identificador.',
  // shell
  'nav.groupOverview': 'Visão geral',
  'nav.groupKnowledge': 'Conhecimento',
  'nav.groupActivity': 'Atividade',
  'nav.groupSystem': 'Sistema',
  'nav.dashboard': 'Painel',
  'nav.dashboardHint': 'Resumo do projeto e de todo o acervo',
  'nav.search': 'Buscar',
  'nav.searchHint': 'Busca híbrida em memórias, regras e skills',
  'nav.memories': 'Memórias',
  'nav.memoriesHint': 'Aprendizados consolidados do projeto',
  'nav.rules': 'Regras',
  'nav.rulesHint': 'Regras de desenvolvimento (severidade e prioridade)',
  'nav.rfcs': 'RFCs',
  'nav.rfcsHint': 'Specs técnicas em revisão multiagente (gate de conclusão)',
  'nav.skills': 'Skills',
  'nav.skillsHint': 'Biblioteca de skills compartilhada entre agentes',
  'nav.modules': 'Módulos',
  'nav.modulesHint': 'Subdivisões do projeto (serviço, camada, pacote)',
  // Loop Engineering
  'nav.groupLoop': 'Loop Engineering',
  'nav.tasks': 'Tarefas',
  'nav.tasksHint': 'Backlog de tarefas de desenvolvimento',
  'nav.flows': 'Processos',
  'nav.flowsHint': 'Fluxos de desenvolvimento multiagente (etapas = loops)',
  'nav.runs': 'Execuções',
  'nav.runsHint': 'Monitorar os runs dos processos',
  'flows.header': 'Processos',
  'flows.new': 'Novo processo',
  'flows.newTitle': 'Novo processo',
  'flows.template': 'Modelo',
  'flows.empty': 'Nenhum processo ainda — crie um a partir de um modelo.',
  'flows.selectOne': 'Selecione um processo',
  'flows.saved': 'Processo salvo.',
  'flows.fKey': 'Chave',
  'flows.fKeyDesc':
      'Identidade estável — re-salvar a mesma chave cria uma nova versão',
  'flows.fName': 'Nome',
  'flows.fNameDesc': 'Nome legível do processo',
  'flows.fDesc': 'Descrição',
  'flows.fOrchestrator': 'Orquestrador',
  'flows.fBudget': 'Orçamento de tokens (máx.)',
  'flows.fBudgetDesc': 'Opcional — o run para (stall) ao exceder',
  'flows.keyRequired': 'Informe a chave',
  'flows.nameRequired': 'Informe o nome',
  'flows.stepKeyRequired': 'Toda etapa precisa de uma chave',
  'flows.steps': 'Etapas (cada etapa é um loop)',
  'flows.stepsShort': 'etapas',
  'flows.edges': 'Ligações',
  'flows.edgesHint':
      'Sem ligações = cadeia linear automática (success). Adicione para ramificar/voltar (verdict/failure).',
  'flows.noEdges': 'Sem ligações.',
  'flows.add': 'Adicionar',
  'flows.step': 'Etapa',
  'flows.entry': 'Entrada',
  'flows.maxIter': 'máx.',
  'flows.verifier': 'Verificador',
  'flows.fStepKey': 'Chave',
  'flows.fStepName': 'Nome',
  'flows.fKind': 'Tipo',
  'flows.fAgent': 'Agente',
  'flows.fRole': 'Papel',
  'flows.fMaxIter': 'Máx. iterações',
  'flows.fExit': 'Comandos de verificação',
  'flows.fExitDesc': 'Rodados FORA do agente; separados por vírgula',
  'flows.fPrompt': 'Prompt',
  'flows.fCommand': 'Comando',
  'flows.fOnFail': 'Ao falhar',
  'flows.from': 'De',
  'flows.to': 'Para',
  'flows.condition': 'Condição',
  'flows.verdict': 'Veredito',
  // editor n8n-style
  'flows.editorNew': 'Novo processo',
  'flows.editorEdit': 'Editar processo',
  'flows.saveProcess': 'Salvar processo',
  'flows.canvas': 'Etapas do processo',
  'flows.canvasHint':
      'Role para navegar · Ctrl + rolagem para zoom · botão do meio ou Espaço + arrastar para mover · duplo clique na linha para editar.',
  'flows.expandField': 'Abrir editor ampliado',
  'flows.expandedEditor': 'Editor de texto',
  'flows.organize': 'Organizar automaticamente',
  'flows.fitView': 'Ajustar processo à tela',
  'flows.zoomIn': 'Aumentar zoom',
  'flows.zoomOut': 'Diminuir zoom',
  'flows.snapGrid': 'Encaixar nós na grade',
  'flows.duplicate': 'Duplicar etapa',
  'flows.removeConnections': 'Remover conexões',
  'flows.secIdentity': 'Identificação',
  'flows.secProcess': 'Dados gerais do processo',
  'flows.secAgent': 'Agente',
  'flows.secExecution': 'Execução',
  'flows.addSkill': 'Adicionar skill',
  'flows.pickSkills': 'Skills cadastradas no Oracle',
  'flows.noRegisteredSkills':
      'Nenhuma skill cadastrada neste escopo — cadastre na aba Skills.',
  'flows.searchSkill': 'Filtrar por nome, chave ou descrição…',
  // diagnóstico de agente
  'flows.health.checking': 'Verificando o agente…',
  'flows.health.ready': 'Pronto — CLI, MCP e captura funcionando',
  'flows.health.warn': 'Executa — mas há avisos (captura/hooks ou sandbox)',
  'flows.health.fail': 'NÃO vai executar — corrija antes de rodar',
  'flows.health.details': 'ver detalhes',
  'flows.health.title': 'Diagnóstico do agente',
  'flows.health.cli': 'CLI disponível',
  'flows.health.mcp': 'MCP do Oracle configurado',
  'flows.health.hooks': 'Hooks configurados (captura)',
  'flows.health.receiver': 'Receptor de hooks ativo',
  'flows.health.cliFix':
      'Instale o CLI do agente ou configure o caminho do executável.',
  'flows.health.mcpFix':
      'Configure o MCP em Configurações → Integração de agentes.',
  'flows.health.hooksFix':
      'Adicione os hooks em Configurações → Integração de agentes.',
  'flows.health.receiverFix':
      'Ligue "Hospedar hooks" nas Configurações (daemon).',
  'flows.health.sandbox': 'Sandbox do agente (shell)',
  'flows.health.sandboxFix':
      'O Codex resolve o pwsh.exe pelo alias da Microsoft Store (WindowsApps), '
      'que o sandbox dele não consegue executar ("Acesso negado"). No Windows, '
      'etapas de ESCRITA já rodam sem o sandbox do SO (não são afetadas); isso '
      'atinge etapas somente-leitura e o uso interativo do Codex. Correção: '
      'instale o PowerShell 7 fora da Store — winget install --id '
      'Microsoft.PowerShell --scope machine — ou desative o alias em '
      'Configurações do Windows → Aplicativos → Aliases de execução de '
      'aplicativo.',
  'flows.health.smoke': 'Rodar teste real',
  'flows.health.smokeRunning': 'Testando… (pode levar minutos)',
  'flows.health.smokeOk': 'Teste real: o agente respondeu',
  'flows.health.smokeFail': 'Teste real: falhou',
  'flows.health.recheck': 'Reverificar',
  // presets (nome, descrição e PROMPT da etapa)
  'flows.preset.dev': 'Implementação',
  'flows.presetDesc.dev': 'Agente que implementa a tarefa no código',
  'flows.presetPrompt.dev':
      'Implemente a tarefa conforme o plano do run. Faça commit ao final.',
  'flows.preset.review': 'Revisão de código',
  'flows.presetDesc.review': 'Agente que revisa e corrige o diff da branch',
  'flows.presetPrompt.review':
      'Revise o diff da branch: corretude, simplicidade e aderência às regras do projeto. '
      'Corrija o que encontrar e registre um resumo dos achados no blackboard.',
  'flows.preset.security': 'Segurança',
  'flows.presetDesc.security': 'Agente focado em vulnerabilidades no diff',
  'flows.presetPrompt.security':
      'Analise o diff da branch por vulnerabilidades e más práticas de segurança; corrija e '
      'registre os achados no blackboard.',
  'flows.preset.tests': 'Testes',
  'flows.presetDesc.tests': 'Agente que cobre a mudança com testes',
  'flows.presetPrompt.tests':
      'Escreva/atualize testes para a mudança e garanta que a suíte passa.',
  'flows.preset.docs': 'Documentação',
  'flows.presetDesc.docs': 'Agente que atualiza a documentação',
  'flows.presetPrompt.docs':
      'Atualize a documentação do projeto com base no diff da branch.',
  'flows.preset.pr': 'Pull request',
  'flows.presetDesc.pr': 'Agente que abre o PR da branch',
  'flows.presetPrompt.pr':
      'Abra o pull request da branch e registre a URL como artifact (kind "pr").',
  // template
  'flows.tplName': 'Feature completa',
  'flows.tplPlanName': 'Planejar',
  'flows.tplPlanPrompt':
      'Analise a tarefa, escreva um plano de implementação no blackboard (key "plan") e um '
      'brief objetivo para cada etapa seguinte.',
  'flows.tplDevName': 'Implementar',
  'flows.tplEdgeContinuar':
      'Quando ainda houver achados abertos: nova rodada de revisão',
  'flows.tplEdgeConcluir':
      'Quando não houver mais achados bloqueantes nem novos: seguir para a implementação',
  'flows.tplEdgeLimite':
      'Quando atingir o limite de rodadas: parar e chamar um humano',
  'flows.tplEdgeReprovado':
      'Quando qualquer teste falhar: voltar para a implementação corrigir',
  'flows.tplEdgeAprovado':
      'Quando TODOS os testes passarem: seguir para a documentação',
  'flows.tplTestName': 'Testes passaram?',
  'flows.tplTestPrompt':
      'Rode a suíte de testes do projeto no workspace (ex.: dart test) e avalie o resultado. '
      'Se TODOS os testes passarem, grave o veredito "aprovado"; se qualquer teste falhar, '
      'grave "reprovado" e registre no relatório quais testes falharam e por quê. '
      'NÃO corrija nada nesta etapa — apenas avalie e decida a rota.',
  'flows.tplDocsName': 'Documentar',
  'flows.tplPrName': 'Pull request',
  'flows.tplGateName': 'Aprovação humana',
  'flows.tplRfcName': 'Criar RFC',
  'flows.tplReviewName': 'Revisar RFC',
  'flows.tplConsName': 'Consolidar e planejar',
  'flows.tplRoundsName': 'Rodadas',
  'flows.fMaxRounds': 'Máx. de rodadas',
  'flows.fMaxRoundsDesc':
      'Quantas vezes o portão pode mandar de volta para revisão; depois disso roteia por "limite"',
  'flows.keyLocked':
      'A chave é a identidade do processo — salvar cria uma nova versão da MESMA chave; por isso ela não muda ao editar',
  'g.kindUse.rfc_consolidate':
      'Use após a revisão: resolve achados, revisa a RFC e escreve o plano.',
  'g.kindUse.rfc_gate':
      'Use após a consolidação: sem IA, emite o veredito continuar/concluir/limite — e cada veredito é uma conexão que você aponta para onde quiser (ex.: limite → aprovação humana ou outro caminho).',
  // status do worker (daemon)
  'set.workerSt.on': 'ativo',
  'set.workerSt.off': 'desligado',
  'set.workerSt.stopping': 'parando…',
  // guia (documentação in-app)
  'flows.guide': 'Como funciona',
  'flows.guideTitle': 'Loop Engineering — guia de processos',
  'flows.guideMd': '''
# Como funcionam os processos (Loop Engineering)

Um **processo** é um fluxo de desenvolvimento desenhado no canvas: cada **etapa é um loop** executado por um agente de código (Claude Code, Codex, Gemini…), e as **conexões** definem a ordem. Você cria uma **tarefa**, executa com um processo, e o **Flow Runner** dirige tudo automaticamente — lançando os agentes, verificando o trabalho e avançando o fluxo.

## Pré-requisitos (sem isso nada executa)

1. **Ligue o Flow Runner** em *Configurações → Hospedar o Flow Runner* (ou pelo banner na aba Execuções). Ele é quem pega os runs da fila.
2. **Agentes prontos**: ao selecionar o agente de uma etapa, o **diagnóstico** mostra se o CLI está instalado e se o MCP do Oracle está configurado — use **"Rodar teste real"** para provar que o agente responde. Vermelho = não vai executar.
3. O projeto precisa ter um **repositório** (o run cria uma branch/worktree nele).

## O ciclo de execução

1. Você cria a tarefa e clica **Executar** com um processo → o run entra na **fila**.
2. O Flow Runner reivindica o run, cria uma **branch + worktree** git isolada e começa pela **etapa inicial** (o orquestrador, quando existir).
3. Em cada etapa de agente: o runner monta um **prompt completo** (tarefa, instruções da etapa, regras do projeto, skills, o *blackboard* com o que as etapas anteriores registraram, artefatos e critérios de saída) e lança o agente **headless** no worktree.
4. Ao final, o runner roda os **comandos de verificação FORA do agente** (o agente não se auto-aprova). Falhou → nova iteração da MESMA etapa com o erro anexado ao prompt (até o máx. de iterações). Passou → segue pelas conexões.
5. **Aprovação humana** pausa o run até você aprovar na aba Execuções. Ao terminar, a tarefa vira *Concluída*.

## Tipos de etapa

- **Orquestrador** — só pode existir UM, e ele é o **início** do fluxo. Use para planejar e decidir rotas (ele grava `verdict` no blackboard).
- **Agente** — o caso geral: implementar, revisar, documentar… (use os *modelos prontos* do seletor).
- **Revisão RFC** — revisão técnica multiagente com evidência.
- **Comando** — determinístico, sem IA (build, teste, deploy).
- **Aprovação humana** — pausa até um humano decidir.

## Configurando uma etapa (campos)

- **Agente / Modelo** — qual CLI executa e, opcionalmente, qual modelo (ex.: `opus`).
- **Papel** — a persona (implementer, reviewer, security…). Entra no prompt.
- **Prompt** — as instruções específicas da etapa. Seja objetivo: o runner já injeta tarefa, regras, blackboard e critérios automaticamente.
- **Skills** — skills da biblioteca do Oracle que o agente carrega antes de trabalhar.
- **Comandos de verificação** — a prova objetiva (ex.: `dart analyze, dart test`). São o coração do loop: sem eles a etapa passa só pelo relatório do agente.
- **Máx. iterações** — quantas tentativas a etapa tem para passar na verificação.
- **Timeout** — vazio = **sem limite** (agentes podem rodar horas). Use só como válvula de segurança.
- **Ao falhar** — esgotou as iterações: *Aguardar humano* (recomendado), *Falhar o run* ou *Continuar mesmo assim*.

## Conexões

- Arraste a bolinha **→** de um nó até outro. Padrão: **Sucesso** (segue quando a verificação passa).
- **Falha** — rota alternativa quando a etapa esgota as iterações.
- **Veredito** — rota escolhida pelo orquestrador (ele grava `verdict` no blackboard; a conexão dispara quando o valor bate). Ex.: `aprovado` segue, `rejeitado` volta ao planejamento.
- **Sempre** — segue independente do resultado.
- **Ramificações**: um nó pode alimentar vários (executam um após o outro) e vários podem convergir num só (o *join* espera todos). **Voltar** para uma etapa anterior re-executa o trecho.

## Boas práticas para um bom loop

- **Etapas pequenas com verificação objetiva** — um loop sem verificador confiável não converge.
- **Um escritor por vez** — concentre a escrita de código numa etapa; revisores registram achados no blackboard.
- **Use o orquestrador para decidir**, não para trabalhar — planejamento e vereditos.
- **Defina orçamento de tokens** no processo para runs longos.
- **Acompanhe na aba Execuções** — cada iteração mostra o prompt enviado, o relatório do agente e a saída da verificação.
''',
  'set.hooksSt.off': 'desligado',
  'set.hooksSt.on': 'ativo em',
  'set.hooksSt.reserved':
      'porta reservada pelo Windows — escolha uma porta abaixo de 49152 nas configurações',
  'set.hooksSt.busy':
      'porta ocupada — outro processo serve os hooks; assumo automaticamente quando ele sair',
  'flows.connect': 'Conectar a outra etapa',
  'flows.connectingFrom': 'Conectando de',
  'flows.connectingHint': 'clique no nó de destino (ou no X para cancelar)',
  'flows.startBadge': 'INÍCIO',
  'flows.setEntry': 'Etapa inicial do fluxo',
  'flows.fModel': 'Modelo (opcional)',
  'flows.fModelDesc':
      'Alias aceito pelo CLI do agente (ex.: opus) — vazio usa o padrão',
  'flows.fSkills': 'Skills do Oracle',
  'flows.fSkillsDesc':
      'Skills da biblioteca do Oracle que o agente carrega antes de trabalhar — escolha entre as cadastradas',
  'flows.fTimeoutDesc': 'Vazio = sem limite (agentes podem rodar por horas)',
  'flows.presets': 'Modelos prontos (etapas de agente)',
  'flows.deleteConnection': 'Remover conexão',
  'flows.onlyOneOrchestrator':
      'Só pode haver UM orquestrador — ele é quem inicia o fluxo',
  'flows.verdictDesc':
      'Valor que o agente do nó de ORIGEM grava no blackboard (key "verdict") para tomar esta rota — vale para qualquer nó, não só decisão',
  'flows.edgeInstruction': 'Quando seguir por aqui (instrução)',
  'flows.edgeInstructionDesc':
      'Vai para o prompt do agente do nó de origem junto com o veredito — ele avalia essa instrução e escolhe a rota. Ex.: "quando o RFC não tiver mais achados abertos".',
  'flows.edgeInstructionHint': 'ex.: quando todos os testes passarem',
  'flows.editConnection': 'Editar conexão',
  'flows.modelSuggestions': 'Sugestões de modelo',
  'flows.fModelDesc.claude-code':
      'Alias (fable, opus, sonnet, haiku) ou nome completo (ex.: claude-fable-5). Vazio = padrão do CLI. Pode digitar qualquer modelo válido.',
  'flows.fModelDesc.codex':
      'ID do modelo (ex.: gpt-5.5, gpt-5.4-mini, gpt-5.3-codex). Vazio = padrão do config.toml. Pode digitar qualquer ID válido.',
  'flows.fModelDesc.gemini':
      'ID do modelo (ex.: gemini-3-pro-preview). Vazio = roteamento automático do CLI. Pode digitar qualquer ID válido.',
  'flows.fModelDesc.cursor':
      'ID do modelo — liste os válidos com "cursor-agent --list-models". Vazio = padrão do Cursor.',
  'flows.fModelDesc.copilot':
      'ID do modelo (ex.: claude-sonnet-4.5). Vazio = padrão do Copilot.',
  'flows.fEffort': 'Raciocínio (esforço)',
  'flows.fEffortDesc.claude-code':
      'Vira a flag --effort do Claude Code. Mais esforço = mais qualidade e mais tokens; "max" só para as etapas mais difíceis.',
  'flows.fEffortDesc.codex':
      'Vira -c model_reasoning_effort do Codex (xhigh depende do modelo). Mais esforço = mais qualidade e mais tokens.',
  'floweffort.minimal': 'Mínimo',
  'floweffort.low': 'Baixo',
  'floweffort.medium': 'Médio',
  'floweffort.high': 'Alto',
  'floweffort.xhigh': 'Extra-alto',
  'floweffort.max': 'Máximo',
  'flows.insertHere': 'Inserir etapa aqui',
  'flows.addStep': 'Adicionar etapa',
  'flows.pickKind': 'Que tipo de etapa?',
  'flows.connections': 'Conexões',
  'flows.connectionsHint':
      'Por padrão cada etapa conecta na próxima (sucesso). Personalize para ramificar ou voltar (veredito/falha).',
  'flows.linearReset': 'Voltar ao encadeamento linear',
  'flows.addConnection': 'Adicionar conexão',
  'flows.moveLeft': 'Mover para a esquerda',
  'flows.moveRight': 'Mover para a direita',
  'flows.dupStepKey': 'Há chaves de etapa duplicadas',
  'flows.edit': 'Editar',
  'flows.noCommand': 'sem comando',
  'flows.fStepKeyDesc': 'Identificador curto e único da etapa',
  'flows.fRoleDesc': 'Persona do agente nesta etapa',
  'flows.fPromptDesc': 'Instruções específicas desta etapa para o agente',
  'flows.fCommandDesc': 'Comando executado pelo runner (sem IA)',
  'flows.fTimeout': 'Timeout (min)',
  'flows.fTokenBudget': 'Limite de tokens da etapa',
  'flows.fTokenBudgetDesc': 'Vazio = sem limite específico para esta etapa',
  'flows.fVerifierTimeout': 'Timeout da verificação (min)',
  'flows.fVerifierTimeoutDesc':
      'Limite separado para cada comando de verificação',
  'flows.fOutputSchema': 'Contrato da saída (JSON Schema)',
  'flows.fOutputSchemaDesc': 'Valida o objeto outputs informado pelo agente',
  'flows.fPermissions': 'Permissões da etapa',
  'flows.fPermissionsDesc': 'JSON: workspace read/write, shell e mcp',
  // rótulos amigáveis dos enums
  'flowkind.agent': 'Agente',
  'flowkind.orchestrator': 'Orquestrador',
  'flowkind.decision': 'Decisão',
  'flowkindDesc.decision':
      'Um agente avalia um critério (teste, checagem…) e escolhe entre 2+ caminhos gravando "verdict"',
  'flowkind.subflow': 'Sub-processo',
  'flowkindDesc.subflow':
      'Executa OUTRO processo dentro deste (como no n8n): mesmo workspace, blackboard compartilhado',
  'flowkind.join': 'Junção',
  'flowkindDesc.join':
      'Aguarda todas as ramificações ativas que chegam aqui e continua uma única vez, sem executar agente',
  'flows.secSubflow': 'Sub-processo',
  'flows.fSubflow': 'Processo a executar',
  'flows.fSubflowNone': '— selecione um processo —',
  'flows.fSubflowDesc':
      'O runner executa o processo escolhido como um run FILHO, no mesmo workspace deste run; '
      'o blackboard desce para o filho e volta mesclado quando ele conclui. Máx. 3 níveis.',
  'flows.noSubflow': 'sem processo alvo',
  'flows.subflowRequired':
      'Toda etapa Sub-processo precisa de um processo alvo selecionado',
  'flows.unsupportedAgent':
      'O agente selecionado não possui executor automático compatível',
  'flows.invalidMaxIterations': 'Máx. de iterações deve ser pelo menos 1',
  'flows.invalidTimeout':
      'Timeout deve estar vazio ou ser um número inteiro não negativo',
  'flows.commandRequired': 'Uma etapa Comando precisa informar o comando',
  'flows.invalidMaxRounds': 'Máx. de rodadas deve ser pelo menos 1',
  'flows.joinIncomingRequired':
      'A Junção precisa receber pelo menos duas ramificações',
  'flows.decisionVerdictsRequired':
      'Uma Decisão precisa ter pelo menos duas conexões de veredito',
  'flows.invalidVerdictValues':
      'Os vereditos de uma Decisão devem ser preenchidos e não podem se repetir',
  'flows.fTags': 'Tags (comandos do agente)',
  'flows.fTagsDesc':
      'Separadas por vírgula; viram linhas /tag no INÍCIO do prompt — no Claude Code, "review" '
      'aciona o comando /review. Deixe vazio se não precisar.',
  'flowkind.rfc_create': 'Criação de RFC',
  'flowkind.rfc_review': 'Revisão RFC',
  'flowkind.command': 'Comando',
  'flowkind.human_gate': 'Aprovação humana',
  'flowkindDesc.agent':
      'Um agente de código executa a etapa em loop até passar na verificação',
  'flowkindDesc.orchestrator':
      'O agente-orquestrador do processo planeja ou decide a rota',
  'flowkind.rfc_consolidate': 'Consolidação RFC',
  'flowkind.rfc_gate': 'Rodadas RFC',
  'flowkindDesc.rfc_create':
      'Um agente PUBLICA a spec da tarefa como RFC seccionada (oracle_rfc_open)',
  'flowkindDesc.rfc_review':
      'Revisão técnica multiagente com evidência (motor RFC)',
  'flowkindDesc.rfc_consolidate':
      'Agente que resolve os achados da rodada, REVISA a RFC e escreve o plano de implementação',
  'flowkindDesc.rfc_gate':
      'Portão determinístico (sem IA): decide continuar (nova rodada), concluir ou limite',
  'flowkindDesc.command':
      'Comando determinístico (build, teste, deploy) — sem IA',
  'flowkindDesc.human_gate': 'Pausa o run até um humano aprovar no Studio',
  'runst.queued': 'Na fila',
  'runst.running': 'Executando',
  'runst.awaiting_human': 'Aguardando aprovação',
  'runst.paused': 'Pausado',
  'runst.stalled': 'Estagnado',
  'runst.completed': 'Concluído',
  'runst.failed': 'Falhou',
  'runst.cancelled': 'Cancelado',
  'taskst.backlog': 'Backlog',
  'taskst.ready': 'Pronta',
  'taskst.running': 'Em execução',
  'taskst.blocked': 'Bloqueada',
  'taskst.done': 'Concluída',
  'taskst.cancelled': 'Cancelada',
  'stepst.running': 'Executando',
  'stepst.verifying': 'Verificando',
  'stepst.passed': 'Passou',
  'stepst.failed': 'Falhou',
  'stepst.skipped': 'Pulada',
  'stepst.parked': 'Aguardando humano',
  'stepst.abandoned': 'Interrompida',
  'flowcond.success': 'Sucesso',
  'flowcond.failure': 'Falha',
  'flowcond.verdict': 'Veredito',
  'flowcond.always': 'Sempre',
  'flowfail.park': 'Aguardar humano',
  'flowfail.halt': 'Falhar o run',
  'flowfail.continue': 'Continuar mesmo assim',
  'flowev.state': 'Estado',
  'flowev.step_start': 'Início de etapa',
  'flowev.step_end': 'Fim de etapa',
  'flowev.verifier': 'Verificador',
  'flowev.iteration': 'Iteração',
  'flowev.decision': 'Decisão',
  'flowev.gate': 'Aprovação',
  'flowev.budget': 'Orçamento',
  'flowev.error': 'Erro',
  'flowev.info': 'Info',
  'tasks.header': 'Tarefas',
  'tasks.new': 'Nova tarefa',
  'tasks.newTitle': 'Nova tarefa',
  'tasks.empty': 'Nenhuma tarefa no backlog.',
  'tasks.created': 'Tarefa criada.',
  'tasks.run': 'Executar',
  'tasks.completed': 'Concluída',
  'tasks.terminalNoRerun':
      'Esta tarefa já foi encerrada e não pode ser executada novamente. Crie uma nova tarefa para outra solicitação.',
  'tasks.alreadyRunning': 'Esta tarefa já possui uma execução em andamento.',
  'tasks.enqueued': 'Run enfileirado',
  'tasks.noFlows': 'Crie um processo antes de executar.',
  'tasks.pickFlow': 'Escolha o processo',
  'tasks.fTitle': 'Título',
  'tasks.fDesc': 'Descrição',
  'tasks.fPriority': 'Prioridade',
  'tasks.fPriorityDesc': '0..100 (padrão 50)',
  'tasks.titleRequired': 'Informe o título',
  'runs.header': 'Execuções',
  'runs.refresh': 'Atualizar',
  'runs.allRuns': 'Todas',
  'runs.activeRuns': 'Ativas',
  'runs.noActiveRuns': 'Nenhuma execução ativa.',
  'runs.graphHint': 'Arraste para mover · Ctrl + scroll para zoom',
  'runs.sectionExecution': 'Execução',
  'runs.sectionSessions': 'Sessões',
  'runs.openSession': 'Abrir sessão',
  'runs.sessionPrompt': 'Solicitação enviada ao agente',
  'runs.sessionAnswer': 'Atividade e resposta',
  'runs.noSessionsYet': 'Nenhuma sessão foi vinculada a esta execução.',
  'runs.legacySessionMissing':
      'Esta iteração antiga não possui sessão vinculada. Novas execuções criam a sessão obrigatoriamente.',
  'runs.stepsCompleted': 'etapas concluídas',
  'runs.now': 'Agora',
  'runs.withIssue': 'com atenção',
  'runs.sectionData': 'Dados',
  'runs.sectionEvents': 'Eventos',
  'runs.noDataYet': 'O processo ainda não produziu dados ou artefatos.',
  'runs.noEventsYet': 'Nenhum evento foi registrado nesta execução.',
  'runs.zoomIn': 'Aumentar zoom',
  'runs.zoomOut': 'Diminuir zoom',
  'runs.resetView': 'Restaurar visualização',
  'runs.empty': 'Nenhum run ainda.',
  'runs.selectOne': 'Selecione um run',
  'runs.run': 'Run',
  'runs.approve': 'Aprovar',
  'runs.reject': 'Rejeitar',
  'runs.rejectQ': 'Rejeitar o run?',
  'runs.rejectMsg': 'O run será marcado como falho.',
  'runs.approved': 'Aprovado — o run retoma.',
  'runs.rejected': 'Run rejeitado.',
  'runs.pause': 'Pausar',
  'runs.resume': 'Retomar',
  'runs.cancel': 'Cancelar',
  'runs.ctl.pause': 'Run pausado.',
  'runs.ctl.resume': 'Run retomado.',
  'runs.ctl.cancel': 'Run cancelado.',
  'runs.steps': 'Etapas',
  'runs.noSteps': 'Nenhuma etapa executada ainda.',
  'runs.queuedHint':
      'O run está na fila aguardando o Flow Runner reivindicá-lo. Se nada acontecer, verifique o banner acima.',
  'runs.workerOffBody':
      'O Flow Runner está DESLIGADO — os runs ficam na fila e nenhuma etapa executa. Ligue-o para começar.',
  'runs.workerEnable': 'Ligar agora',
  'runs.promptSent': 'Prompt enviado ao agente',
  'runs.agentReport': 'Relatório do agente',
  'runs.verifierOut': 'Verificação (runner)',
  'runs.running': 'Executando — os logs aparecem quando a iteração termina.',
  'runs.copy': 'Copiar',
  'runs.copied': 'Copiado.',
  'runs.pending': 'Pendente',
  'runs.iteration': 'Iteração',
  'runs.iterations': 'iterações',
  'runs.sessionLinked': 'sessão capturada',
  'runs.interactions': 'interações',
  'runs.contextContinued': 'Contexto do agente continuado',
  'runs.nativeSession': 'Sessão nativa',
  'runs.outputs': 'Saídas',
  'runs.filesTouched': 'Arquivos alterados',
  'runs.openQuestions': 'Questões em aberto',
  'runs.verifPassed': 'Verificação passou',
  'runs.verifFailed': 'Verificação falhou',
  'runs.technical': 'Detalhes técnicos',
  'runs.launchCmd': 'Comando',
  'runs.agentOk': 'Agente executou',
  'runs.agentFail': 'Agente FALHOU',
  'flows.modelDefault': 'Padrão do agente',
  // guia visual
  'g.heroTitle': 'Processos, tarefas e execuções',
  'g.heroSub':
      'Você desenha o processo uma vez; o Oracle executa quantas tarefas quiser com ele — com agentes reais, verificação objetiva e você no controle.',
  'g.cProcess': 'Processo',
  'g.cProcessBody':
      'O fluxo desenhado no canvas: cada etapa é um loop executado por um agente; as conexões definem a ordem. Versionado pela chave.',
  'g.cTask': 'Tarefa',
  'g.cTaskBody':
      'A demanda de desenvolvimento (o que fazer). Vive no backlog e é o gatilho: Executar = tarefa + processo.',
  'g.cRun': 'Execução',
  'g.cRunBody':
      'Uma rodada do processo para uma tarefa. O Flow Runner dirige tudo e você acompanha ao vivo, etapa por etapa.',
  'g.cycleTitle': 'O ciclo em 4 passos',
  'g.cycle1': 'Criar o processo',
  'g.cycle1Body':
      'No canvas: adicione etapas, conecte uma na outra, configure agentes e verificações.',
  'g.cycle2': 'Criar a tarefa',
  'g.cycle2Body':
      'Título + descrição clara do que precisa ser feito — vira o coração do prompt.',
  'g.cycle3': 'Executar',
  'g.cycle3Body':
      'Escolha o processo. O run entra na fila e o Flow Runner assume.',
  'g.cycle4': 'Acompanhar e aprovar',
  'g.cycle4Body':
      'Na aba Execuções: logs por etapa, gates humanos e controles (pausar/cancelar).',
  'g.exampleTitle': 'Exemplo: o processo "Feature completa"',
  'g.exampleNote':
      'O orquestrador (INÍCIO) planeja; dev implementa até passar na verificação; docs e PR completam; a aprovação humana fecha. Com uma conexão de Veredito você faz "rejeitado" voltar ao planejamento.',
  'g.hoodTitle': 'Por baixo dos panos (como o runner executa)',
  'g.hood1': 'Fila',
  'g.hood1Body':
      'Executar enfileira o run (status "Na fila"). Nada roda sem o Flow Runner ligado.',
  'g.hood2': 'Reivindicação',
  'g.hood2Body':
      'O Flow Runner pega o run mais antigo da fila com trava no banco — dois workers nunca pegam o mesmo run.',
  'g.hood3': 'Branch + worktree',
  'g.hood3Body':
      'Uma branch git isolada (flow/…) e uma worktree são criadas no repositório do projeto — todo o trabalho acontece ali.',
  'g.hood4': 'Montagem do prompt',
  'g.hood4Body':
      'Para cada etapa de agente, o runner monta um prompt completo com:',
  'g.chipTask': 'tarefa',
  'g.chipRules': 'regras do projeto',
  'g.chipSkills': 'skills',
  'g.chipBlackboard': 'blackboard',
  'g.chipReports': 'relatórios anteriores',
  'g.chipCriteria': 'critérios de saída',
  'g.hood5': 'Lançamento do agente',
  'g.hood5Body':
      'O CLI do agente roda em modo headless na worktree, com o MCP do Oracle disponível (step_context, context_put, artifact_add, step_report).',
  'g.hood6': 'Verificação fora do agente',
  'g.hood6Body':
      'O runner roda os comandos de verificação na worktree. O agente NUNCA se auto-aprova. Falhou → nova iteração com o erro no prompt.',
  'g.hood7': 'Avanço pelo grafo',
  'g.hood7Body':
      'Passou → segue as conexões (sucesso/veredito). Ramificações executam uma após a outra; junções esperam; voltas re-executam.',
  'g.hood8': 'Conclusão',
  'g.hood8Body':
      'Gates aguardam sua aprovação. Ao final, a tarefa vira Concluída e tudo fica registrado: sessões, tokens, artefatos e timeline.',
  'g.kindsTitle': 'Tipos de etapa',
  'g.kindsNote':
      'Só pode existir UM orquestrador — e ele é sempre o INÍCIO do fluxo.',
  'g.decisionNote':
      'Como ligar: crie 2+ conexões saindo do nó com condição "Veredito" (ex.: aprovado, reprovado). '
      'O prompt do agente lista esses valores automaticamente; ele grava um deles e o runner segue a conexão correspondente.',
  'g.fieldsTitle': 'Campos de uma etapa',
  'g.fAgent':
      'Qual CLI executa a etapa; o modelo é livre (com sugestões) e o esforço de raciocínio vira a flag certa de cada CLI (--effort no Claude Code, model_reasoning_effort no Codex).',
  'g.fPrompt':
      'As instruções específicas da etapa. Seja objetivo: tarefa, regras, blackboard e critérios já são injetados automaticamente.',
  'g.fExit':
      'Comandos que PROVAM que a etapa terminou bem (ex.: dart analyze, dart test). São o coração do loop — sem eles a etapa passa só pelo relatório do agente.',
  'g.fMaxIter':
      'Quantas tentativas a etapa tem para passar na verificação antes do "Ao falhar".',
  'g.fOnFail':
      'O que fazer quando as iterações esgotam: Aguardar humano (recomendado), Falhar o run ou Continuar mesmo assim.',
  'g.connTitle': 'Conexões (as rotas do fluxo)',
  'g.connSuccess':
      'Segue quando a verificação da etapa passa. É a rota padrão.',
  'g.connFailure':
      'Rota alternativa quando a etapa esgota as iterações sem passar.',
  'g.connVerdict':
      'Rota escolhida pelo AGENTE do nó — vale para QUALQUER nó, não só decisão. Cada conexão de veredito tem um valor e uma INSTRUÇÃO ("quando seguir por aqui", ex.: "quando o RFC não tiver mais achados"); as instruções entram no prompt, o agente grava "verdict" com o valor da rota escolhida e o runner segue a conexão. Se o veredito for o único caminho de saída, o runner EXIGE que o agente grave um.',
  'g.connAlways': 'Segue independente do resultado.',
  'g.connFanout':
      'Ramificar: uma etapa pode alimentar várias — elas executam uma após a outra.',
  'g.connJoin':
      'Juntar: várias etapas convergindo numa só — a junção espera todas terminarem.',
  'g.connLoop':
      'Voltar: uma conexão para uma etapa anterior re-executa aquele trecho (ex.: rejeitado → replanejar).',
  'g.preTitle': 'Antes de executar (checklist)',
  'g.pre1':
      'Flow Runner LIGADO — Configurações → Hospedar o Flow Runner (ou o botão no banner da aba Execuções).',
  'g.pre2':
      'Agentes verdes no diagnóstico — CLI instalado + MCP do Oracle configurado; use "Rodar teste real" para provar.',
  'g.pre3': 'Projeto com repositório git — o run cria a branch/worktree nele.',
  'g.tasksTitle': 'Tarefas (o backlog)',
  'g.tasksBody':
      'Crie tarefas com título e descrição clara — ela vira o núcleo do prompt de todas as etapas. "Executar" pergunta o processo e enfileira o run. Os status acompanham o ciclo:',
  'g.monTitle': 'Acompanhando uma execução',
  'g.mon1':
      'Prompt enviado — exatamente o que o agente recebeu, renderizado em markdown.',
  'g.mon2':
      'Relatório do agente — resumo, saídas, arquivos alterados e questões em aberto, estruturados.',
  'g.mon3':
      'Verificação — cada comando com passou/falhou e a saída de erro quando houver.',
  'g.mon4':
      'Gates humanos — o run pausa e os botões Aprovar/Rejeitar aparecem no topo.',
  'g.bestTitle': 'Boas práticas',
  'g.doTitle': 'Faça',
  'g.do1': 'Etapas pequenas com verificação objetiva (testes/build).',
  'g.do2':
      'Um escritor de código por vez; revisores registram achados no blackboard.',
  'g.do3': 'Orquestrador para planejar e decidir vereditos.',
  'g.do4': 'Orçamento de tokens no processo para runs longos.',
  'g.demoCaption':
      'Simulação: assim um run caminha pelo grafo — pendente → executando → concluída.',
  'g.cmdTitle': 'O comando por baixo (como o agente é acionado)',
  'g.cmdBody':
      'Para cada etapa de agente, o runner executa o CLI do agente em modo headless DENTRO da worktree do run — o "<prompt>" é o prompt completo montado no passo 4. O comando exato usado em cada iteração aparece no painel "Verificação" da execução.',
  'g.cmdNote':
      'A saída do CLI é analisada para extrair tokens usados e o id da sessão; o exit code + os comandos de verificação decidem se a etapa passou. O MCP do Oracle vem do .mcp.json/config do projeto — é assim que o agente acessa step_context, context_put, artifact_add e step_report.',
  'g.ctxTitle': 'Como a próxima etapa sabe o que aconteceu',
  'g.ctxBody':
      'Nenhuma etapa depende do transcript da anterior. Tudo que uma etapa produz fica registrado de forma ESTRUTURADA no banco, e o runner injeta isso no prompt da próxima — além das tools MCP para consultar ao vivo:',
  'g.ctxStepN': 'Etapa N',
  'g.ctxStepN1': 'Etapa N+1',
  'g.ctxProduces': 'PRODUZ →',
  'g.ctxChipReport': 'relatório (resumo, saídas, arquivos)',
  'g.ctxChipBlackboard': 'blackboard (plan, rfc_id, verdict…)',
  'g.ctxChipArtifacts': 'artefatos (PR, commit, RFC)',
  'g.ctxChipCommit': 'commits na branch do run',
  'g.ctx1':
      'O prompt da etapa N+1 já chega com os resumos dos relatórios anteriores e o blackboard inline.',
  'g.ctx2':
      'A tool oracle_flow_step_context devolve tudo ao vivo (tarefa, blackboard, relatórios, artefatos).',
  'g.ctx3':
      'O código em si viaja pela branch git do run — a etapa seguinte trabalha sobre os commits da anterior.',
  'g.ctx4':
      'Por isso: registre no blackboard o que as próximas etapas precisam — transcript não é passado.',
  'g.kindUse.agent':
      'Use para qualquer trabalho de código: implementar, revisar, testar, documentar.',
  'g.kindUse.orchestrator':
      'Use no início para planejar, e em pontos de decisão (grava "verdict" para rotear).',
  'g.kindUse.decision':
      'Avaliador dedicado: só avalia e roteia (não implementa nada). Lembre: QUALQUER nó pode rotear por conexões de veredito com instruções — use este tipo quando quiser a avaliação como etapa separada.',
  'g.kindUse.subflow':
      'Use para compor processos: um fluxo de "code review" ou "release" vira uma etapa reutilizável dentro de outros — o filho roda no mesmo workspace e devolve o blackboard.',
  'g.kindUse.rfc_create':
      'Use após o planejamento para formalizar a spec como RFC antes de implementar.',
  'g.kindUse.rfc_review':
      'Use depois da criação da RFC: revisores apontam gaps/bugs com evidência.',
  'g.kindUse.command':
      'Use para passos determinísticos: build, migração, deploy, lint.',
  'g.kindUse.human_gate':
      'Use antes de ações irreversíveis (merge, release) — o run espera você.',
  'g.mon5':
      'Comando — a linha exata de CLI que acionou o agente/etapa, no painel Verificação.',
  'g.dontTitle': 'Evite',
  'g.dont1': 'Etapas sem comandos de verificação — o loop não converge.',
  'g.dont2': 'Duas etapas escrevendo código em paralelo na mesma branch.',
  'g.dont3': 'Prompts gigantes repetindo o que o runner já injeta.',
  'g.dont4':
      'Timeout curto em etapas de agente — eles podem legitimamente rodar horas.',
  'tasks.workerOff':
      'Run enfileirado — mas o Flow Runner está DESLIGADO. Ligue-o na aba Execuções ou nas Configurações.',
  'runs.blackboard': 'Blackboard (contexto)',
  'runs.artifacts': 'Artefatos',
  'runs.timeline': 'Linha do tempo',
  'runs.tokens': 'tokens',
  'runs.worktree': 'Workspace',
  'runs.worktreeHint':
      'Worktree git isolado onde os agentes deste run trabalham — mesmo projeto, branch própria. Clique para copiar o caminho.',
  'runs.skip': 'Pular etapa',
  'runs.skipQ': 'Pular etapa',
  'runs.skipMsg':
      'A etapa atual será marcada como PULADA (sem executar/re-tentar) e o fluxo segue adiante. Se uma tentativa estiver rodando agora, o pulo vale assim que ela terminar. Use quando a etapa já foi resolvida por fora ou está travando o processo.',
  'runs.skipTo': 'Seguir por qual conexão?',
  'runs.skipQueued': 'Pulo registrado — vale na próxima fronteira da etapa',
  'runs.parkedRetryHint':
      'Este run pausou porque a etapa FALHOU (não é aprovação normal): Aprovar = re-executar a etapa; "Pular etapa" = seguir adiante sem ela; Rejeitar = encerrar o run.',
  'runs.currentStep': 'Em execução agora',
  'runs.nextSteps': 'Próximas etapas',
  'runs.doneSteps': 'Etapas executadas',
  'runs.verifRunning': 'Etapa em execução — o agente está trabalhando…',
  'runs.subflowRan': 'Sub-processo',
  'mod.intro':
      'Módulos do projeto (auto-resolvidos pela subpasta). Reclassifique um "projeto falso" como módulo aqui.',
  'mod.empty':
      'Nenhum módulo ainda. Os agentes criam via oracle_module_resolve, ou reclassifique um projeto.',
  'mod.reclassify': 'Reclassificar projeto',
  'mod.reclassifyTitle': 'Reclassificar projeto como módulo',
  'mod.reclassifyDesc':
      'Escolha um projeto que na verdade é um módulo de "{p}". Ele vira um módulo daqui, com regras/memórias/arquitetura/skills e histórico re-apontados; o projeto solto é removido.',
  'mod.sourceProject': 'Projeto a reclassificar',
  'mod.noOtherProjects': 'Não há outro projeto para reclassificar.',
  'mod.reclassified': 'Projeto reclassificado como módulo.',
  'nav.sessions': 'Sessões',
  'nav.sessionsHint': 'Histórico capturado: sessões, demandas e mensagens',
  'nav.handoffs': 'Handoffs',
  'nav.handoffsHint':
      'Passagem de contexto entre sessões (pendentes e histórico)',
  'nav.searchHistory': 'Histórico de pesquisa',
  'nav.searchHistoryHint':
      'O que os agentes buscaram × o que voltou (audite a recuperação)',
  'hist.intro':
      'Cada busca dos agentes: ferramenta, query e o que voltou. Buscas vazias = lacunas na memória.',
  'hist.onlyGaps': 'Só lacunas',
  'hist.noGaps': 'Nenhuma busca vazia. 🎉',
  'hist.empty': 'Nenhuma pesquisa registrada ainda.',
  'hist.gap': 'lacuna (0 resultados)',
  'hist.hits': 'resultados',
  'hist.selectOne': 'Selecione uma pesquisa para ver os resultados.',
  'hist.filters': 'Filtros',
  'hist.results': 'Resultados retornados',
  'hist.gapNote':
      'Nada voltou — pode ser uma lacuna: o que foi pedido não está na memória, ou o termo não casou.',
  'nav.duplicates': 'Duplicatas',
  'nav.duplicatesHint': 'Encontrar e limpar itens quase duplicados',
  'handoff.empty':
      'Nenhum handoff ainda. O agente cria um ao final de uma tarefa.',
  'handoff.selectOne': 'Selecione um handoff para ver o contexto.',
  'handoff.contextTitle': 'Contexto da passagem',
  'handoff.open': 'Pendente',
  'handoff.accepted': 'Aceito',
  'handoff.expired': 'Expirado',
  'handoff.nextSteps': 'Próximos passos',
  'handoff.openQuestions': 'Questões em aberto',
  'handoff.filesTouched': 'Arquivos alterados',
  'dup.intro':
      'Itens quase idênticos agrupados por proximidade de embedding. Mantenha um e aposente os demais.',
  'dup.memories': 'Memórias',
  'dup.rules': 'Regras',
  'dup.rescan': 'Reescanear',
  'dup.runSweep': 'Rodar deduplicação agora',
  'dup.none': 'Nenhuma duplicata encontrada. 🎉',
  'dup.items': 'itens',
  'dup.retireOthers': 'Aposentar as outras',
  'dup.keep': 'Manter esta',
  'dup.retireQ': 'Aposentar duplicatas?',
  'dup.retireMsg':
      'As outras {n} memórias serão aposentadas (soft — recuperáveis).',
  'dup.retire': 'Aposentar',
  'dup.retired': 'Duplicatas aposentadas.',
  'dup.sweepDone': 'Deduplicação executada.',
  'nav.backup': 'Backup',
  'nav.backupHint': 'Backups do banco: agora e agendados',
  'nav.settings': 'Config',
  'nav.settingsHint': 'Conexão, daemon, .env e integração de agentes',
  'shell.project': 'Projeto',
  'shell.tagline': 'Banco de memória',
  'shell.connected': 'Conectado',
  'shell.offline': 'Offline',
  'shell.daemonOn': 'daemon ativo',
  'shell.daemonOff': 'daemon parado',
  'shell.switchProject': 'Trocar de projeto',
  'shell.noProjects': 'Nenhum projeto ainda',
  'shell.deleteProject': 'Excluir projeto',
  'shell.deleteProjectConfirm':
      'Excluir o projeto "{p}" ({path})?\n\nTUDO que pertence a ele será removido: memórias, regras, sessões, skills, RFCs, processos e execuções. Use para limpar projetos registrados por engano (ex.: worktrees). Esta ação não pode ser desfeita.',
  'shell.deleteProjectDo': 'Excluir tudo',
  'shell.noPath': 'sem caminho',
  'shell.noEnvTip': 'Sem .env (defaults)',
  'tray.open': 'Abrir o Oracle Studio',
  'tray.backup': 'Fazer backup agora',
  'tray.quit': 'Encerrar',
  'tray.tooltip': 'Oracle Studio — banco de memória',
  // common
  'common.selectProject': 'Selecione um projeto.',
  'common.refresh': 'Atualizar',
  'common.cancel': 'Cancelar',
  'common.save': 'Salvar',
  'common.saving': 'Salvando…',
  'common.close': 'Fechar',
  'common.apply': 'Aplicar',
  'common.confirm': 'Confirmar',
  'common.loadError': 'Erro ao carregar',
  'common.tags': 'Tags (separadas por vírgula)',
  'common.tagsDesc':
      'Rótulos para filtrar e agrupar. Ex.: auth, backend, performance.',
  'common.editVersion': 'Editar (nova versão)',
  'common.retireSoft': 'Aposentar (mantém auditoria)',
  'common.deleteHard': 'Apagar permanentemente',
  'common.retire': 'Aposentar',
  'common.delete': 'Apagar',
  'common.failure': 'Falha',
  // dashboard
  'dash.title': 'Painel',
  'dash.subtitle':
      'Visão geral do projeto selecionado e de todo o banco de memória.',
  'dash.thisProject': 'Este projeto',
  'dash.thisProjectSub': 'Identidade e números do projeto selecionado no topo.',
  'dash.global': 'Todo o acervo',
  'dash.globalSub': 'Totais somando todos os projetos e organizações.',
  'dash.created': 'criado em',
  'dash.organizations': 'Produtos',
  'dash.projects': 'Projetos',
  'dash.modules': 'Módulos',
  'dash.tokens': 'Tokens',
  'dash.searches': 'Buscas',
  'dash.capModules': 'Subdivisões do projeto (auto-resolvidas).',
  'dash.capTokens': 'Total de tokens somando as sessões do projeto.',
  'dash.memories': 'Memórias',
  'dash.rules': 'Regras',
  'dash.skills': 'Skills',
  'dash.architectures': 'Arquiteturas',
  'dash.sessions': 'Sessões',
  'dash.requests': 'Demandas',
  'dash.messages': 'Mensagens',
  'dash.handoffs': 'Handoffs',
  'dash.capMemories': 'Aprendizados consolidados deste projeto',
  'dash.capRules': 'Regras próprias do projeto (última versão)',
  'dash.capArch': 'Notas de arquitetura por área',
  'dash.capSessions': 'Sessões de agente capturadas',
  'dash.capRequests': 'Demandas do usuário registradas',
  'dash.capHandoffs': 'Passagens de contexto entre sessões',
  'dash.health': 'Saúde do banco de memória',
  'dash.healthSub':
      'Verificações determinísticas (lint) — quanto mais zeros, melhor.',
  'dash.healthy': 'Tudo saudável',
  'dash.attention': 'Atenção necessária',
  'dash.memNoEmb': 'Memórias sem embedding',
  'dash.memNoEmbSub': 'cegas para busca semântica',
  'dash.ruleNoEmb': 'Regras sem embedding',
  'dash.ruleNoEmbSub': 'não aparecem na busca semântica',
  'dash.reqNoMsg': 'Demandas sem resposta',
  'dash.reqNoMsgSub': 'requests sem nenhuma mensagem',
  'dash.staleVec': 'Vetores de modelo antigo',
  'dash.staleVecSub': 'embeddados com outro modelo',
  'dash.model': 'modelo atual',
  'dash.metrics': 'Métricas por experimento',
  'dash.metricsSub':
      'Tokens e compactações por rótulo (A/B: oracle vs baseline).',
  'dash.noMetrics':
      'Sem métricas registradas ainda — elas aparecem conforme os agentes trabalham.',
  'dash.sessionsCol': 'Sessões',
  'dash.compactions': 'Compactações',
  // memories
  'mem.searchHint': 'Buscar memórias (híbrido: semântico + texto)…',
  'mem.new': 'Nova memória',
  'mem.editTitle': 'Editar memória (nova versão)',
  'mem.newTitle': 'Nova memória',
  'mem.fieldTitle': 'Título',
  'mem.fieldTitleDesc': 'Uma manchete curta e pesquisável do aprendizado.',
  'mem.fieldBody': 'Conteúdo',
  'mem.fieldBodyDesc':
      'O fato E por que importa. Aceita markdown. Evite o que dá para deduzir do código.',
  'mem.fieldKey': 'Key (opcional — identidade estável p/ atualizações)',
  'mem.fieldKeyDesc':
      'Reusar a mesma key substitui a memória (versionada), em vez de duplicar.',
  'mem.kind': 'Tipo',
  'mem.tier': 'Camada',
  'mem.importance': 'Importância',
  'mem.selectOne': 'Selecione uma memória.',
  'mem.created': 'Memória criada.',
  'mem.versionSaved': 'Nova versão salva.',
  'mem.forgetQ': 'Esquecer memória?',
  'mem.deleteQ': 'Apagar permanentemente?',
  'mem.forgetMsg': 'sai do recall, mas é mantida para auditoria.',
  'mem.deleteMsg': 'será APAGADA para sempre (sem auditoria).',
  'mem.forget': 'Esquecer',
  'mem.forgotten': 'Memória esquecida.',
  'mem.deleted': 'Memória apagada.',
  'mem.forgetSoft': 'Esquecer (mantém auditoria)',
  // rules
  'rule.header': 'Regras do projeto (com herança da organização)',
  'rule.new': 'Nova regra',
  'rule.newTitle': 'Nova regra (do projeto)',
  'rule.editTitle': 'Refinar regra (nova versão)',
  'rule.fieldKey': 'Key (slug estável — mesma key = atualiza)',
  'rule.fieldKeyDesc':
      'Identificador estável (ex.: sql-parametrizado). Re-salvar a mesma key refina a regra.',
  'rule.fieldScope': 'Escopo (módulo/pasta/área)',
  'rule.fieldScopeDesc':
      'Onde a regra vale. Vazio = todo o projeto; ou um módulo/pasta específico.',
  'rule.fieldTitle': 'Título',
  'rule.fieldContent': 'Conteúdo',
  'rule.fieldContentDesc':
      'A regra em si, com a justificativa. Aceita markdown.',
  'rule.severity': 'Severidade',
  'rule.required': 'obrigatória',
  'rule.recommended': 'recomendada',
  'rule.priority': 'Prioridade',
  'rule.priorityHint':
      'Menor = mais relevante (1 vem primeiro · 100 por último)',
  'rule.selectOne': 'Selecione uma regra.',
  'rule.created': 'Regra criada.',
  'rule.refined': 'Regra refinada (nova versão).',
  'rule.rerank': 'Re-ranquear regra',
  'rule.adjust': 'Ajustar',
  'rule.prioritySet': 'Prioridade ajustada para',
  'rule.retireQ': 'Aposentar regra?',
  'rule.deleteQ': 'Apagar permanentemente?',
  'rule.retireMsg': 'sai do recall, mas é mantida para auditoria.',
  'rule.deleteMsg': 'será APAGADA para sempre.',
  'rule.retired': 'Regra aposentada.',
  'rule.deleted': 'Regra apagada.',
  'rule.fromProject': 'do projeto',
  'rule.fromOrganization': 'da organização (herdada)',
  'rule.refine': 'Refinar (nova versão)',
  'rule.scopeChip': 'escopo',
  // rfc
  'rfc.header': 'RFCs do projeto (revisão multiagente)',
  'rfc.new': 'Nova RFC',
  'rfc.newTitle': 'Nova RFC',
  'rfc.fieldTitle': 'Título',
  'rfc.fieldTitleDesc': 'Uma manchete curta da spec técnica em revisão.',
  'rfc.fieldType': 'Tipo (perfil de checklist)',
  'rfc.fieldTypeDesc':
      'backend | frontend | fullstack | data | infra | generic.',
  'rfc.fieldSummary': 'Resumo',
  'rfc.fieldSummaryDesc':
      'O substrato executável da versão 1. Aceita markdown. É o que vai para o recall semântico.',
  'rfc.titleRequired': 'O título é obrigatório.',
  'rfc.created': 'RFC aberta.',
  'rfc.selectOne': 'Selecione uma RFC.',
  'rfc.empty':
      'Nenhuma RFC ainda. Crie uma aqui ou deixe os agentes abrirem via oracle_rfc_open.',
  'rfc.filterAll': 'Todas',
  'rfc.filterOpen': 'Abertas',
  'rfc.filterApproved': 'Aprovadas',
  'rfc.round': 'rodada',
  'rfc.readiness': 'Prontidão',
  'rfc.readinessDesc':
      'O gate de conclusão em resumo: bloqueadores verificados + cobertura obrigatória.',
  'rfc.ready': 'pronta',
  'rfc.notReady': 'em revisão',
  'rfc.blockingCriticals': 'bloqueadores',
  'rfc.openMajors': 'majors abertos',
  'rfc.totalComments': 'achados',
  'rfc.requiredCovered': 'obrigatórias cobertas',
  'rfc.summaryTitle': 'Resumo da versão',
  'rfc.sections': 'Seções',
  'rfc.findings': 'Achados',
  'rfc.noFindings': 'Nenhum achado registrado ainda.',
  'rfc.verified': 'verificado',
  'rfc.unverified': 'não verificado',
  'rfc.problem': 'Problema',
  'rfc.solution': 'Solução proposta',
  'rfc.finalize': 'Finalizar',
  'rfc.finalizeQ': 'Finalizar RFC?',
  'rfc.finalizeMsg':
      'passará pelo gate de conclusão (bloqueadores + cobertura) antes de aprovar.',
  'rfc.finalized': 'RFC',
  'rfc.copyPrompt': 'Copiar prompt de revisão',
  'rfc.promptCopied': 'Prompt copiado.',
  'rfc.st.draft': 'rascunho',
  'rfc.st.open_for_comments': 'aberta',
  'rfc.st.in_review': 'em revisão',
  'rfc.st.in_consolidation': 'consolidando',
  'rfc.st.awaiting_human': 'aguarda humano',
  'rfc.st.stalled': 'estagnada',
  'rfc.st.approved': 'aprovada',
  'rfc.st.rejected': 'rejeitada',
  'rfc.st.superseded': 'substituída',
  'rfc.st.obsolete': 'obsoleta',
  // skills
  'skill.header': 'Biblioteca central de skills',
  'skill.headerTip':
      'Uma única fonte para todos os agentes (MCP). "Sincronizar" materializa em ~/.claude/skills para descoberta nativa do Claude Code.',
  'skill.sync': 'Sincronizar p/ disco',
  'skill.syncing': 'Sincronizando…',
  'skill.new': 'Nova skill',
  'skill.newTitle': 'Nova skill',
  'skill.editTitle': 'Editar skill (nova versão)',
  'skill.fieldKey': 'Key (slug estável, kebab-case — vira o nome da pasta)',
  'skill.fieldName': 'Nome',
  'skill.fieldDesc': 'Descrição (o gatilho do recall: o que faz + quando usar)',
  'skill.fieldContent': 'Conteúdo (markdown, estilo SKILL.md)',
  'skill.scope': 'Escopo',
  'skill.scopeGlobal': 'Global (todos os projetos e agentes)',
  'skill.scopeProject': 'Deste projeto',
  'skill.scopeSelectProject': 'Deste projeto (selecione um projeto)',
  'skill.global': 'global',
  'skill.project': 'projeto',
  'skill.organization': 'organização',
  'skill.empty':
      'Nenhuma skill ainda — crie aqui ou deixe os agentes salvarem com oracle_skill_save.',
  'skill.selectOne': 'Selecione uma skill.',
  'skill.created': 'Skill criada.',
  'skill.updated': 'Skill atualizada (nova versão).',
  'skill.retireQ': 'Aposentar skill?',
  'skill.deleteQ': 'Apagar permanentemente?',
  'skill.retireMsg': 'sai da biblioteca, mas é mantida para auditoria.',
  'skill.deleteMsg': 'será APAGADA para sempre.',
  'skill.retired': 'Skill aposentada.',
  'skill.deleted': 'Skill apagada.',
  'skill.synced': 'Sincronizado',
  'skill.syncFail': 'Falha no sync',
  'skill.pruned': 'removidas',
  // sessions
  'sess.selectSession': 'Selecione uma sessão.',
  'sess.tokensIn': 'entrada',
  'sess.tokensOut': 'saída',
  'sess.selectRequest': 'Selecione uma demanda.',
  // search
  'search.hint':
      'Buscar em todo o banco de memória (memórias, regras e skills)…',
  'search.prompt': 'Digite e pressione Enter para buscar em tudo.',
  'search.empty': 'Nada encontrado.',
  'search.memories': 'Memórias',
  'search.rules': 'Regras',
  'search.skills': 'Skills',
  'search.sections': 'Seções (arquitetura)',
  // backup
  'bk.title': 'Backup do banco de memória',
  'bk.explain':
      'Gera um seed .sql portátil com TODOS os dados (embeddings inclusos, snapshot consistente). Restaure em um banco vazio com `oracle_ai restore-db`, ou deixe o `docker compose up` restaurar automaticamente em um volume novo.',
  'bk.target': 'Destino',
  'bk.run': 'Fazer backup agora',
  'bk.running': 'Gerando backup…',
  'bk.done': 'Backup concluído',
  'bk.rows': 'linhas',
  'bk.scheduleNote':
      'Backups agendados (intervalo + retenção) ficam na aba Config — o Studio cuida deles em segundo plano.',
  // settings
  'set.title': 'Configurações',
  'set.daemon': 'Daemon em segundo plano',
  'set.daemonExplain':
      'Com isto ligado, o próprio Studio é o receptor de hooks em http://127.0.0.1:47500/hook — dispensa Docker e o oracle_ai.exe de console. Mantenha o Studio aberto (ele fica na bandeja) e ligue "Iniciar com o Windows" para os hooks estarem sempre no ar. Use uma porta abaixo de 49152 (o Windows reserva a faixa dinâmica acima disso); se estiver ocupada por outro processo, o Studio assume automaticamente quando ele sair.',
  'set.hostToggle': 'Hospedar hooks + manutenção neste app',
  'set.workerToggle': 'Hospedar o Flow Runner (Loop Engineering)',
  'set.workerDesc':
      'Executa os runs enfileirados: lança agentes, cria worktrees e roda os verificadores',
  'set.workerParallel': 'Processos em paralelo',
  'set.workerParallelDesc':
      'Quantos runs o worker executa AO MESMO TEMPO (cada um lança seus próprios agentes — mais paralelismo = mais CPU/API em uso)',
  'set.autostart': 'Iniciar com o Windows',
  'set.autostartSub':
      'Abre o Studio (na bandeja) no login — hooks e backups sempre ativos.',
  'set.autostartOn': 'O Studio iniciará com o Windows.',
  'set.autostartOff': 'Autostart desativado.',
  'set.language': 'Idioma',
  'set.schedTitle': 'Backup agendado',
  'set.schedExplain':
      'Snapshots .sql com carimbo de data em backups/ (com retenção). O seed para commit/docker continua manual, na aba Backup.',
  'set.schedToggle': 'Fazer backup automaticamente',
  'set.every': 'A cada',
  'set.hours6': '6 horas',
  'set.hours12': '12 horas',
  'set.hours24': '24 horas',
  'set.hours48': '48 horas',
  'set.keepLast': 'Manter últimos',
  'set.runNow': 'Executar agora',
  'set.runningNow': 'Executando…',
  'set.lastBackup': 'Último backup',
  'set.agents': 'Integração de agentes',
  'set.agentsDesc':
      'Escolha o agente e copie a configuração de MCP e de hooks dele. O protocolo (no fim) é o mesmo para todos.',
  'set.targetsTitle': 'Onde configurar cada agente',
  'set.mcpTitle': '.mcp.json (raiz do projeto do agente)',
  'set.hooksTitle': 'settings.json do Claude Code (bloco "hooks")',
  'set.promptTitle': 'Prompt para o agente (CLAUDE.md / AGENTS.md)',
  // per-agent tabs
  'ag.mcp': 'Servidor MCP',
  'ag.cli': 'Atalho CLI',
  'ag.hooks': 'Hooks (captura automática)',
  'ag.hooksHttp':
      'Este agente faz POST direto no receptor de hooks — nenhuma ponte necessária.',
  'ag.hooksBridge':
      'Os hooks deste agente rodam um comando: usamos o "oracle_ai forward-hook" para repassar o evento ao receptor. Precisa do Oracle Studio (ou do daemon) hospedando o receptor. Captura funciona; o recall automático varia por agente — na dúvida, use as ferramentas MCP.',
  'ag.hooksNone':
      'Este agente não tem hooks de ciclo de vida. Use as ferramentas MCP + o protocolo abaixo para recuperar e registrar manualmente.',
  'ag.instr': 'Arquivo de instruções',
  'ag.instrBody': 'Cole o protocolo (no fim desta seção) em:',
  'ag.badgeHttp': 'Hooks nativos (HTTP)',
  'ag.badgeBridge': 'Hooks via ponte',
  'ag.badgeNone': 'Sem hooks',
  'set.promptDesc':
      'Cole este protocolo no arquivo de instruções do seu agente para ensiná-lo a usar a Oracle: '
      'recuperar antes de re-deduzir, registrar o que é durável e passar adiante o que ficou aberto.',
  'set.copied': 'copiado para a área de transferência.',
  'set.copy': 'Copiar',
  'set.envSave': 'Salvar .env',
  'set.envSaved': 'Salvo. Reinicie o Studio (e o MCP) para aplicar.',
  'set.envMissing': 'Nenhum .env conectado — crie um na raiz do projeto.',
  'set.envNotFound': '(não encontrado)',
  'set.subtitle':
      'Conexão, daemon, backups e integração — tudo do Oracle em um lugar.',
  'set.langDesc': 'Idioma da interface do Studio.',
  'set.daemonStatus': 'Status do receptor de hooks',
  'set.online': 'Ativo',
  'set.offline': 'Desligado',
  'set.portBusy': 'Porta ocupada',
  // env form
  'env.title': 'Conexão e ambiente (.env)',
  'env.desc':
      'Estas configurações valem para o Studio, o MCP dos agentes e o daemon. Salvar atualiza o arquivo .env com segurança (backup .bak automático, comentários preservados). Reinicie o Studio e os agentes para aplicar.',
  'env.db': 'Banco de dados PostgreSQL',
  'env.dbDesc':
      'Onde a memória vive. Use o banco criado na instalação ou aponte para outro.',
  'env.host': 'Host',
  'env.port': 'Porta',
  'env.user': 'Usuário',
  'env.password': 'Senha',
  'env.dbName': 'Nome do banco',
  'env.embed': 'Embeddings (busca semântica)',
  'env.embedDesc':
      '"local" funciona offline e sem custo. Provedores de API (Gemini/OpenAI/Voyage) dão mais qualidade — após trocar, rode o re-embed na manutenção.',
  'env.provider': 'Provedor',
  'env.apiKey': 'API key do provedor',
  'env.server': 'Servidor local (hooks)',
  'env.serverDesc':
      'Endpoint HTTP que recebe os eventos dos agentes (sessões, mensagens). Loopback por padrão.',
  'env.httpHost': 'Host HTTP',
  'env.httpPort': 'Porta HTTP',
  'env.token': 'Token dos hooks',
  'env.tokenDesc':
      'Protege o endpoint /hook. Opcional em loopback; obrigatório se expor a porta. Ao mudar, atualize também o snippet de hooks nos agentes.',
  'env.generate': 'Gerar',
  'env.maint': 'Manutenção e métricas',
  'env.interval': 'Manutenção a cada (minutos)',
  'env.intervalDesc':
      '0 desliga a varredura periódica (decay + dedup de memórias).',
  'env.metricsLabel': 'Label de métricas (experimento)',
  'env.save': 'Salvar configurações',
  'env.saved': 'Configurações salvas no .env. Reinicie o Studio para aplicar.',
  'env.advanced': 'Avançado: editar o .env manualmente',
  // backup folder
  'bk.folder': 'Pasta de backups',
  'bk.folderDesc':
      'Onde os backups (manuais e agendados) são gravados. Padrão: Documentos › Oracle AI › backups.',
  'bk.change': 'Alterar…',
  'bk.reset': 'Usar padrão',
  'bk.openFolder': 'Abrir pasta',
  'bk.subtitle':
      'Um backup é um arquivo .sql portátil com TODA a memória (embeddings inclusos). Guarde, versione ou leve para outra máquina.',
  'bk.what': 'O que o backup contém?',
  'bk.whatDesc':
      'Todas as organizações, projetos, memórias, regras, skills, sessões e métricas — com snapshot consistente mesmo com agentes trabalhando. A restauração só acontece em banco vazio (nunca sobrescreve).',
};

const _en = <String, String>{
  'app.connecting': 'Connecting to the memory bank…',
  'app.connectFailTitle': 'Could not connect',
  'app.retry': 'Try again',
  'app.noEnv':
      'No .env found — using defaults (localhost:5432). Set ORACLE_ENV_PATH or place a .env at the project root.',
  'app.config': 'Configuration',
  'records.search': 'Search records…',
  'records.clearSearch': 'Clear search',
  'records.result': 'result',
  'records.results': 'results',
  'records.all': 'All',
  'records.noMatch': 'No records match the filters',
  'records.noMatchHint': 'Try adjusting the search or removing a filter.',
  'sess.requests': 'Requests',
  'sess.messages': 'Messages',
  'hist.recordUnavailable': 'Record unavailable',
  'hist.recordUnavailableHint':
      'The original record was removed and this older history entry stored only its identifier.',
  'nav.groupOverview': 'Overview',
  'nav.groupKnowledge': 'Knowledge',
  'nav.groupActivity': 'Activity',
  'nav.groupSystem': 'System',
  'nav.dashboard': 'Dashboard',
  'nav.dashboardHint': 'Project summary and whole-bank totals',
  'nav.search': 'Search',
  'nav.searchHint': 'Hybrid search across memories, rules and skills',
  'nav.memories': 'Memories',
  'nav.memoriesHint': "The project's consolidated learnings",
  'nav.rules': 'Rules',
  'nav.rulesHint': 'Development rules (severity and priority)',
  'nav.rfcs': 'RFCs',
  'nav.rfcsHint': 'Technical specs in multi-agent review (termination gate)',
  'nav.skills': 'Skills',
  'nav.skillsHint': 'Skill library shared across agents',
  'nav.modules': 'Modules',
  'nav.modulesHint': 'Project subdivisions (service, layer, package)',
  // Loop Engineering
  'nav.groupLoop': 'Loop Engineering',
  'nav.tasks': 'Tasks',
  'nav.tasksHint': 'Development task backlog',
  'nav.flows': 'Processes',
  'nav.flowsHint': 'Multi-agent dev flows (steps = loops)',
  'nav.runs': 'Runs',
  'nav.runsHint': 'Monitor process runs',
  'flows.header': 'Processes',
  'flows.new': 'New process',
  'flows.newTitle': 'New process',
  'flows.template': 'Template',
  'flows.empty': 'No processes yet — create one from a template.',
  'flows.selectOne': 'Select a process',
  'flows.saved': 'Process saved.',
  'flows.fKey': 'Key',
  'flows.fKeyDesc':
      'Stable identity — re-saving the same key creates a new version',
  'flows.fName': 'Name',
  'flows.fNameDesc': 'Human-readable process name',
  'flows.fDesc': 'Description',
  'flows.fOrchestrator': 'Orchestrator',
  'flows.fBudget': 'Token budget (max)',
  'flows.fBudgetDesc': 'Optional — stalls the run when exceeded',
  'flows.keyRequired': 'Key is required',
  'flows.nameRequired': 'Name is required',
  'flows.stepKeyRequired': 'Every step needs a key',
  'flows.steps': 'Steps (each step is a loop)',
  'flows.stepsShort': 'steps',
  'flows.edges': 'Edges',
  'flows.edgesHint':
      'No edges = automatic linear chain (success). Add to branch/loop (verdict/failure).',
  'flows.noEdges': 'No edges.',
  'flows.add': 'Add',
  'flows.step': 'Step',
  'flows.entry': 'Entry',
  'flows.maxIter': 'max',
  'flows.verifier': 'Verifier',
  'flows.fStepKey': 'Key',
  'flows.fStepName': 'Name',
  'flows.fKind': 'Kind',
  'flows.fAgent': 'Agent',
  'flows.fRole': 'Role',
  'flows.fMaxIter': 'Max iterations',
  'flows.fExit': 'Verification commands',
  'flows.fExitDesc': 'Run OUTSIDE the agent; comma-separated',
  'flows.fPrompt': 'Prompt',
  'flows.fCommand': 'Command',
  'flows.fOnFail': 'On fail',
  'flows.from': 'From',
  'flows.to': 'To',
  'flows.condition': 'Condition',
  'flows.verdict': 'Verdict',
  // n8n-style editor
  'flows.editorNew': 'New process',
  'flows.editorEdit': 'Edit process',
  'flows.saveProcess': 'Save process',
  'flows.canvas': 'Process steps',
  'flows.canvasHint':
      'Scroll to navigate · Ctrl + scroll to zoom · middle button or Space + drag to pan · double-click a line to edit.',
  'flows.expandField': 'Open expanded editor',
  'flows.expandedEditor': 'Text editor',
  'flows.organize': 'Auto-organize',
  'flows.fitView': 'Fit process to screen',
  'flows.zoomIn': 'Zoom in',
  'flows.zoomOut': 'Zoom out',
  'flows.snapGrid': 'Snap nodes to grid',
  'flows.duplicate': 'Duplicate step',
  'flows.removeConnections': 'Remove connections',
  'flows.secIdentity': 'Identity',
  'flows.secProcess': 'General process details',
  'flows.secAgent': 'Agent',
  'flows.secExecution': 'Execution',
  'flows.addSkill': 'Add skill',
  'flows.pickSkills': 'Skills registered in Oracle',
  'flows.noRegisteredSkills':
      'No skills registered in this scope — register one in the Skills tab.',
  'flows.searchSkill': 'Filter by name, key or description…',
  // agent diagnostics
  'flows.health.checking': 'Checking the agent…',
  'flows.health.ready': 'Ready — CLI, MCP and capture working',
  'flows.health.warn': 'Runs — but with warnings (capture/hooks or sandbox)',
  'flows.health.fail': 'Will NOT run — fix before running',
  'flows.health.details': 'see details',
  'flows.health.title': 'Agent diagnostics',
  'flows.health.cli': 'CLI available',
  'flows.health.mcp': 'Oracle MCP configured',
  'flows.health.hooks': 'Hooks configured (capture)',
  'flows.health.receiver': 'Hook receiver reachable',
  'flows.health.cliFix':
      'Install the agent CLI or configure its executable path.',
  'flows.health.mcpFix': 'Configure the MCP in Settings → Agent integration.',
  'flows.health.hooksFix': 'Add the hooks in Settings → Agent integration.',
  'flows.health.receiverFix': 'Turn on "Host hooks" in Settings (daemon).',
  'flows.health.sandbox': 'Agent sandbox (shell)',
  'flows.health.sandboxFix':
      'Codex resolves pwsh.exe through the Microsoft Store alias (WindowsApps), '
      'which its sandbox cannot execute ("access denied"). On Windows, WRITE '
      'steps already run without the OS sandbox (unaffected); this hits '
      'read-only steps and interactive Codex use. Fix: install PowerShell 7 '
      'outside the Store — winget install --id Microsoft.PowerShell --scope '
      'machine — or disable the alias in Windows Settings → Apps → App '
      'execution aliases.',
  'flows.health.smoke': 'Run real test',
  'flows.health.smokeRunning': 'Testing… (may take minutes)',
  'flows.health.smokeOk': 'Real test: the agent responded',
  'flows.health.smokeFail': 'Real test: failed',
  'flows.health.recheck': 'Re-check',
  // presets (name, description and the step PROMPT)
  'flows.preset.dev': 'Implementation',
  'flows.presetDesc.dev': 'Agent that implements the task in code',
  'flows.presetPrompt.dev':
      'Implement the task according to the run plan. Commit at the end.',
  'flows.preset.review': 'Code review',
  'flows.presetDesc.review': "Agent that reviews and fixes the branch's diff",
  'flows.presetPrompt.review':
      "Review the branch's diff: correctness, simplicity and adherence to the project rules. "
      'Fix what you find and record a summary of the findings on the blackboard.',
  'flows.preset.security': 'Security',
  'flows.presetDesc.security': 'Agent focused on vulnerabilities in the diff',
  'flows.presetPrompt.security':
      "Analyze the branch's diff for vulnerabilities and bad security practices; fix them and "
      'record the findings on the blackboard.',
  'flows.preset.tests': 'Tests',
  'flows.presetDesc.tests': 'Agent that covers the change with tests',
  'flows.presetPrompt.tests':
      'Write/update tests for the change and make sure the suite passes.',
  'flows.preset.docs': 'Documentation',
  'flows.presetDesc.docs': 'Agent that updates the documentation',
  'flows.presetPrompt.docs':
      "Update the project documentation based on the branch's diff.",
  'flows.preset.pr': 'Pull request',
  'flows.presetDesc.pr': 'Agent that opens the branch PR',
  'flows.presetPrompt.pr':
      "Open the branch's pull request and record the URL as an artifact (kind \"pr\").",
  // template
  'flows.tplName': 'Full feature',
  'flows.tplPlanName': 'Plan',
  'flows.tplPlanPrompt':
      'Analyze the task, write an implementation plan to the blackboard (key "plan") and an '
      'objective brief for each following step.',
  'flows.tplDevName': 'Implement',
  'flows.tplEdgeContinuar':
      'While there are still open findings: another review round',
  'flows.tplEdgeConcluir':
      'When there are no blocking or new findings left: proceed to implementation',
  'flows.tplEdgeLimite':
      'When the round limit is reached: stop and bring in a human',
  'flows.tplEdgeAprovado': 'When ALL tests pass: proceed to documentation',
  'flows.tplEdgeReprovado':
      'When any test fails: go back to implementation to fix',
  'flows.tplTestName': 'Tests passed?',
  'flows.tplTestPrompt':
      'Run the project test suite in the workspace (e.g. dart test) and evaluate the result. '
      'If ALL tests pass, write the verdict "aprovado"; if any test fails, write '
      '"reprovado" and record in your report which tests failed and why. '
      'Do NOT fix anything in this step — only evaluate and decide the route.',
  'flows.tplDocsName': 'Document',
  'flows.tplPrName': 'Pull request',
  'flows.tplGateName': 'Human approval',
  'flows.tplRfcName': 'Create RFC',
  'flows.tplReviewName': 'Review RFC',
  'flows.tplConsName': 'Consolidate & plan',
  'flows.tplRoundsName': 'Rounds',
  'flows.fMaxRounds': 'Max rounds',
  'flows.fMaxRoundsDesc':
      'How many times the gate may send the flow back to review; after that it routes via "limite"',
  'flows.keyLocked':
      'The key is the process identity — saving creates a new version of the SAME key; that is why it cannot change while editing',
  'g.kindUse.rfc_consolidate':
      'Use after review: resolves findings, revises the RFC and writes the plan.',
  'g.kindUse.rfc_gate':
      'Use after consolidation: no AI, emits the continuar/concluir/limite verdict — and each verdict is a connection you point wherever you want (e.g. limite → human approval or another path).',
  // worker status (daemon)
  'set.workerSt.on': 'running',
  'set.workerSt.off': 'off',
  'set.workerSt.stopping': 'stopping…',
  // guide (in-app documentation)
  'flows.guide': 'How it works',
  'flows.guideTitle': 'Loop Engineering — process guide',
  'flows.guideMd': '''
# How processes work (Loop Engineering)

A **process** is a development flow drawn on the canvas: each **step is a loop** executed by a coding agent (Claude Code, Codex, Gemini…), and the **connections** define the order. You create a **task**, run it with a process, and the **Flow Runner** drives everything automatically — launching the agents, verifying the work and advancing the flow.

## Prerequisites (nothing executes without these)

1. **Turn on the Flow Runner** in *Settings → Host the Flow Runner* (or via the banner on the Runs tab). It is what picks runs from the queue.
2. **Agents ready**: when you select a step agent, the **diagnostics** show whether the CLI is installed and the Oracle MCP is configured — use **"Run real test"** to prove the agent responds. Red = it will not run.
3. The project needs a **repository** (the run creates a branch/worktree in it).

## The execution cycle

1. You create the task and click **Run** with a process → the run enters the **queue**.
2. The Flow Runner claims the run, creates an isolated git **branch + worktree** and starts at the **entry step** (the orchestrator, when present).
3. For each agent step: the runner builds a **complete prompt** (task, step instructions, project rules, skills, the *blackboard* with what earlier steps recorded, artifacts and exit criteria) and launches the agent **headless** in the worktree.
4. When it finishes, the runner executes the **verification commands OUTSIDE the agent** (the agent cannot self-approve). Failed → a new iteration of the SAME step with the error attached to the prompt (up to max iterations). Passed → follows the connections.
5. **Human approval** parks the run until you approve it on the Runs tab. When it completes, the task becomes *Done*.

## Step types

- **Orchestrator** — only ONE may exist, and it is the flow **start**. Use it to plan and decide routes (it writes `verdict` to the blackboard).
- **Agent** — the general case: implement, review, document… (use the ready-made presets in the picker).
- **RFC review** — evidence-grounded multi-agent review.
- **Command** — deterministic, no AI (build, test, deploy).
- **Human approval** — parks until a human decides.

## Configuring a step (fields)

- **Agent / Model** — which CLI executes and, optionally, which model (e.g. `opus`).
- **Role** — the persona (implementer, reviewer, security…). Goes into the prompt.
- **Prompt** — the step-specific instructions. Be objective: the runner already injects task, rules, blackboard and criteria automatically.
- **Skills** — Oracle library skills the agent loads before working.
- **Verification commands** — the objective proof (e.g. `dart analyze, dart test`). They are the heart of the loop: without them the step passes on the agent report alone.
- **Max iterations** — how many attempts the step has to pass verification.
- **Timeout** — empty = **no limit** (agents may run for hours). Use only as a safety valve.
- **On fail** — iterations exhausted: *Wait for human* (recommended), *Fail the run* or *Continue anyway*.

## Connections

- Drag a node **→** dot onto another node. Default: **Success** (follows when verification passes).
- **Failure** — alternative route when the step exhausts its iterations.
- **Verdict** — route chosen by the orchestrator (it writes `verdict` to the blackboard; the connection fires when the value matches). E.g. `approved` proceeds, `rejected` goes back to planning.
- **Always** — follows regardless of the result.
- **Branches**: one node can feed several (they execute one after another) and several can converge into one (the *join* waits for all). **Looping back** to an earlier step re-executes that stretch.

## Best practices for a good loop

- **Small steps with objective verification** — a loop without a trustworthy verifier does not converge.
- **One writer at a time** — concentrate code writing in one step; reviewers record findings on the blackboard.
- **Use the orchestrator to decide**, not to work — planning and verdicts.
- **Set a token budget** on the process for long runs.
- **Watch the Runs tab** — each iteration shows the sent prompt, the agent report and the verification output.
''',
  'set.hooksSt.off': 'off',
  'set.hooksSt.on': 'running on',
  'set.hooksSt.reserved':
      'port reserved by Windows — pick a port below 49152 in the settings',
  'set.hooksSt.busy':
      'port busy — another process serves the hooks; I take over automatically when it exits',
  'flows.connect': 'Connect to another step',
  'flows.connectingFrom': 'Connecting from',
  'flows.connectingHint': 'click the target node (or X to cancel)',
  'flows.startBadge': 'START',
  'flows.setEntry': 'Flow entry step',
  'flows.fModel': 'Model (optional)',
  'flows.fModelDesc':
      'Alias the agent CLI accepts (e.g. opus) — empty uses the default',
  'flows.fSkills': 'Oracle skills',
  'flows.fSkillsDesc':
      'Oracle library skills the agent loads before working — pick from the registered ones',
  'flows.fTimeoutDesc': 'Empty = no limit (agents may run for hours)',
  'flows.presets': 'Ready-made presets (agent steps)',
  'flows.deleteConnection': 'Remove connection',
  'flows.onlyOneOrchestrator':
      'Only ONE orchestrator is allowed — it starts the flow',
  'flows.verdictDesc':
      'Value the SOURCE node\'s agent writes to the blackboard (key "verdict") to take this route — works on any node, not only decision',
  'flows.edgeInstruction': 'When to take this route (instruction)',
  'flows.edgeInstructionDesc':
      'Goes into the source node agent\'s prompt next to the verdict — it evaluates this instruction and picks the route. E.g. "when the RFC has no open findings left".',
  'flows.edgeInstructionHint': 'e.g. when all tests pass',
  'flows.editConnection': 'Edit connection',
  'flows.modelSuggestions': 'Model suggestions',
  'flows.fModelDesc.claude-code':
      'Alias (fable, opus, sonnet, haiku) or full name (e.g. claude-fable-5). Empty = CLI default. Any valid model can be typed.',
  'flows.fModelDesc.codex':
      'Model id (e.g. gpt-5.5, gpt-5.4-mini, gpt-5.3-codex). Empty = config.toml default. Any valid id can be typed.',
  'flows.fModelDesc.gemini':
      'Model id (e.g. gemini-3-pro-preview). Empty = the CLI\'s auto routing. Any valid id can be typed.',
  'flows.fModelDesc.cursor':
      'Model id — list valid ones with "cursor-agent --list-models". Empty = Cursor default.',
  'flows.fModelDesc.copilot':
      'Model id (e.g. claude-sonnet-4.5). Empty = Copilot default.',
  'flows.fEffort': 'Reasoning (effort)',
  'flows.fEffortDesc.claude-code':
      'Becomes Claude Code\'s --effort flag. More effort = more quality and more tokens; "max" only for the hardest steps.',
  'flows.fEffortDesc.codex':
      'Becomes Codex\'s -c model_reasoning_effort (xhigh is model-dependent). More effort = more quality and more tokens.',
  'floweffort.minimal': 'Minimal',
  'floweffort.low': 'Low',
  'floweffort.medium': 'Medium',
  'floweffort.high': 'High',
  'floweffort.xhigh': 'Extra-high',
  'floweffort.max': 'Max',
  'flows.insertHere': 'Insert step here',
  'flows.addStep': 'Add step',
  'flows.pickKind': 'What kind of step?',
  'flows.connections': 'Connections',
  'flows.connectionsHint':
      'By default each step connects to the next (success). Customize to branch or loop back (verdict/failure).',
  'flows.linearReset': 'Back to linear chain',
  'flows.addConnection': 'Add connection',
  'flows.moveLeft': 'Move left',
  'flows.moveRight': 'Move right',
  'flows.dupStepKey': 'Duplicate step keys',
  'flows.edit': 'Edit',
  'flows.noCommand': 'no command',
  'flows.fStepKeyDesc': 'Short unique identifier of the step',
  'flows.fRoleDesc': 'The agent persona for this step',
  'flows.fPromptDesc': 'Step-specific instructions for the agent',
  'flows.fCommandDesc': 'Command the runner executes (no AI)',
  'flows.fTimeout': 'Timeout (min)',
  'flows.fTokenBudget': 'Step token budget',
  'flows.fTokenBudgetDesc': 'Empty = no step-specific limit',
  'flows.fVerifierTimeout': 'Verifier timeout (min)',
  'flows.fVerifierTimeoutDesc': 'Separate limit for each verification command',
  'flows.fOutputSchema': 'Output contract (JSON Schema)',
  'flows.fOutputSchemaDesc':
      'Validates the outputs object reported by the agent',
  'flows.fPermissions': 'Step permissions',
  'flows.fPermissionsDesc': 'JSON: workspace read/write, shell and mcp',
  // friendly enum labels
  'flowkind.agent': 'Agent',
  'flowkind.orchestrator': 'Orchestrator',
  'flowkind.decision': 'Decision',
  'flowkindDesc.decision':
      'An agent evaluates a criterion (test, check…) and picks between 2+ paths by writing "verdict"',
  'flowkind.subflow': 'Sub-process',
  'flowkindDesc.subflow':
      'Executes ANOTHER process inside this one (like n8n): same workspace, shared blackboard',
  'flowkind.join': 'Join',
  'flowkindDesc.join':
      'Waits for every active incoming branch and continues once, without running an agent',
  'flows.secSubflow': 'Sub-process',
  'flows.fSubflow': 'Process to execute',
  'flows.fSubflowNone': '— select a process —',
  'flows.fSubflowDesc':
      'The runner executes the chosen process as a CHILD run, in this run\'s workspace; the '
      'blackboard flows down to the child and merges back when it completes. Max 3 levels.',
  'flows.noSubflow': 'no target process',
  'flows.subflowRequired':
      'Every Sub-process step needs a selected target process',
  'flows.unsupportedAgent':
      'The selected agent has no compatible automatic executor',
  'flows.invalidMaxIterations': 'Max iterations must be at least 1',
  'flows.invalidTimeout':
      'Timeout must be empty or a non-negative whole number',
  'flows.commandRequired': 'A Command step requires a command',
  'flows.invalidMaxRounds': 'Max rounds must be at least 1',
  'flows.joinIncomingRequired': 'A Join must receive at least two branches',
  'flows.decisionVerdictsRequired':
      'A Decision requires at least two verdict connections',
  'flows.invalidVerdictValues':
      'Decision verdicts must be filled in and cannot be duplicated',
  'flows.fTags': 'Tags (agent commands)',
  'flows.fTagsDesc':
      'Comma-separated; they become /tag lines at the TOP of the prompt — in Claude Code, '
      '"review" triggers the /review command. Leave empty if not needed.',
  'flowkind.rfc_create': 'RFC creation',
  'flowkind.rfc_review': 'RFC review',
  'flowkind.command': 'Command',
  'flowkind.human_gate': 'Human approval',
  'flowkindDesc.agent':
      'A coding agent loops on the step until verification passes',
  'flowkindDesc.orchestrator':
      "The process's orchestrator agent plans or decides the route",
  'flowkind.rfc_consolidate': 'RFC consolidation',
  'flowkind.rfc_gate': 'RFC rounds',
  'flowkindDesc.rfc_create':
      "An agent PUBLISHES the task's spec as a sectioned RFC (oracle_rfc_open)",
  'flowkindDesc.rfc_review':
      'Evidence-grounded multi-agent review (RFC engine)',
  'flowkindDesc.rfc_consolidate':
      "Agent that resolves the round's findings, REVISES the RFC and writes the implementation plan",
  'flowkindDesc.rfc_gate':
      'Deterministic gate (no AI): decides continuar (new round), concluir or limite',
  'flowkindDesc.command': 'Deterministic command (build, test, deploy) — no AI',
  'flowkindDesc.human_gate':
      'Parks the run until a human approves in the Studio',
  'runst.queued': 'Queued',
  'runst.running': 'Running',
  'runst.awaiting_human': 'Awaiting approval',
  'runst.paused': 'Paused',
  'runst.stalled': 'Stalled',
  'runst.completed': 'Completed',
  'runst.failed': 'Failed',
  'runst.cancelled': 'Cancelled',
  'taskst.backlog': 'Backlog',
  'taskst.ready': 'Ready',
  'taskst.running': 'Running',
  'taskst.blocked': 'Blocked',
  'taskst.done': 'Done',
  'taskst.cancelled': 'Cancelled',
  'stepst.running': 'Running',
  'stepst.verifying': 'Verifying',
  'stepst.passed': 'Passed',
  'stepst.failed': 'Failed',
  'stepst.skipped': 'Skipped',
  'stepst.parked': 'Awaiting human',
  'stepst.abandoned': 'Abandoned',
  'flowcond.success': 'Success',
  'flowcond.failure': 'Failure',
  'flowcond.verdict': 'Verdict',
  'flowcond.always': 'Always',
  'flowfail.park': 'Wait for human',
  'flowfail.halt': 'Fail the run',
  'flowfail.continue': 'Continue anyway',
  'flowev.state': 'State',
  'flowev.step_start': 'Step start',
  'flowev.step_end': 'Step end',
  'flowev.verifier': 'Verifier',
  'flowev.iteration': 'Iteration',
  'flowev.decision': 'Decision',
  'flowev.gate': 'Approval',
  'flowev.budget': 'Budget',
  'flowev.error': 'Error',
  'flowev.info': 'Info',
  'tasks.header': 'Tasks',
  'tasks.new': 'New task',
  'tasks.newTitle': 'New task',
  'tasks.empty': 'No tasks in the backlog.',
  'tasks.created': 'Task created.',
  'tasks.run': 'Run',
  'tasks.completed': 'Completed',
  'tasks.terminalNoRerun':
      'This task is closed and cannot be run again. Create a new task for another request.',
  'tasks.alreadyRunning': 'This task already has an execution in progress.',
  'tasks.enqueued': 'Run enqueued',
  'tasks.noFlows': 'Create a process before running.',
  'tasks.pickFlow': 'Pick the process',
  'tasks.fTitle': 'Title',
  'tasks.fDesc': 'Description',
  'tasks.fPriority': 'Priority',
  'tasks.fPriorityDesc': '0..100 (default 50)',
  'tasks.titleRequired': 'Title is required',
  'runs.header': 'Runs',
  'runs.refresh': 'Refresh',
  'runs.allRuns': 'All',
  'runs.activeRuns': 'Active',
  'runs.noActiveRuns': 'No active runs.',
  'runs.graphHint': 'Drag to move · Ctrl + scroll to zoom',
  'runs.sectionExecution': 'Execution',
  'runs.sectionSessions': 'Sessions',
  'runs.openSession': 'Open session',
  'runs.sessionPrompt': 'Request sent to the agent',
  'runs.sessionAnswer': 'Activity and response',
  'runs.noSessionsYet': 'No session has been linked to this execution.',
  'runs.legacySessionMissing':
      'This older iteration has no linked session. New executions create sessions as a requirement.',
  'runs.stepsCompleted': 'steps completed',
  'runs.now': 'Now',
  'runs.withIssue': 'need attention',
  'runs.sectionData': 'Data',
  'runs.sectionEvents': 'Events',
  'runs.noDataYet': 'The process has not produced data or artifacts yet.',
  'runs.noEventsYet': 'No events were recorded for this run.',
  'runs.zoomIn': 'Zoom in',
  'runs.zoomOut': 'Zoom out',
  'runs.resetView': 'Reset view',
  'runs.empty': 'No runs yet.',
  'runs.selectOne': 'Select a run',
  'runs.run': 'Run',
  'runs.approve': 'Approve',
  'runs.reject': 'Reject',
  'runs.rejectQ': 'Reject the run?',
  'runs.rejectMsg': 'The run will be marked failed.',
  'runs.approved': 'Approved — the run resumes.',
  'runs.rejected': 'Run rejected.',
  'runs.pause': 'Pause',
  'runs.resume': 'Resume',
  'runs.cancel': 'Cancel',
  'runs.ctl.pause': 'Run paused.',
  'runs.ctl.resume': 'Run resumed.',
  'runs.ctl.cancel': 'Run cancelled.',
  'runs.steps': 'Steps',
  'runs.noSteps': 'No steps executed yet.',
  'runs.queuedHint':
      'The run is queued waiting for the Flow Runner to claim it. If nothing happens, check the banner above.',
  'runs.workerOffBody':
      'The Flow Runner is OFF — runs sit in the queue and no step executes. Turn it on to start.',
  'runs.workerEnable': 'Turn on now',
  'runs.promptSent': 'Prompt sent to the agent',
  'runs.agentReport': 'Agent report',
  'runs.verifierOut': 'Verification (runner)',
  'runs.running': 'Running — logs appear when the iteration finishes.',
  'runs.copy': 'Copy',
  'runs.copied': 'Copied.',
  'runs.pending': 'Pending',
  'runs.iteration': 'Iteration',
  'runs.iterations': 'iterations',
  'runs.sessionLinked': 'session captured',
  'runs.interactions': 'interactions',
  'runs.contextContinued': 'Agent context continued',
  'runs.nativeSession': 'Native session',
  'runs.outputs': 'Outputs',
  'runs.filesTouched': 'Files touched',
  'runs.openQuestions': 'Open questions',
  'runs.verifPassed': 'Verification passed',
  'runs.verifFailed': 'Verification failed',
  'runs.technical': 'Technical details',
  'runs.launchCmd': 'Command',
  'runs.agentOk': 'Agent completed',
  'runs.agentFail': 'Agent FAILED',
  'flows.modelDefault': 'Agent default',
  // visual guide
  'g.heroTitle': 'Processes, tasks and runs',
  'g.heroSub':
      'You design the process once; Oracle runs as many tasks as you want with it — with real agents, objective verification and you in control.',
  'g.cProcess': 'Process',
  'g.cProcessBody':
      'The flow drawn on the canvas: each step is a loop executed by an agent; connections define the order. Versioned by its key.',
  'g.cTask': 'Task',
  'g.cTaskBody':
      'The development demand (what to do). Lives in the backlog and is the trigger: Run = task + process.',
  'g.cRun': 'Run',
  'g.cRunBody':
      'One round of the process for a task. The Flow Runner drives everything and you watch live, step by step.',
  'g.cycleTitle': 'The cycle in 4 steps',
  'g.cycle1': 'Create the process',
  'g.cycle1Body':
      'On the canvas: add steps, connect them, configure agents and verifications.',
  'g.cycle2': 'Create the task',
  'g.cycle2Body':
      'Title + a clear description of what must be done — it becomes the heart of the prompt.',
  'g.cycle3': 'Run it',
  'g.cycle3Body':
      'Pick the process. The run enters the queue and the Flow Runner takes over.',
  'g.cycle4': 'Watch and approve',
  'g.cycle4Body':
      'On the Runs tab: per-step logs, human gates and controls (pause/cancel).',
  'g.exampleTitle': 'Example: the "Full feature" process',
  'g.exampleNote':
      'The orchestrator (START) plans; dev implements until verification passes; docs and PR complete; human approval closes. With a Verdict connection you make "rejected" go back to planning.',
  'g.hoodTitle': 'Under the hood (how the runner executes)',
  'g.hood1': 'Queue',
  'g.hood1Body':
      'Run enqueues the run (status "Queued"). Nothing runs while the Flow Runner is off.',
  'g.hood2': 'Claim',
  'g.hood2Body':
      'The Flow Runner claims the oldest queued run with a database lock — two workers never grab the same run.',
  'g.hood3': 'Branch + worktree',
  'g.hood3Body':
      'An isolated git branch (flow/…) and a worktree are created in the project repository — all the work happens there.',
  'g.hood4': 'Prompt composition',
  'g.hood4Body':
      'For each agent step, the runner builds a complete prompt with:',
  'g.chipTask': 'task',
  'g.chipRules': 'project rules',
  'g.chipSkills': 'skills',
  'g.chipBlackboard': 'blackboard',
  'g.chipReports': 'prior reports',
  'g.chipCriteria': 'exit criteria',
  'g.hood5': 'Agent launch',
  'g.hood5Body':
      'The agent CLI runs headless in the worktree, with the Oracle MCP available (step_context, context_put, artifact_add, step_report).',
  'g.hood6': 'Verification outside the agent',
  'g.hood6Body':
      'The runner executes the verification commands in the worktree. The agent NEVER self-approves. Failed → a new iteration with the error in the prompt.',
  'g.hood7': 'Advancing through the graph',
  'g.hood7Body':
      'Passed → follows the connections (success/verdict). Branches execute one after another; joins wait; loop-backs re-execute.',
  'g.hood8': 'Completion',
  'g.hood8Body':
      'Gates wait for your approval. At the end the task becomes Done and everything is recorded: sessions, tokens, artifacts and the timeline.',
  'g.kindsTitle': 'Step types',
  'g.kindsNote':
      'Only ONE orchestrator may exist — and it is always the flow START.',
  'g.decisionNote':
      'How to wire it: create 2+ connections leaving the node with the "Verdict" condition (e.g. aprovado, reprovado). '
      'The agent prompt lists those values automatically; it writes one of them and the runner follows the matching connection.',
  'g.fieldsTitle': 'Step fields',
  'g.fAgent':
      'Which CLI executes the step; the model is free-typed (with suggestions) and the reasoning effort becomes each CLI\'s own flag (--effort on Claude Code, model_reasoning_effort on Codex).',
  'g.fPrompt':
      'The step-specific instructions. Be objective: task, rules, blackboard and criteria are injected automatically.',
  'g.fExit':
      'Commands that PROVE the step finished well (e.g. dart analyze, dart test). They are the heart of the loop — without them the step passes on the agent report alone.',
  'g.fMaxIter':
      'How many attempts the step gets to pass verification before "On fail".',
  'g.fOnFail':
      'What to do when iterations run out: Wait for human (recommended), Fail the run or Continue anyway.',
  'g.connTitle': 'Connections (the flow routes)',
  'g.connSuccess':
      'Follows when the step verification passes. The default route.',
  'g.connFailure':
      'Alternative route when the step exhausts its iterations without passing.',
  'g.connVerdict':
      'Route chosen by the node\'s AGENT — works on ANY node, not only decision. Each verdict connection has a value and an INSTRUCTION ("when to take this route", e.g. "when the RFC has no findings left"); the instructions go into the prompt, the agent writes "verdict" with the chosen route\'s value and the runner follows that connection. When the verdict is the only way out, the runner REQUIRES the agent to write one.',
  'g.connAlways': 'Follows regardless of the result.',
  'g.connFanout':
      'Branch out: one step can feed several — they execute one after another.',
  'g.connJoin':
      'Join: several steps converging into one — the join waits for all of them.',
  'g.connLoop':
      'Loop back: a connection to an earlier step re-executes that stretch (e.g. rejected → replan).',
  'g.preTitle': 'Before running (checklist)',
  'g.pre1':
      'Flow Runner ON — Settings → Host the Flow Runner (or the banner button on the Runs tab).',
  'g.pre2':
      'Agents green in diagnostics — CLI installed + Oracle MCP configured; use "Run real test" to prove it.',
  'g.pre3':
      'Project with a git repository — the run creates the branch/worktree in it.',
  'g.tasksTitle': 'Tasks (the backlog)',
  'g.tasksBody':
      'Create tasks with a title and a clear description — it becomes the core of every step prompt. "Run" asks for the process and enqueues the run. The statuses follow the cycle:',
  'g.monTitle': 'Watching a run',
  'g.mon1':
      'Sent prompt — exactly what the agent received, rendered as markdown.',
  'g.mon2':
      'Agent report — summary, outputs, files touched and open questions, structured.',
  'g.mon3':
      'Verification — every command with pass/fail and the error output when any.',
  'g.mon4':
      'Human gates — the run parks and the Approve/Reject buttons appear at the top.',
  'g.bestTitle': 'Best practices',
  'g.doTitle': 'Do',
  'g.do1': 'Small steps with objective verification (tests/build).',
  'g.do2':
      'One code writer at a time; reviewers record findings on the blackboard.',
  'g.do3': 'Orchestrator for planning and verdict decisions.',
  'g.do4': 'A token budget on the process for long runs.',
  'g.demoCaption':
      'Simulation: this is how a run walks the graph — pending → running → done.',
  'g.cmdTitle': 'The command underneath (how the agent is triggered)',
  'g.cmdBody':
      'For each agent step, the runner executes the agent CLI headless INSIDE the run worktree — "<prompt>" is the full prompt composed in step 4. The exact command used in each iteration is shown in the run\'s "Verification" pane.',
  'g.cmdNote':
      'The CLI output is parsed to extract tokens used and the session id; the exit code + the verification commands decide whether the step passed. The Oracle MCP comes from the project\'s .mcp.json/config — that is how the agent reaches step_context, context_put, artifact_add and step_report.',
  'g.ctxTitle': 'How the next step knows what happened',
  'g.ctxBody':
      'No step depends on the previous one\'s transcript. Everything a step produces is recorded STRUCTURED in the database, and the runner injects it into the next prompt — plus live MCP tools to query:',
  'g.ctxStepN': 'Step N',
  'g.ctxStepN1': 'Step N+1',
  'g.ctxProduces': 'PRODUCES →',
  'g.ctxChipReport': 'report (summary, outputs, files)',
  'g.ctxChipBlackboard': 'blackboard (plan, rfc_id, verdict…)',
  'g.ctxChipArtifacts': 'artifacts (PR, commit, RFC)',
  'g.ctxChipCommit': 'commits on the run branch',
  'g.ctx1':
      'Step N+1\'s prompt arrives with the previous report summaries and the blackboard inlined.',
  'g.ctx2':
      'The oracle_flow_step_context tool returns everything live (task, blackboard, reports, artifacts).',
  'g.ctx3':
      'The code itself travels through the run\'s git branch — the next step works on top of the previous commits.',
  'g.ctx4':
      'Therefore: write to the blackboard what later steps will need — transcripts are not passed.',
  'g.kindUse.agent':
      'Use for any code work: implement, review, test, document.',
  'g.kindUse.orchestrator':
      'Use at the start for planning, and at decision points (writes "verdict" to route).',
  'g.kindUse.decision':
      'Dedicated evaluator: it only evaluates and routes (implements nothing). Remember: ANY node can route through verdict connections with instructions — use this kind when you want the evaluation as its own step.',
  'g.kindUse.subflow':
      'Use to compose processes: a "code review" or "release" flow becomes a reusable step inside others — the child runs in the same workspace and hands the blackboard back.',
  'g.kindUse.rfc_create':
      'Use after planning to formalize the spec as an RFC before implementing.',
  'g.kindUse.rfc_review':
      'Use after RFC creation: reviewers surface gaps/bugs with evidence.',
  'g.kindUse.command':
      'Use for deterministic passes: build, migration, deploy, lint.',
  'g.kindUse.human_gate':
      'Use before irreversible actions (merge, release) — the run waits for you.',
  'g.mon5':
      'Command — the exact CLI line that triggered the agent/step, in the Verification pane.',
  'g.dontTitle': 'Avoid',
  'g.dont1':
      'Steps without verification commands — the loop does not converge.',
  'g.dont2': 'Two steps writing code in parallel on the same branch.',
  'g.dont3': 'Huge prompts repeating what the runner already injects.',
  'g.dont4':
      'Short timeouts on agent steps — they may legitimately run for hours.',
  'tasks.workerOff':
      'Run enqueued — but the Flow Runner is OFF. Turn it on in the Runs tab or in Settings.',
  'runs.blackboard': 'Blackboard (context)',
  'runs.artifacts': 'Artifacts',
  'runs.timeline': 'Timeline',
  'runs.tokens': 'tokens',
  'runs.worktree': 'Workspace',
  'runs.worktreeHint':
      'Isolated git worktree where this run\'s agents work — same project, its own branch. Click to copy the path.',
  'runs.skip': 'Skip step',
  'runs.skipQ': 'Skip step',
  'runs.skipMsg':
      'The current step will be marked SKIPPED (no execution/retry) and the flow moves on. If an attempt is running right now, the skip applies as soon as it finishes. Use when the step was resolved externally or is blocking the process.',
  'runs.skipTo': 'Follow which connection?',
  'runs.skipQueued': 'Skip registered — applies at the next step boundary',
  'runs.parkedRetryHint':
      'This run parked because the step FAILED (not a normal approval): Approve = re-run the step; "Skip step" = move on without it; Reject = end the run.',
  'runs.currentStep': 'Running now',
  'runs.nextSteps': 'Next steps',
  'runs.doneSteps': 'Executed steps',
  'runs.verifRunning': 'Step executing — the agent is working…',
  'runs.subflowRan': 'Sub-process',
  'mod.intro':
      'Project modules (auto-resolved from the subpath). Reclassify a "fake project" as a module here.',
  'mod.empty':
      'No modules yet. Agents create them via oracle_module_resolve, or reclassify a project.',
  'mod.reclassify': 'Reclassify project',
  'mod.reclassifyTitle': 'Reclassify project as a module',
  'mod.reclassifyDesc':
      'Pick a project that is really a module of "{p}". It becomes a module here, with its rules/memories/architecture/skills and history re-pointed; the stray project is removed.',
  'mod.sourceProject': 'Project to reclassify',
  'mod.noOtherProjects': 'No other project to reclassify.',
  'mod.reclassified': 'Project reclassified as a module.',
  'nav.sessions': 'Sessions',
  'nav.sessionsHint': 'Captured history: sessions, requests and messages',
  'nav.handoffs': 'Handoffs',
  'nav.handoffsHint': 'Context passed between sessions (pending and history)',
  'nav.searchHistory': 'Search history',
  'nav.searchHistoryHint':
      'What agents searched vs what came back (audit retrieval)',
  'hist.intro':
      "Every agent search: the tool, the query and what came back. Empty searches = gaps in memory.",
  'hist.onlyGaps': 'Only gaps',
  'hist.noGaps': 'No empty searches. 🎉',
  'hist.empty': 'No searches logged yet.',
  'hist.gap': 'gap (0 results)',
  'hist.hits': 'results',
  'hist.selectOne': 'Select a search to see its results.',
  'hist.filters': 'Filters',
  'hist.results': 'Returned results',
  'hist.gapNote':
      'Nothing came back — possibly a gap: what was asked is not in memory, or the term did not match.',
  'nav.duplicates': 'Duplicates',
  'nav.duplicatesHint': 'Find and clean up near-duplicate items',
  'handoff.empty':
      'No handoffs yet. The agent writes one at the end of a task.',
  'handoff.selectOne': 'Select a handoff to see its context.',
  'handoff.contextTitle': 'Handoff context',
  'handoff.open': 'Pending',
  'handoff.accepted': 'Accepted',
  'handoff.expired': 'Expired',
  'handoff.nextSteps': 'Next steps',
  'handoff.openQuestions': 'Open questions',
  'handoff.filesTouched': 'Files touched',
  'dup.intro':
      'Near-identical items grouped by embedding proximity. Keep one and retire the rest.',
  'dup.memories': 'Memories',
  'dup.rules': 'Rules',
  'dup.rescan': 'Rescan',
  'dup.runSweep': 'Run dedup now',
  'dup.none': 'No duplicates found. 🎉',
  'dup.items': 'items',
  'dup.retireOthers': 'Retire the others',
  'dup.keep': 'Keep this one',
  'dup.retireQ': 'Retire duplicates?',
  'dup.retireMsg':
      'The other {n} memories will be retired (soft — recoverable).',
  'dup.retire': 'Retire',
  'dup.retired': 'Duplicates retired.',
  'dup.sweepDone': 'Dedup sweep complete.',
  'nav.backup': 'Backup',
  'nav.backupHint': 'Database backups: now and scheduled',
  'nav.settings': 'Settings',
  'nav.settingsHint': 'Connection, daemon, .env and agent integration',
  'shell.project': 'Project',
  'shell.tagline': 'Memory bank',
  'shell.connected': 'Connected',
  'shell.offline': 'Offline',
  'shell.daemonOn': 'daemon on',
  'shell.daemonOff': 'daemon off',
  'shell.switchProject': 'Switch project',
  'shell.noProjects': 'No projects yet',
  'shell.deleteProject': 'Delete project',
  'shell.deleteProjectConfirm':
      'Delete the project "{p}" ({path})?\n\nEVERYTHING that belongs to it will be removed: memories, rules, sessions, skills, RFCs, processes and runs. Use this to clean up wrongly registered projects (e.g. worktrees). This cannot be undone.',
  'shell.deleteProjectDo': 'Delete everything',
  'shell.noPath': 'no path',
  'shell.noEnvTip': 'No .env (defaults)',
  'tray.open': 'Open Oracle Studio',
  'tray.backup': 'Back up now',
  'tray.quit': 'Quit',
  'tray.tooltip': 'Oracle Studio — memory bank',
  'common.selectProject': 'Select a project.',
  'common.refresh': 'Refresh',
  'common.cancel': 'Cancel',
  'common.save': 'Save',
  'common.saving': 'Saving…',
  'common.close': 'Close',
  'common.apply': 'Apply',
  'common.confirm': 'Confirm',
  'common.loadError': 'Failed to load',
  'common.tags': 'Tags (comma separated)',
  'common.tagsDesc':
      'Labels to filter and group. E.g. auth, backend, performance.',
  'common.editVersion': 'Edit (new version)',
  'common.retireSoft': 'Retire (keeps audit trail)',
  'common.deleteHard': 'Delete permanently',
  'common.retire': 'Retire',
  'common.delete': 'Delete',
  'common.failure': 'Failed',
  'dash.title': 'Dashboard',
  'dash.subtitle':
      'An overview of the selected project and the whole memory bank.',
  'dash.thisProject': 'This project',
  'dash.thisProjectSub':
      'Identity and numbers for the project selected at the top.',
  'dash.global': 'Whole memory bank',
  'dash.globalSub': 'Totals across every project and organization.',
  'dash.created': 'created',
  'dash.organizations': 'Organizations',
  'dash.projects': 'Projects',
  'dash.modules': 'Modules',
  'dash.tokens': 'Tokens',
  'dash.searches': 'Searches',
  'dash.capModules': "Project subdivisions (auto-resolved).",
  'dash.capTokens': "Total tokens summed across the project's sessions.",
  'dash.memories': 'Memories',
  'dash.rules': 'Rules',
  'dash.skills': 'Skills',
  'dash.architectures': 'Architectures',
  'dash.sessions': 'Sessions',
  'dash.requests': 'Requests',
  'dash.messages': 'Messages',
  'dash.handoffs': 'Handoffs',
  'dash.capMemories': "This project's consolidated learnings",
  'dash.capRules': 'Project-owned rules (latest version)',
  'dash.capArch': 'Architecture notes per area',
  'dash.capSessions': 'Captured agent sessions',
  'dash.capRequests': 'Recorded user requests',
  'dash.capHandoffs': 'Context handoffs between sessions',
  'dash.health': 'Memory bank health',
  'dash.healthSub': 'Deterministic checks (lint) — the more zeros, the better.',
  'dash.healthy': 'All healthy',
  'dash.attention': 'Needs attention',
  'dash.memNoEmb': 'Memories without embedding',
  'dash.memNoEmbSub': 'blind to semantic search',
  'dash.ruleNoEmb': 'Rules without embedding',
  'dash.ruleNoEmbSub': 'absent from semantic search',
  'dash.reqNoMsg': 'Requests without answer',
  'dash.reqNoMsgSub': 'requests with no messages',
  'dash.staleVec': 'Stale-model vectors',
  'dash.staleVecSub': 'embedded with another model',
  'dash.model': 'current model',
  'dash.metrics': 'Metrics per experiment',
  'dash.metricsSub':
      'Tokens and compactions per label (A/B: oracle vs baseline).',
  'dash.noMetrics': 'No metrics recorded yet — they appear as agents work.',
  'dash.sessionsCol': 'Sessions',
  'dash.compactions': 'Compactions',
  'mem.searchHint': 'Search memories (hybrid: semantic + text)…',
  'mem.new': 'New memory',
  'mem.editTitle': 'Edit memory (new version)',
  'mem.newTitle': 'New memory',
  'mem.fieldTitle': 'Title',
  'mem.fieldTitleDesc': 'A short, searchable headline for the learning.',
  'mem.fieldBody': 'Body',
  'mem.fieldBodyDesc':
      'The fact AND why it matters. Markdown supported. Skip anything derivable from code.',
  'mem.fieldKey': 'Key (optional — stable identity for updates)',
  'mem.fieldKeyDesc':
      'Reusing the same key supersedes the memory (versioned) instead of duplicating it.',
  'mem.kind': 'Kind',
  'mem.tier': 'Tier',
  'mem.importance': 'Importance',
  'mem.selectOne': 'Select a memory.',
  'mem.created': 'Memory created.',
  'mem.versionSaved': 'New version saved.',
  'mem.forgetQ': 'Forget memory?',
  'mem.deleteQ': 'Delete permanently?',
  'mem.forgetMsg': 'leaves recall but is kept for audit.',
  'mem.deleteMsg': 'will be deleted FOREVER (no audit trail).',
  'mem.forget': 'Forget',
  'mem.forgotten': 'Memory forgotten.',
  'mem.deleted': 'Memory deleted.',
  'mem.forgetSoft': 'Forget (keeps audit trail)',
  'rule.header': 'Project rules (with organization inheritance)',
  'rule.new': 'New rule',
  'rule.newTitle': 'New rule (project-scoped)',
  'rule.editTitle': 'Refine rule (new version)',
  'rule.fieldKey': 'Key (stable slug — same key = update)',
  'rule.fieldKeyDesc':
      'A stable identifier (e.g. parametrized-sql). Re-saving the same key refines the rule.',
  'rule.fieldScope': 'Scope (module/folder/area)',
  'rule.fieldScopeDesc':
      'Where the rule applies. Empty = whole project; or a specific module/folder.',
  'rule.fieldTitle': 'Title',
  'rule.fieldContent': 'Content',
  'rule.fieldContentDesc':
      'The rule itself, with its rationale. Markdown supported.',
  'rule.severity': 'Severity',
  'rule.required': 'required',
  'rule.recommended': 'recommended',
  'rule.priority': 'Priority',
  'rule.priorityHint': 'Lower = more relevant (1 comes first · 100 last)',
  'rule.selectOne': 'Select a rule.',
  'rule.created': 'Rule created.',
  'rule.refined': 'Rule refined (new version).',
  'rule.rerank': 'Re-rank rule',
  'rule.adjust': 'Adjust',
  'rule.prioritySet': 'Priority set to',
  'rule.retireQ': 'Retire rule?',
  'rule.deleteQ': 'Delete permanently?',
  'rule.retireMsg': 'leaves recall but is kept for audit.',
  'rule.deleteMsg': 'will be deleted FOREVER.',
  'rule.retired': 'Rule retired.',
  'rule.deleted': 'Rule deleted.',
  'rule.fromProject': 'project-scoped',
  'rule.fromOrganization': 'organization (inherited)',
  'rule.refine': 'Refine (new version)',
  'rule.scopeChip': 'scope',
  'rfc.header': 'Project RFCs (multi-agent review)',
  'rfc.new': 'New RFC',
  'rfc.newTitle': 'New RFC',
  'rfc.fieldTitle': 'Title',
  'rfc.fieldTitleDesc': 'A short headline for the technical spec under review.',
  'rfc.fieldType': 'Type (checklist profile)',
  'rfc.fieldTypeDesc':
      'backend | frontend | fullstack | data | infra | generic.',
  'rfc.fieldSummary': 'Summary',
  'rfc.fieldSummaryDesc':
      "Version 1's executable substrate. Markdown supported. This is what goes to semantic recall.",
  'rfc.titleRequired': 'Title is required.',
  'rfc.created': 'RFC opened.',
  'rfc.selectOne': 'Select an RFC.',
  'rfc.empty':
      'No RFCs yet. Create one here or let agents open one via oracle_rfc_open.',
  'rfc.filterAll': 'All',
  'rfc.filterOpen': 'Open',
  'rfc.filterApproved': 'Approved',
  'rfc.round': 'round',
  'rfc.readiness': 'Readiness',
  'rfc.readinessDesc':
      'The termination gate at a glance: verified blockers + required coverage.',
  'rfc.ready': 'ready',
  'rfc.notReady': 'in review',
  'rfc.blockingCriticals': 'blockers',
  'rfc.openMajors': 'open majors',
  'rfc.totalComments': 'findings',
  'rfc.requiredCovered': 'required covered',
  'rfc.summaryTitle': 'Version summary',
  'rfc.sections': 'Sections',
  'rfc.findings': 'Findings',
  'rfc.noFindings': 'No findings recorded yet.',
  'rfc.verified': 'verified',
  'rfc.unverified': 'unverified',
  'rfc.problem': 'Problem',
  'rfc.solution': 'Proposed solution',
  'rfc.finalize': 'Finalize',
  'rfc.finalizeQ': 'Finalize RFC?',
  'rfc.finalizeMsg':
      'goes through the termination gate (blockers + coverage) before approval.',
  'rfc.finalized': 'RFC',
  'rfc.copyPrompt': 'Copy review prompt',
  'rfc.promptCopied': 'Prompt copied.',
  'rfc.st.draft': 'draft',
  'rfc.st.open_for_comments': 'open',
  'rfc.st.in_review': 'in review',
  'rfc.st.in_consolidation': 'consolidating',
  'rfc.st.awaiting_human': 'awaiting human',
  'rfc.st.stalled': 'stalled',
  'rfc.st.approved': 'approved',
  'rfc.st.rejected': 'rejected',
  'rfc.st.superseded': 'superseded',
  'rfc.st.obsolete': 'obsolete',
  'skill.header': 'Central skill library',
  'skill.headerTip':
      'One source for every agent (MCP). "Sync" materializes to ~/.claude/skills for Claude Code native discovery.',
  'skill.sync': 'Sync to disk',
  'skill.syncing': 'Syncing…',
  'skill.new': 'New skill',
  'skill.newTitle': 'New skill',
  'skill.editTitle': 'Edit skill (new version)',
  'skill.fieldKey': 'Key (stable kebab-case slug — becomes the folder name)',
  'skill.fieldName': 'Name',
  'skill.fieldDesc':
      'Description (the recall trigger: what it does + when to use)',
  'skill.fieldContent': 'Content (markdown, SKILL.md style)',
  'skill.scope': 'Scope',
  'skill.scopeGlobal': 'Global (all projects and agents)',
  'skill.scopeProject': 'This project',
  'skill.scopeSelectProject': 'This project (select a project)',
  'skill.global': 'global',
  'skill.project': 'project',
  'skill.organization': 'organization',
  'skill.empty':
      'No skills yet — create one here or let agents save with oracle_skill_save.',
  'skill.selectOne': 'Select a skill.',
  'skill.created': 'Skill created.',
  'skill.updated': 'Skill updated (new version).',
  'skill.retireQ': 'Retire skill?',
  'skill.deleteQ': 'Delete permanently?',
  'skill.retireMsg': 'leaves the library but is kept for audit.',
  'skill.deleteMsg': 'will be deleted FOREVER.',
  'skill.retired': 'Skill retired.',
  'skill.deleted': 'Skill deleted.',
  'skill.synced': 'Synced',
  'skill.syncFail': 'Sync failed',
  'skill.pruned': 'pruned',
  'sess.selectSession': 'Select a session.',
  'sess.tokensIn': 'in',
  'sess.tokensOut': 'out',
  'sess.selectRequest': 'Select a request.',
  'search.hint': 'Search the whole memory bank (memories, rules and skills)…',
  'search.prompt': 'Type and press Enter to search everything.',
  'search.empty': 'Nothing found.',
  'search.memories': 'Memories',
  'search.rules': 'Rules',
  'search.skills': 'Skills',
  'search.sections': 'Sections (architecture)',
  'bk.title': 'Memory bank backup',
  'bk.explain':
      'Writes a portable .sql seed with ALL data (embeddings included, consistent snapshot). Restore into an empty database with `oracle_ai restore-db`, or let `docker compose up` restore it on a fresh volume.',
  'bk.target': 'Target',
  'bk.run': 'Back up now',
  'bk.running': 'Backing up…',
  'bk.done': 'Backup complete',
  'bk.rows': 'rows',
  'bk.scheduleNote':
      'Scheduled backups (interval + retention) live in Settings — the Studio runs them in the background.',
  'set.title': 'Settings',
  'set.daemon': 'Background daemon',
  'set.daemonExplain':
      'When on, the Studio itself is the hook receiver at http://127.0.0.1:47500/hook — no Docker or console oracle_ai.exe needed. Keep the Studio open (it lives in the tray) and turn on "Start with Windows" so hooks are always up. Use a port below 49152 (Windows reserves the dynamic range above that); if another process holds it, the Studio takes over automatically when it stops.',
  'set.hostToggle': 'Host hooks + maintenance in this app',
  'set.workerToggle': 'Host the Flow Runner (Loop Engineering)',
  'set.workerDesc':
      'Drives queued runs: launches agents, creates worktrees and runs the verifiers',
  'set.workerParallel': 'Parallel processes',
  'set.workerParallelDesc':
      'How many runs the worker drives AT THE SAME TIME (each launches its own agents — more parallelism = more CPU/API in use)',
  'set.autostart': 'Start with Windows',
  'set.autostartSub':
      'Opens the Studio (in the tray) at login — hooks and backups always on.',
  'set.autostartOn': 'The Studio will start with Windows.',
  'set.autostartOff': 'Autostart disabled.',
  'set.language': 'Language',
  'set.schedTitle': 'Scheduled backup',
  'set.schedExplain':
      'Timestamped .sql snapshots in backups/ (with retention). The commit/docker seed stays manual, on the Backup tab.',
  'set.schedToggle': 'Back up automatically',
  'set.every': 'Every',
  'set.hours6': '6 hours',
  'set.hours12': '12 hours',
  'set.hours24': '24 hours',
  'set.hours48': '48 hours',
  'set.keepLast': 'Keep last',
  'set.runNow': 'Run now',
  'set.runningNow': 'Running…',
  'set.lastBackup': 'Last backup',
  'set.agents': 'Agent integration',
  'set.agentsDesc':
      'Pick your agent and copy its MCP and hooks config. The protocol (at the end) is the same for all.',
  'set.targetsTitle': 'Where to configure each agent',
  'set.mcpTitle': '.mcp.json (agent project root)',
  'set.hooksTitle': 'Claude Code settings.json ("hooks" block)',
  'set.promptTitle': 'Prompt for your agent (CLAUDE.md / AGENTS.md)',
  // per-agent tabs
  'ag.mcp': 'MCP server',
  'ag.cli': 'CLI shortcut',
  'ag.hooks': 'Hooks (automatic capture)',
  'ag.hooksHttp':
      'This agent POSTs straight to the hook receiver — no bridge needed.',
  'ag.hooksBridge':
      'This agent\'s hooks run a command: we use "oracle_ai forward-hook" to relay the event to the receiver. Needs Oracle Studio (or the daemon) hosting the receiver. Capture works; automatic recall varies by agent — when unsure, use the MCP tools.',
  'ag.hooksNone':
      'This agent has no lifecycle hooks. Use the MCP tools + the protocol below to recall and record manually.',
  'ag.instr': 'Instruction file',
  'ag.instrBody': 'Paste the protocol (at the end of this section) into:',
  'ag.badgeHttp': 'Native hooks (HTTP)',
  'ag.badgeBridge': 'Hooks via bridge',
  'ag.badgeNone': 'No hooks',
  'set.promptDesc':
      "Paste this protocol into your agent's instruction file to teach it the Oracle workflow: "
      'recall before re-deriving, record what is durable, and hand off what is open.',
  'set.copied': 'copied to clipboard.',
  'set.copy': 'Copy',
  'set.envSave': 'Save .env',
  'set.envSaved': 'Saved. Restart the Studio (and the MCP) to apply.',
  'set.envMissing': 'No .env connected — create one at the project root.',
  'set.envNotFound': '(not found)',
  'set.subtitle':
      'Connection, daemon, backups and integration — all of Oracle in one place.',
  'set.langDesc': 'Studio interface language.',
  'set.daemonStatus': 'Hook receiver status',
  'set.online': 'Online',
  'set.offline': 'Off',
  'set.portBusy': 'Port busy',
  'env.title': 'Connection & environment (.env)',
  'env.desc':
      'These settings apply to the Studio, the agents\' MCP and the daemon. Saving updates the .env file safely (automatic .bak backup, comments preserved). Restart the Studio and agents to apply.',
  'env.db': 'PostgreSQL database',
  'env.dbDesc':
      'Where the memory lives. Use the database from setup or point elsewhere.',
  'env.host': 'Host',
  'env.port': 'Port',
  'env.user': 'User',
  'env.password': 'Password',
  'env.dbName': 'Database name',
  'env.embed': 'Embeddings (semantic search)',
  'env.embedDesc':
      '"local" is offline and free. API providers (Gemini/OpenAI/Voyage) give higher quality — after switching, run re-embed in maintenance.',
  'env.provider': 'Provider',
  'env.apiKey': 'Provider API key',
  'env.server': 'Local server (hooks)',
  'env.serverDesc':
      'HTTP endpoint receiving agent events (sessions, messages). Loopback by default.',
  'env.httpHost': 'HTTP host',
  'env.httpPort': 'HTTP port',
  'env.token': 'Hook token',
  'env.tokenDesc':
      'Protects the /hook endpoint. Optional on loopback; required if the port is exposed. When changed, update the hooks snippet in your agents too.',
  'env.generate': 'Generate',
  'env.maint': 'Maintenance & metrics',
  'env.interval': 'Maintenance every (minutes)',
  'env.intervalDesc': '0 disables the periodic sweep (memory decay + dedup).',
  'env.metricsLabel': 'Metrics label (experiment)',
  'env.save': 'Save settings',
  'env.saved': 'Settings saved to .env. Restart the Studio to apply.',
  'env.advanced': 'Advanced: edit .env manually',
  'bk.folder': 'Backup folder',
  'bk.folderDesc':
      'Where backups (manual and scheduled) are written. Default: Documents › Oracle AI › backups.',
  'bk.change': 'Change…',
  'bk.reset': 'Use default',
  'bk.openFolder': 'Open folder',
  'bk.subtitle':
      'A backup is a portable .sql file with ALL the memory (embeddings included). Keep it, version it, or take it to another machine.',
  'bk.what': 'What does a backup contain?',
  'bk.whatDesc':
      'Every organization, project, memory, rule, skill, session and metric — with a consistent snapshot even while agents keep working. Restore only happens into an empty database (never overwrites).',
};
