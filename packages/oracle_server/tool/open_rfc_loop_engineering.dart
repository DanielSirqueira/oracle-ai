// One-shot tool: publishes the Loop Engineering (v2.2.0) implementation as an RFC
// in the Oracle RFC engine and posts Claude Fable's evidence-grounded review.
//
// Run from the repo root (connects to the live Oracle DB; local embedder so no
// network is needed):
//   dart run packages/oracle_server/tool/open_rfc_loop_engineering.dart
import 'dart:io';

import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';
import 'package:oracle_server/oracle_server.dart';

const _reviewer = 'claude-fable';

/// Whitespace-normalized substring check — the same rule the MCP evidence tool
/// uses to decide a file citation RESOLVES (and thus verifies the finding).
bool _fileResolves(String locator, String excerpt) {
  final file = File(locator);
  if (!file.existsSync()) return false;
  String norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return norm(file.readAsStringSync()).contains(norm(excerpt));
}

Future<void> main() async {
  // DB connection comes entirely from .env (cwd, else next to the executable) —
  // point it at your live Oracle (e.g. the docker oracle-postgres on port 5435).
  // Only the embedder is forced to the offline local provider so no network /
  // API key is needed to publish the RFC.
  final exeEnv = '${File(Platform.resolvedExecutable).parent.path}'
      '${Platform.pathSeparator}.env';
  final env = Map<String, String>.of(
      loadEnv(path: File('.env').existsSync() ? '.env' : exeEnv))
    ..['ORACLE_EMBEDDING_PROVIDER'] = 'local'
    ..['ORACLE_EMBEDDING_DIM'] = '1024';
  stdout.writeln('DB: ${env['ORACLE_DB_HOST']}:${env['ORACLE_DB_PORT']}'
      '/${env['ORACLE_DB_NAME']} (user ${env['ORACLE_DB_USER']})');

  final database = await Bootstrap.fromEnv(env).start(
    ensureDatabase: false,
    allowSeed: false,
  );

  try {
    // Resolve the project for this repo (get-or-create by git root).
    final projectResult =
        await injector.get<ResolveProjectUsecase>()(Directory.current.path);
    if (projectResult.isError()) {
      stderr.writeln('project resolve failed: '
          '${projectResult.exceptionOrNull()!.errorMessage}');
      exitCode = 1;
      return;
    }
    final project = projectResult.getOrThrow();
    stdout.writeln('project: ${project.name.value} (${project.id.value})');

    // ── 1) Open the RFC (sectioned spec of everything built) ──────────────
    final rfc = RfcEntity(
      id: const IdVO.empty(),
      projectId: project.id,
      title: const TextVO('Loop Engineering (v2.2.0) — implementação para revisão'),
      rfcType: 'fullstack',
      authorAgent: _reviewer,
    );
    const version = RfcVersionEntity(
      id: IdVO.empty(),
      rfcId: IdVO.empty(),
      versionNo: 1,
      summary: TextVO(
        'Loop Engineering v2.2.0: hub de flows de desenvolvimento multiagente no '
        'Oracle. Entregue a migração 001_flows (9 tabelas), o slice DDD flow em '
        'oracle_memory, 15 tools MCP oracle_task_*/oracle_flow_*, e o Flow Runner '
        'determinístico (oracle_ai flow-worker). A auto-revisão inicial (Claude Fable) '
        'achou 8 pontos; 5 foram CORRIGIDOS na fonte antes desta publicação (report '
        '"blocked" honrado + report preservado; orçamento de token imposto no boundary; '
        'flow_run_steps.session_id preenchido best-effort; resume de gate sem worktree; '
        'jsonb robusto; CHECK de priority 0..100). A rodada 1 traz os 4 achados residuais.',
      ),
      authorAgent: _reviewer,
    );

    final sections = <RfcSectionEntity>[
      _section('context', true, 'covered',
          'Loop Engineering (termo do Addy Osmani, jun/2026) = projetar o sistema que '
          'prompta/verifica/lembra/re-executa agentes. O Oracle vira o hub (blackboard) '
          'entre agentes heterogêneos: processos estilo n8n encadeiam loops por etapa '
          '(RFC → dev → docs → PR). Oracle NÃO é agente; o orquestrador é um agente '
          'configurável; uma task aciona o fluxo. Ver docs/loop-engineering-plan.md.'),
      _section('scope', false, 'covered',
          'Fase 1 entregue: schema + slice + tools MCP + Flow Runner determinístico '
          '(claude-code/codex/gemini/cursor headless). Fora de escopo (Fases 2–3): '
          'telas do Studio, kind rfc_review nativo, ligação session_id, paralelismo, '
          'triggers.'),
      _section('architecture', true, 'covered',
          'Híbrido: runner determinístico (oracle_server/lib/src/flow_runner/, sem LLM) '
          'executa o grafo; o orquestrador-agente é invocado por etapa. Slice DDD flow '
          'em oracle_memory (domain/infra/external), FlowModule registrado no bootstrap '
          '(14 módulos). MCP é pull-only, então o runner é obrigatório para lançar os '
          'agentes. Ver docs/architecture.md §Flow Runner.'),
      _section('data_model', true, 'covered',
          'Migração v2.2.0/001_flows (4 arquivos SQL, 9 tabelas): tasks, flows, '
          'flow_steps, flow_edges, flow_runs, flow_run_steps, flow_run_context, '
          'flow_artifacts, flow_run_events. Convenções da casa (uuid PK, owner CHECK, '
          'is_latest/supersedes, jsonb, HNSW+GIN). Nenhuma tabela existente alterada; '
          'seams por FK novas (tasks.rfc_id→rfcs, flow_run_steps.session_id→sessions).'),
      _section('functional_reqs', false, 'covered',
          '15 tools MCP: oracle_task_{create,list,update}; oracle_flow_{save,list,get}; '
          'oracle_flow_run_{start,status,list,control}; oracle_flow_{gate_decide,'
          'step_context,context_put,artifact_add,step_report}. O agente de uma etapa usa '
          '3 no caminho feliz: step_context → trabalho → step_report.'),
      _section('flows', false, 'covered',
          'Flow Runner: claim FOR UPDATE SKIP LOCKED + lease/heartbeat; git worktree por '
          'run; travessia do grafo (arestas success/failure/verdict/always); inner loop '
          'por etapa com verificador FORA do agente; human_gate → awaiting_human com '
          'retomada; kinds agent/orchestrator/rfc_review/command/human_gate.'),
      _section('security', false, 'thin',
          'Menor privilégio por etapa (permissions) e token de claim por etapa (D8) '
          'existem no schema, mas a imposição server-side por etapa ainda é parcial '
          '(Fase 2). O verificador roda comandos com runInShell.'),
      _section('observability', false, 'covered',
          'flow_run_events (timeline append-only) grava estado, verificador, decisão, '
          'gate e orçamento. Cada etapa agora linka a sessão capturada '
          '(flow_run_steps.session_id) best-effort, resolvendo o id externo do agente '
          'via resolveSessionId (sujeito à corrida com a captura assíncrona dos hooks).'),
      _section('tests', true, 'thin',
          'Sem testes automatizados — consistente com o repo (test/ vazio, sem mocking '
          'nem harness de DB; o slice rfc também não tem). Verificação feita: dart '
          'analyze limpo em todo o código novo; binário compila e roda; migração '
          'descoberta/embarcada. Sem cobertura end-to-end (precisa de Postgres + CLIs).'),
      _section('migration', false, 'covered',
          'v2.2.0/001_flows aditiva/forward-only; embedded_migrations regenerado '
          '(dart run packages/oracle_server/tool/gen_embedded_migrations.dart). 11 '
          'migrações descobertas.'),
      _section('acceptance_criteria', true, 'covered',
          'Definir um flow, criar uma task e acioná-la roda o ciclo linear de ponta a '
          'ponta; verificador fora do agente; um escritor por branch; gate humano '
          'funcional; toda transição na timeline.'),
      _section('risks', true, 'covered',
          'Custo/loops (iterações/timeout + orçamento de token imposto no boundary, '
          'porém a contagem de tokens é best-effort por parsing do harness); reward '
          'hacking (verificador fora do agente); fragilidade dos CLIs headless (adapters '
          'isolados); context rot (blackboard estruturado). Ver docs/loop-engineering-plan.md §10.'),
      _section('open_decisions', false, 'covered',
          'jsonb representado como String de JSON cru (equality trivial); worker usa cwd '
          'como raiz do repo (resolver repo_path do projeto é Fase 2); rfc_review roda '
          'via launcher genérico até a integração nativa.'),
    ];

    final openResult =
        await injector.get<OpenRfcUsecase>()(rfc, version, sections);
    if (openResult.isError()) {
      stderr.writeln('open failed: ${openResult.exceptionOrNull()!.errorMessage}');
      exitCode = 1;
      return;
    }
    final opened = openResult.getOrThrow();
    stdout.writeln('RFC aberta: ${opened.id.value} (status ${opened.status.code})');

    // Fetch the bundle to anchor findings to real section ids.
    final bundleResult = await injector.get<GetRfcUsecase>()(opened.id);
    final bundle = bundleResult.getOrThrow();
    final versionId = bundle.version!.id;
    final sectionIdByKey = {
      for (final s in bundle.sections) s.sectionKey: s.id,
    };

    // ── 2) Start review round 1 ───────────────────────────────────────────
    await injector.get<StartRoundUsecase>()(RfcRoundEntity(
      id: const IdVO.empty(),
      rfcId: opened.id,
      versionId: versionId,
      roundNo: 1,
      participants: const [_reviewer],
    ));

    // ── 3) Claude Fable's review — findings grounded in verifiable evidence ─
    final findings = _claudeFableFindings();
    var verifiedCount = 0;
    for (final f in findings) {
      final comment = RfcCommentEntity(
        id: const IdVO.empty(),
        rfcId: opened.id,
        versionId: versionId,
        sectionId: sectionIdByKey[f.anchorSection],
        authorAgent: _reviewer,
        reviewerRole: f.role,
        type: f.type,
        severity: f.severity,
        area: f.area,
        problem: TextVO(f.problem),
        rationale: TextVO(f.rationale),
        impact: TextVO(f.impact),
        proposedSolution: TextVO(f.solution),
        confidence: f.confidence,
        roundNo: 1,
      );
      final commentResult = await injector.get<AddCommentUsecase>()(comment);
      if (commentResult.isError()) {
        stderr.writeln('  ! comment failed (${f.short}): '
            '${commentResult.exceptionOrNull()!.errorMessage}');
        continue;
      }
      final saved = commentResult.getOrThrow();

      final resolves = _fileResolves(f.locator, f.excerpt);
      final evResult = await injector.get<AddEvidenceUsecase>()(RfcEvidenceEntity(
        id: const IdVO.empty(),
        commentId: saved.id,
        kind: f.evidenceKind,
        refKind: 'file',
        locator: f.locator,
        excerpt: f.excerpt,
        resolved: resolves,
        resolvedAt: resolves ? DateTime.now() : null,
      ));
      final verified = evResult.isSuccess() && resolves;
      if (verified) verifiedCount++;
      stdout.writeln('  [${f.severity.code}] ${f.short} '
          '— evidência ${resolves ? 'RESOLVE ✓' : 'NÃO resolve'} '
          '(${f.locator})');
    }

    // ── 4) Close the round + print the readiness snapshot ─────────────────
    final closed =
        await injector.get<CloseRoundUsecase>()(rfcId: opened.id, roundNo: 1);
    final novelty = closed.isSuccess() ? closed.getOrThrow().noveltyScore : null;

    final statusResult = await injector.get<RfcStatusUsecase>()(opened.id);
    final s = statusResult.getOrThrow();
    stdout
      ..writeln('')
      ..writeln('=== RFC ${opened.id.value} — round 1 fechado ===')
      ..writeln('findings: ${findings.length} postados, $verifiedCount verificados')
      ..writeln('novelty: ${novelty?.toStringAsFixed(2) ?? 'n/a'}')
      ..writeln('blockingCriticals(verificados): ${s.blockingCriticals} | '
          'openCriticals: ${s.openCriticals} | openMajors: ${s.openMajors}')
      ..writeln('coverage required: ${s.coveredRequired}/${s.requiredSections} '
          '| checklistComplete: ${s.checklistComplete}')
      ..writeln('=> RFC pronta para revisão no Studio (console RFC) / '
          'oracle_rfc_get id=${opened.id.value}');
  } finally {
    await database.dispose();
  }
}

