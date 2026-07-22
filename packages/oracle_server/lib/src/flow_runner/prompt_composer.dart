import 'dart:convert';

import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';

/// One verdict route a step can take: the value the agent must write plus the
/// flow author's instruction of WHEN to take it (rendered into the prompt).
typedef VerdictOption = ({String value, String? instruction});

/// Composes the prompt handed to a step's agent, in the configured language
/// (pt/en). The agent depends only on this structured context (task + step
/// brief + inlined run state + verifier feedback), never on a prior agent's
/// transcript — and the run state is INLINED (blackboard, prior step reports,
/// artifacts) so the agent starts oriented even before its first tool call.
/// The prompt teaches the step protocol: pull context, work, write shared
/// state, report — and that the runner verifies OUTSIDE the agent, so it must
/// never self-approve.
class PromptComposer {
  String compose({
    required FlowRunEntity run,
    required FlowStepEntity step,
    required IdVO runStepId,
    required int iteration,
    String? claimToken,
    TaskEntity? task,
    StepContext? context,
    List<RuleEntity> rules = const [],
    List<VerdictOption> verdictOptions = const [],
    String? verifierFeedback,
    String language = 'pt',
  }) {
    final t = _fragments[language] ?? _fragments['pt']!;
    final b = StringBuffer();

    // ── mission ──
    b.writeln('# ${t['title']} — "${step.stepKey}"');
    b.writeln();
    b.writeln(t['mission']);
    b.writeln();
    b.writeln(
      '- ${t['step']}: `${step.stepKey}`'
      '${step.name.trim().isEmpty ? '' : ' — ${step.name.trim()}'}',
    );
    b.writeln('- ${t['role']}: ${step.role ?? step.kind.code}');
    if (iteration > 1) {
      b.writeln(
        '- ${t['iteration']}: $iteration/${step.maxIterations} — '
        '${t['iterationRetry']}',
      );
    }
    if (run.branchName != null) {
      b.writeln(
        '- ${t['workspace']}: ${t['workspaceBranch']} '
        '`${run.branchName}`. ${t['workspaceRules']}',
      );
    } else {
      b.writeln('- ${t['workspace']}: ${t['workspaceCwd']}');
    }
    b.writeln();

    // ── the task ──
    if (task != null) {
      b.writeln('## ${t['taskTitle']}');
      b.writeln('**${task.title.value}**');
      if (task.description.trim().isNotEmpty) {
        b.writeln();
        b.writeln(task.description.trim());
      }
      b.writeln();
    }

    // ── step instructions (the flow author's brief) ──
    if (step.promptTemplate.trim().isNotEmpty) {
      b.writeln('## ${t['instructionsTitle']}');
      b.writeln(step.promptTemplate.trim());
      b.writeln();
    }

    // ── project rules (EVERY step agent gets them) ──
    if (rules.isNotEmpty) {
      b.writeln('## ${t['rulesTitle']}');
      for (final r in rules) {
        b.writeln(
          '- [${r.severity.code}] ${r.title.value}'
          '${r.key.trim().isEmpty ? '' : ' (`${r.key}`)'}',
        );
      }
      b.writeln(t['rulesFooter']);
      b.writeln();
    }

    // ── skills attached to this step (from the Oracle skill library) ──
    final skills = _stepSkills(step.config);
    if (skills.isNotEmpty) {
      b.writeln('## ${t['skillsTitle']}');
      b.writeln(t['skillsIntro']);
      for (final s in skills) {
        b.writeln('- key: `$s`');
      }
      b.writeln();
    }

    // ── inlined run state (the blackboard) ──
    final ctx = context;
    if (ctx != null && ctx.context.isNotEmpty) {
      b.writeln('## ${t['blackboardTitle']}');
      for (final c in ctx.context) {
        b.writeln('- `${c.key}`: ${_compact(c.value)}');
      }
      b.writeln();
    }
    if (ctx != null && ctx.priorReports.isNotEmpty) {
      b.writeln('## ${t['reportsTitle']}');
      for (final r in ctx.priorReports) {
        final summary = _reportSummary(r.report);
        if (summary != null) b.writeln('- $summary');
      }
      b.writeln();
    }
    if (ctx != null && ctx.artifacts.isNotEmpty) {
      b.writeln('## ${t['artifactsTitle']}');
      for (final a in ctx.artifacts) {
        b.writeln('- ${a.kind}: ${a.locator}');
      }
      b.writeln();
    }

    // ── exit criteria ──
    final criteria = _exitCommands(step.exitCriteria);
    if (criteria.isNotEmpty) {
      b.writeln('## ${t['exitTitle']}');
      b.writeln(t['exitIntro']);
      for (final c in criteria) {
        b.writeln('- `$c`');
      }
      b.writeln();
    }

    // ── verifier feedback (inner-loop retry) ──
    if (verifierFeedback != null && verifierFeedback.trim().isNotEmpty) {
      b.writeln('## ${t['feedbackTitle']}');
      b.writeln('```');
      b.writeln(verifierFeedback.trim());
      b.writeln('```');
      b.writeln(t['feedbackFooter']);
      b.writeln();
    }

    // ── kind-specific missions ──
    if (step.kind == FlowStepKind.orchestrator) {
      b.writeln('## ${t['orchTitle']}');
      b.writeln(t['orchBody']);
      b.writeln();
    } else if (step.kind == FlowStepKind.decision) {
      b.writeln('## ${t['decisionTitle']}');
      b.writeln(t['decisionBody']);
      b.writeln();
    }

    // ── verdict routing (any step with outgoing verdict edges) ──
    // Each route lists the flow author's INSTRUCTION of when to take it, so
    // any agent node can decide — not just a dedicated decision step.
    if (verdictOptions.isNotEmpty) {
      b.writeln('## ${t['verdictTitle']}');
      b.writeln(t['verdictIntro']);
      for (final v in verdictOptions) {
        final inst = (v.instruction ?? '').trim();
        b.writeln(inst.isEmpty ? '- `${v.value}`' : '- `${v.value}` — $inst');
      }
      b.writeln(t['verdictFooter']);
      b.writeln();
    }

    final outputSchema = step.outputSchema?.trim() ?? '';
    if (outputSchema.isNotEmpty && outputSchema != '{}') {
      b.writeln(
        language == 'en'
            ? '## Required structured output'
            : '## Saída estruturada obrigatória',
      );
      b.writeln(
        language == 'en'
            ? 'The `outputs` object in your final report must satisfy this JSON Schema:'
            : 'O objeto `outputs` do relatório final deve obedecer a este JSON Schema:',
      );
      b.writeln('```json');
      b.writeln(outputSchema);
      b.writeln('```');
      b.writeln();
    }

    // ── RFC-specific protocol (create / review steps) ──
    if (step.kind == FlowStepKind.rfcCreate) {
      b.writeln('## ${t['rfcCreateTitle']}');
      b.writeln(t['rfcCreateBody']);
      b.writeln();
    } else if (step.kind == FlowStepKind.rfcReview) {
      b.writeln('## ${t['rfcReviewTitle']}');
      b.writeln(t['rfcReviewBody']);
      b.writeln();
    } else if (step.kind == FlowStepKind.rfcConsolidate) {
      b.writeln('## ${t['rfcConsolidateTitle']}');
      b.writeln(t['rfcConsolidateBody']);
      b.writeln();
    }

    // ── protocol ──
    b.writeln('## ${t['protocolTitle']}');
    b.writeln(t['protocolWarn']);
    b.writeln();
    b.writeln(
      language == 'en'
          ? '**USE THE MCP SURFACE AVAILABLE IN THIS CLIENT:** prefer a native '
                'direct `oracle_*` tool when it is exposed. If this Codex client '
                'only exposes MCP tools through `functions.exec` / `exec` as '
                '`tools.mcp__oracle_ai__oracle_*`, USE that supported programmatic '
                'wrapper. Do not refuse the step because a native direct tool is '
                'absent. Never emulate Oracle with shell, curl, or by launching '
                'the executable yourself.'
          : '**USE A SUPERFÍCIE MCP DISPONÍVEL NESTE CLIENTE:** prefira uma tool '
                '`oracle_*` direta quando ela estiver exposta. Se este cliente '
                'Codex expuser as MCPs somente por `functions.exec` / `exec` como '
                '`tools.mcp__oracle_ai__oracle_*`, USE esse wrapper programático '
                'suportado. Não recuse a etapa só porque a tool direta não existe. '
                'Nunca emule o Oracle com shell, curl ou iniciando o executável '
                'manualmente.',
    );
    b.writeln();
    b.writeln(t['mcpRetry']);
    b.writeln();
    b.writeln(
      '1. ${t['p1']} `oracle_flow_step_context` '
      '(runStepId: "${runStepId.value}") — ${t['p1b']}',
    );
    b.writeln('2. ${t['p2']}');
    b.writeln(
      '3. ${t['p3']} `oracle_flow_context_put` '
      '(runId: "${run.id.value}", runStepId: "${runStepId.value}", key, value) '
      '— ${t['p3b']}',
    );
    b.writeln(
      '4. ${t['p4']} `oracle_flow_artifact_add` '
      '(runId: "${run.id.value}", runStepId: "${runStepId.value}", kind: '
      'branch|commit|pr|rfc|doc|file|memory, locator).',
    );
    final tokenArg = (claimToken == null || claimToken.trim().isEmpty)
        ? ''
        : ', claimToken: "${claimToken.trim()}"';
    b.writeln(
      '5. ${t['p5']} `oracle_flow_step_report` '
      '(runStepId: "${runStepId.value}"$tokenArg) ${t['p5b']}',
    );
    if (tokenArg.isNotEmpty) b.writeln('   ${t['p5token']}');
    b.writeln();
    b.writeln(t['rules']);

    // ── tags (config.tags) ──
    // Emitted as slash-command lines at the VERY TOP of the prompt: for Claude
    // Code, `/review`-style lines invoke the matching skill/command; for other
    // CLIs they read as an explicit directive header.
    final tags = _stepTags(step.config);
    if (tags.isEmpty) return b.toString();
    final slash = tags
        .map((tag) => tag.startsWith('/') ? tag : '/$tag')
        .join('\n');
    return '$slash\n\n$b';
  }

  /// Localized prompt fragments. The tool names/ids stay literal; everything the
  /// agent READS as instruction is translated.
  static const _fragments = <String, Map<String, String>>{
    'pt': {
      'title': 'Loop Engineering — etapa',
      'mission':
          'Você é UMA etapa de um run de desenvolvimento multiagente automatizado '
          '(Oracle AI Loop Engineering). Um runner determinístico executa o grafo do '
          'processo; seu trabalho é SOMENTE esta etapa. Faça bem feito, registre os '
          'resultados e finalize — o runner verifica seu trabalho e avança o fluxo.',
      'step': 'Etapa',
      'role': 'Papel',
      'iteration': 'Iteração',
      'iterationRetry':
          'a tentativa anterior FALHOU na verificação; corrija (veja o feedback abaixo)',
      'workspace': 'Workspace',
      'workspaceBranch': 'o diretório de trabalho atual, na branch',
      'workspaceRules':
          'Trabalhe SOMENTE aqui; faça commit das suas mudanças com git ao terminar '
          '(um escritor por branch — você).',
      'workspaceCwd': 'o diretório de trabalho atual. Trabalhe SOMENTE aqui.',
      'taskTitle': 'Tarefa',
      'instructionsTitle': 'Instruções desta etapa',
      'rulesTitle': 'Regras do projeto (você DEVE segui-las)',
      'rulesFooter':
          'Texto completo: `oracle_rule_search` / `oracle_rules_for_task`. Uma regra '
          '[required] é inegociável.',
      'skillsTitle': 'Skills para carregar PRIMEIRO (biblioteca do Oracle)',
      'skillsIntro':
          'Antes de trabalhar, carregue cada uma com `oracle_skill_get` e siga-a:',
      'blackboardTitle':
          'Contexto compartilhado do run (blackboard — escrito pelas etapas anteriores)',
      'reportsTitle': 'Relatórios das etapas anteriores',
      'artifactsTitle': 'Artefatos produzidos até aqui',
      'exitTitle': 'Critérios de saída',
      'exitIntro':
          'Ao terminar, o RUNNER roda estes comandos no workspace — eles precisam passar. '
          'Rode-os você também antes de reportar, mas NÃO enfraqueça testes ou checks '
          'para fazê-los passar:',
      'feedbackTitle': 'Feedback do verificador da tentativa anterior (FALHOU)',
      'feedbackFooter': 'Corrija primeiro a causa raiz dessas falhas.',
      'protocolTitle': 'Protocolo (tools MCP do Oracle — siga na ordem)',
      'protocolWarn':
          '⚠ OBRIGATÓRIO: a etapa SÓ conta como concluída quando você chamar '
          '`oracle_flow_step_report`. Sem esse call o runner marca a tentativa como '
          'FALHA e TODO o seu trabalho é descartado e refeito — desperdício total. '
          'Reserve os minutos finais para o report, SEMPRE, mesmo que o tempo aperte '
          'ou o trabalho fique parcial (reporte o parcial).',
      'p1': 'COMECE chamando',
      'p1b':
          'retorna a tarefa, o blackboard, os relatórios anteriores e os artefatos ao vivo.',
      'p2': 'Faça o trabalho desta etapa. Nada fora do escopo dela.',
      'p3': 'Compartilhe estado que as próximas etapas vão precisar com',
      'p3b':
          'ex.: `plan`, `rfc_id`, `findings_summary`, ou `verdict` quando seu papel é decidir a rota.',
      'p4': 'Registre saídas concretas com',
      'p5': 'FINALIZE chamando',
      'p5b':
          'com um resumo objetivo do que você fez, status "done" (ou "blocked" + '
          'openQuestions se realmente não puder prosseguir — um humano será acionado), '
          'outputs e filesTouched.',
      'p5token':
          'IMPORTANTE: passe o claimToken LITERALMENTE como mostrado acima — sem ele o '
          'report é recusado ("Invalid or stale step claim token"). Se perder o valor, '
          'recupere-o em `oracle_flow_step_context` (campo runStep.claimToken).',
      'mcpRetry':
          'FALHA TRANSITÓRIA DO HOST: se uma chamada Oracle retornar "user cancelled MCP '
          'tool call" (ou variação com "cancelled/cancelado"), NÃO foi você nem o usuário — '
          'é um cancelamento intermitente do próprio host. REPITA a MESMA chamada (até 3 '
          'vezes; ela costuma funcionar na sequência) antes de tratar como bloqueio.',
      'rules':
          'Regras: nunca declare sucesso que você não verificou; nunca apague ou enfraqueça '
          'testes para satisfazer os critérios de saída; o runner decide passou/falhou FORA '
          'de você. Se faltar informação, prefira "blocked" com uma pergunta precisa a chutar.',
      'orchTitle':
          'Sua missão: PLANEJAR (você é o orquestrador, não o executor)',
      'orchBody':
          'Quem gerencia o fluxo é o RUNNER — as próximas etapas serão lançadas '
          'automaticamente com agentes próprios. O seu papel é SÓ planejar: entenda a '
          'tarefa (leia o código apenas o necessário para diagnosticar), e grave no '
          'blackboard (`oracle_flow_context_put`) a key "plan" com: causa/diagnóstico, '
          'passos de implementação e um brief objetivo para cada etapa seguinte. '
          'NÃO implemente, NÃO edite código, NÃO faça commit nesta etapa. Seja rápido — '
          'minutos, não horas.',
      'decisionTitle': 'Sua missão: DECIDIR a rota (nó de decisão)',
      'decisionBody':
          'Você é um nó de DECISÃO: avalie EXATAMENTE o que as instruções desta etapa '
          'pedem (rodar um teste, checar um critério, inspecionar um resultado) e '
          'escolha UM caminho. Grave a escolha no blackboard com '
          '`oracle_flow_context_put` key "verdict", com o valor EXATO de uma das '
          'opções listadas em "Veredito" abaixo — o runner roteia o fluxo por esse '
          'valor. NÃO implemente correções nem faça trabalho além da avaliação; '
          'apenas colete a evidência, decida e reporte o porquê no seu relatório.',
      'verdictTitle': 'Veredito (rota da próxima etapa)',
      'verdictIntro':
          'Este nó tem rotas de VEREDITO. Cada opção abaixo traz a instrução de QUANDO '
          'segui-la — avalie o resultado do seu trabalho contra essas instruções e, antes de '
          'finalizar, grave no blackboard (`oracle_flow_context_put`) a key "verdict" com '
          'EXATAMENTE um destes valores (sem variações, sem texto extra):',
      'verdictFooter':
          'O runner lê esse valor e segue a conexão correspondente. Qualquer outro valor '
          'faz o fluxo cair na conexão padrão (ou falhar) — copie o valor literal.',
      'rfcCreateTitle': 'Sua missão: CRIAR a RFC desta tarefa',
      'rfcCreateBody':
          'Publique a especificação técnica como RFC seccionada com `oracle_rfc_open` '
          '(projectId do brief; seções com key/content, marcando as obrigatórias com '
          'required=true — ex.: context, problem, business_rules, data_model, '
          'acceptance_criteria). Baseie as seções na tarefa e no plano do blackboard. '
          'Depois grave o id no blackboard (`oracle_flow_context_put` key "rfc_id") e '
          'registre o artefato (`oracle_flow_artifact_add` kind "rfc", locator = id).',
      'rfcReviewTitle': 'Sua missão: REVISAR a RFC',
      'rfcReviewBody':
          'Pegue o `rfc_id` no blackboard (ou `oracle_rfc_list_open`), leia com '
          '`oracle_rfc_get` e poste achados ESTRUTURADOS com `oracle_rfc_comment` — todo '
          'gap/inconsistency/bug/blocker exige proposedSolution. Fundamente cada achado com '
          '`oracle_rfc_evidence_add` citando uma entidade real do Oracle (por id) ou '
          'arquivo+trecho que exista — achado sem evidência não trava nada. Confira '
          '`oracle_rfc_status` e grave um resumo no blackboard (key "findings_summary").',
      'rfcConsolidateTitle': 'Sua missão: CONSOLIDAR a rodada e planejar',
      'rfcConsolidateBody':
          'Pegue o `rfc_id` no blackboard e leia a RFC com `oracle_rfc_get`. Trate cada achado '
          'aberto: resolva com `oracle_rfc_resolve` (accepted/rejected/deferred, com motivo) '
          'e, quando os aceitos mudarem a spec, consolide uma nova versão com '
          '`oracle_rfc_revise`. Depois escreva o PLANO DE IMPLEMENTAÇÃO atualizado no '
          'blackboard (`oracle_flow_context_put` key "plan") — objetivo, passos e arquivos. '
          'O portão de rodadas decide se abre nova rodada ou conclui.',
    },
    'en': {
      'title': 'Loop Engineering — step',
      'mission':
          'You are ONE step of an automated multi-agent development run (Oracle AI Loop '
          'Engineering). A deterministic runner drives the process graph; your job is ONLY '
          'this step. Do it well, record your results, and finish — the runner verifies '
          'your work and advances the flow.',
      'step': 'Step',
      'role': 'Role',
      'iteration': 'Iteration',
      'iterationRetry':
          'the previous attempt FAILED verification; fix it (see the feedback below)',
      'workspace': 'Workspace',
      'workspaceBranch': 'the current working directory, on branch',
      'workspaceRules':
          'Work ONLY here; commit your changes with git when you finish (one writer per '
          'branch — you).',
      'workspaceCwd': 'the current working directory. Work ONLY here.',
      'taskTitle': 'Task',
      'instructionsTitle': 'Instructions for this step',
      'rulesTitle': 'Project rules (you MUST follow these)',
      'rulesFooter':
          'Full text: `oracle_rule_search` / `oracle_rules_for_task`. A [required] rule is '
          'non-negotiable.',
      'skillsTitle': 'Skills to load FIRST (Oracle skill library)',
      'skillsIntro':
          'Before working, load each with `oracle_skill_get` and follow it:',
      'blackboardTitle':
          'Shared run context (the blackboard — written by earlier steps)',
      'reportsTitle': 'Reports from earlier steps',
      'artifactsTitle': 'Artifacts produced so far',
      'exitTitle': 'Exit criteria',
      'exitIntro':
          'After you finish, the RUNNER runs these in the workspace — they must pass. Run '
          'them yourself before reporting, but do NOT weaken tests or checks to make them '
          'pass:',
      'feedbackTitle': 'Verifier feedback from the FAILED previous attempt',
      'feedbackFooter': 'Fix the root cause of these failures first.',
      'protocolTitle': 'Protocol (Oracle MCP tools — do these in order)',
      'protocolWarn':
          '⚠ MANDATORY: the step ONLY counts as done once you call '
          '`oracle_flow_step_report`. Without that call the runner marks the attempt '
          'FAILED and ALL your work is discarded and redone — a total waste. Reserve '
          'your final minutes for the report, ALWAYS, even if time runs short or the '
          'work is partial (report the partial).',
      'p1': 'START by calling',
      'p1b':
          'it returns the live task, blackboard, prior reports and artifacts.',
      'p2': 'Do the work of this step. Nothing outside its scope.',
      'p3': 'Share state future steps will need with',
      'p3b':
          'e.g. `plan`, `rfc_id`, `findings_summary`, or `verdict` when your role is to decide a route.',
      'p4': 'Register concrete outputs with',
      'p5': 'FINISH by calling',
      'p5b':
          'with a concise summary of what you did, status "done" (or "blocked" + '
          'openQuestions if you truly cannot proceed — a human will be asked), outputs '
          'and filesTouched.',
      'p5token':
          'IMPORTANT: pass the claimToken LITERALLY as shown above — without it the '
          'report is rejected ("Invalid or stale step claim token"). If you lose the '
          'value, recover it from `oracle_flow_step_context` (field runStep.claimToken).',
      'mcpRetry':
          'TRANSIENT HOST FAILURE: if an Oracle call returns "user cancelled MCP tool '
          'call" (or any "cancelled" variant), it was NOT you and NOT the user — it is an '
          'intermittent cancellation by the host itself. RETRY the SAME call (up to 3 '
          'times; it usually succeeds right after) before treating it as a blocker.',
      'rules':
          'Rules: never claim success you did not verify; never delete or weaken tests to '
          'satisfy the exit criteria; the runner decides pass/fail OUTSIDE of you. If '
          'information is missing, prefer "blocked" with a precise question over guessing.',
      'orchTitle':
          'Your mission: PLAN (you are the orchestrator, not the executor)',
      'orchBody':
          'The RUNNER manages the flow — the next steps will be launched automatically with '
          'their own agents. Your role is ONLY to plan: understand the task (read the code '
          'just enough to diagnose), and write to the blackboard (`oracle_flow_context_put`) '
          'the key "plan" with: cause/diagnosis, implementation steps and an objective brief '
          'for each following step. Do NOT implement, do NOT edit code, do NOT commit in '
          'this step. Be fast — minutes, not hours.',
      'decisionTitle': 'Your mission: DECIDE the route (decision node)',
      'decisionBody':
          'You are a DECISION node: evaluate EXACTLY what this step\'s instructions ask '
          '(run a test, check a criterion, inspect a result) and pick ONE path. Write '
          'your choice to the blackboard with `oracle_flow_context_put` key "verdict", '
          'using the EXACT value of one of the options listed under "Verdict" below — '
          'the runner routes the flow on that value. Do NOT implement fixes or do work '
          'beyond the evaluation; just gather the evidence, decide, and explain why in '
          'your report.',
      'verdictTitle': 'Verdict (route of the next step)',
      'verdictIntro':
          'This node has VERDICT routes. Each option below carries the instruction of WHEN '
          'to take it — evaluate the outcome of your work against those instructions and, '
          'before finishing, write to the blackboard (`oracle_flow_context_put`) the key '
          '"verdict" with EXACTLY one of these values (no variations, no extra text):',
      'verdictFooter':
          'The runner reads that value and follows the matching connection. Any other '
          'value drops the flow to the default connection (or fails) — copy the value '
          'literally.',
      'rfcCreateTitle': 'Your mission: CREATE the RFC for this task',
      'rfcCreateBody':
          'Publish the technical specification as a sectioned RFC with `oracle_rfc_open` '
          '(projectId from the brief; sections with key/content, marking the mandatory ones '
          'required=true — e.g. context, problem, business_rules, data_model, '
          'acceptance_criteria). Base the sections on the task and the blackboard plan. '
          'Then write the id to the blackboard (`oracle_flow_context_put` key "rfc_id") and '
          'register the artifact (`oracle_flow_artifact_add` kind "rfc", locator = id).',
      'rfcReviewTitle': 'Your mission: REVIEW the RFC',
      'rfcReviewBody':
          'Take `rfc_id` from the blackboard (or `oracle_rfc_list_open`), read it with '
          '`oracle_rfc_get` and post STRUCTURED findings with `oracle_rfc_comment` — every '
          'gap/inconsistency/bug/blocker requires a proposedSolution. Ground each finding '
          'with `oracle_rfc_evidence_add` citing a real Oracle entity (by id) or an existing '
          'file+excerpt — an unevidenced finding gates nothing. Check `oracle_rfc_status` '
          'and write a summary to the blackboard (key "findings_summary").',
      'rfcConsolidateTitle': 'Your mission: CONSOLIDATE the round and plan',
      'rfcConsolidateBody':
          'Take `rfc_id` from the blackboard and read the RFC with `oracle_rfc_get`. Handle '
          'every open finding: resolve it with `oracle_rfc_resolve` (accepted/rejected/'
          'deferred, with a reason) and, when accepted ones change the spec, consolidate a '
          'new version with `oracle_rfc_revise`. Then write the updated IMPLEMENTATION PLAN '
          'to the blackboard (`oracle_flow_context_put` key "plan") — goal, steps and files. '
          'The round gate decides whether to open a new round or conclude.',
    },
  };