RfcSectionEntity _section(String key, bool required, String coverage, String content) =>
    RfcSectionEntity(
      id: const IdVO.empty(),
      versionId: const IdVO.empty(),
      sectionKey: key,
      content: TextVO(content),
      required: required,
      coverage: coverage,
    );

class _Finding {
  final String short;
  final RfcCommentType type;
  final RfcSeverity severity;
  final String role;
  final String area;
  final String anchorSection;
  final double confidence;
  final String problem;
  final String rationale;
  final String impact;
  final String solution;
  final String evidenceKind;
  final String locator;
  final String excerpt;
  const _Finding({
    required this.short,
    required this.type,
    required this.severity,
    required this.role,
    required this.area,
    required this.anchorSection,
    required this.confidence,
    required this.problem,
    required this.rationale,
    required this.impact,
    required this.solution,
    required this.evidenceKind,
    required this.locator,
    required this.excerpt,
  });
}

List<_Finding> _claudeFableFindings() => const [
      _Finding(
        short: 'Enforcement de orçamento de token é best-effort (parsing por harness)',
        type: RfcCommentType.risk,
        severity: RfcSeverity.minor,
        role: 'critic',
        area: 'infra',
        anchorSection: 'risks',
        confidence: 0.8,
        problem:
            'O orçamento de token agora é imposto no boundary de etapa (stall ao exceder '
            'budgets.maxTotalTokens), mas a contagem de tokens vem de parsing best-effort da saída '
            'do harness (claude --output-format json; codex JSONL). Para harnesses/shapes não '
            'reconhecidos o delta é 0, então o teto pode nunca disparar.',
        rationale:
            '_parseUsage é declaradamente best-effort e retorna 0 quando a forma é desconhecida; o '
            'enforcement só é confiável para os harnesses cujo formato é parseado.',
        impact:
            'Um flow rodando com um harness não coberto (ou mudança de formato do CLI) pode passar do '
            'orçamento sem stall — o teto de custo é parcial.',
        solution:
            'Preferir contar tokens pela sessão capturada (sessions.total_tokens somado pelos hooks) '
            'em vez do stdout do agente; adicionar teste de contrato por adapter.',
        evidenceKind: 'code',
        locator: 'packages/oracle_server/lib/src/flow_runner/step_launcher.dart',
        excerpt: 'Best-effort extraction of token usage',
      ),
      _Finding(
        short: 'Link de session_id é best-effort e sujeito a corrida',
        type: RfcCommentType.risk,
        severity: RfcSeverity.info,
        role: 'architect',
        area: 'data',
        anchorSection: 'observability',
        confidence: 0.8,
        problem:
            'flow_run_steps.session_id agora é preenchido resolvendo o id externo do agente via '
            'resolveSessionId, mas a captura da sessão pelos hooks é assíncrona: se a linha sessions '
            'ainda não existir quando o worker resolve (logo após o exit do agente), o FK fica null.',
        rationale:
            'resolveSessionId retorna null quando não há linha de sessão ainda; a resolução também '
            'depende do id externo bater com o external_id capturado.',
        impact:
            'Algumas etapas podem ficar sem o link da sessão (drill-down do Studio incompleto), de '
            'forma não-determinística.',
        solution:
            'Retentar a resolução com backoff, ou setar o FK a partir do próprio hook (que conhece a '
            'etapa via um id de correlação injetado no lançamento).',
        evidenceKind: 'code',
        locator:
            'packages/oracle_memory/lib/src/flow/infra/datasources/flow_datasource.dart',
        excerpt: 'Null when no session row',
      ),
      _Finding(
        short: 'kind rfc_review é um no-op idêntico a agent',
        type: RfcCommentType.inconsistency,
        severity: RfcSeverity.minor,
        role: 'architect',
        area: 'infra',
        anchorSection: 'open_decisions',
        confidence: 0.85,
        problem:
            'flow_steps.kind anuncia rfc_review como executor de primeira classe, mas o runner o roteia '
            'pelo launcher de agente genérico, idêntico a agent; não há orquestração do motor RFC '
            '(open/round/status).',
        rationale:
            'No _runStep só humanGate e command têm ramo próprio; todo o resto (inclusive rfcReview) cai '
            'no loop de agente.',
        impact:
            'Um autor de flow que escolhe rfc_review recebe um passo de agente comum — comportamento '
            'enganoso frente ao contrato do enum.',
        solution:
            'Implementar rfc_review (dirigir oracle_rfc_* + usar oracle_rfc_status como verificador) ou, '
            'até a Fase 2, rejeitar/sinalizar o kind explicitamente e documentar.',
        evidenceKind: 'code',
        locator: 'packages/oracle_server/lib/src/flow_runner/flow_worker.dart',
        excerpt: 'Agent / orchestrator / rfc_review — the inner loop.',
      ),
      _Finding(
        short: 'Verificador roda comandos com runInShell e comando como argv[0]',
        type: RfcCommentType.nit,
        severity: RfcSeverity.info,
        role: 'security',
        area: 'sec',
        anchorSection: 'security',
        confidence: 0.7,
        problem:
            'O verificador executa Process.run(cmd, const [], runInShell: true), passando a string '
            'inteira como executável; funciona via shell, mas acopla a verificação ao parsing/quoting '
            'do shell e cria uma superfície de shell (comandos são de autoria do dev, risco baixo).',
        rationale:
            'runInShell com comando composto delega ao cmd.exe/sh; portabilidade e segurança ficam '
            'dependentes do shell.',
        impact:
            'Fragilidade de portabilidade/quoting; superfície de shell (baixa, pois exit_criteria é '
            'controlado pelo autor do flow).',
        solution:
            'Separar programa + args, ou documentar explicitamente que exit_criteria roda num shell.',
        evidenceKind: 'code',
        locator: 'packages/oracle_server/lib/src/flow_runner/verifier.dart',
        excerpt: 'runInShell: true,',
      ),
    ];