  /// Compresses a blackboard value to a single prompt line.
  static String _compact(String json, [int max = 300]) {
    final s = json.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.length <= max ? s : '${s.substring(0, max)}…';
  }

  /// One-line summary of a prior step report ("summary" field when present).
  static String? _reportSummary(String? reportJson) {
    if (reportJson == null || reportJson.trim().isEmpty) return null;
    try {
      final j = jsonDecode(reportJson);
      if (j is Map && j['summary'] is String) {
        return _compact(j['summary'] as String, 400);
      }
    } catch (_) {
      /* raw */
    }
    return _compact(reportJson, 200);
  }

  /// Skill keys attached to the step (`config.skills` in the step's config).
  static List<String> _stepSkills(String configJson) {
    try {
      final j = jsonDecode(configJson);
      if (j is Map && j['skills'] is List) {
        return (j['skills'] as List)
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
    } catch (_) {
      /* none */
    }
    return const [];
  }

  /// Tags attached to the step (`config.tags`) — emitted as slash commands.
  static List<String> _stepTags(String configJson) {
    try {
      final j = jsonDecode(configJson);
      if (j is Map && j['tags'] is List) {
        return (j['tags'] as List)
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
    } catch (_) {
      /* none */
    }
    return const [];
  }

  static List<String> _exitCommands(String exitCriteriaJson) {
    try {
      final decoded = jsonDecode(exitCriteriaJson);
      if (decoded is Map && decoded['commands'] is List) {
        return (decoded['commands'] as List).map((e) => e.toString()).toList();
      }
    } catch (_) {
      /* no criteria */
    }
    return const [];
  }
}
