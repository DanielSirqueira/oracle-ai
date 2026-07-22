import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';
import 'package:oracle_server/src/flow_runner/prompt_composer.dart';
import 'package:test/test.dart';

void main() {
  const run = FlowRunEntity(
    id: IdVO('00000000-0000-0000-0000-000000000001'),
    flowId: IdVO('00000000-0000-0000-0000-000000000002'),
  );
  const runStepId = IdVO('00000000-0000-0000-0000-000000000003');

  FlowStepEntity step({
    FlowStepKind kind = FlowStepKind.agent,
    String config = '{}',
    String? outputSchema,
  }) => FlowStepEntity(
    id: const IdVO('00000000-0000-0000-0000-000000000004'),
    flowId: run.flowId,
    stepKey: 'etapa',
    kind: kind,
    config: config,
    outputSchema: outputSchema,
  );

  String compose(
    FlowStepEntity s, {
    List<VerdictOption> verdicts = const [],
    String language = 'pt',
    String? claimToken,
  }) => PromptComposer().compose(
    run: run,
    step: s,
    runStepId: runStepId,
    iteration: 1,
    claimToken: claimToken,
    verdictOptions: verdicts,
    language: language,
  );

  test('tags become slash-command lines at the very top of the prompt', () {
    final prompt = compose(step(config: '{"tags": ["review", "/security"]}'));
    expect(prompt, startsWith('/review\n/security\n\n'));
  });

  test('no tags → no slash prefix', () {
    final prompt = compose(step());
    expect(prompt.startsWith('/'), isFalse);
    expect(prompt, contains('Loop Engineering'));
  });

  test('verdict options are listed verbatim, with per-route instructions', () {
    final prompt = compose(
      step(kind: FlowStepKind.decision),
      verdicts: [
        (value: 'aprovado', instruction: 'quando TODOS os testes passarem'),
        (value: 'reprovado', instruction: null),
      ],
    );
    expect(prompt, contains('- `aprovado` — quando TODOS os testes passarem'));
    expect(prompt, contains('- `reprovado`'));
    expect(prompt, contains('Veredito'));
  });

  test('any agent node with verdict edges gets the verdict section', () {
    final prompt = compose(
      step(),
      verdicts: [
        (
          value: 'sem-achados',
          instruction: 'quando o RFC não tiver mais achados',
        ),
        (value: 'com-achados', instruction: 'quando restarem achados abertos'),
      ],
    );
    expect(
      prompt,
      contains('- `sem-achados` — quando o RFC não tiver mais achados'),
    );
    expect(prompt, contains('"verdict"'));
  });

  test('decision mission is included (pt and en)', () {
    expect(compose(step(kind: FlowStepKind.decision)), contains('DECIDIR'));
    expect(
      compose(step(kind: FlowStepKind.decision), language: 'en'),
      contains('DECIDE the route'),
    );
  });

  test('orchestrator mission forbids implementing', () {
    final prompt = compose(step(kind: FlowStepKind.orchestrator));
    expect(prompt, contains('PLANEJAR'));
    expect(prompt, contains('NÃO implemente'));
  });

  test('skills from config are inlined as load-first instructions', () {
    final prompt = compose(step(config: '{"skills": ["deploy-checklist"]}'));
    expect(prompt, contains('deploy-checklist'));
    expect(prompt, contains('oracle_skill_get'));
  });

  test('output schema is an explicit final-report contract', () {
    final prompt = compose(
      step(outputSchema: '{"type":"object","required":["result"]}'),
    );
    expect(prompt, contains('Saída estruturada obrigatória'));
    expect(prompt, contains('"required":["result"]'));
    expect(prompt, contains('`outputs`'));
  });

  test('claim token is inlined literally into the report protocol step', () {
    final prompt = compose(step(), claimToken: 'run-1:3');
    expect(prompt, contains('claimToken: "run-1:3"'));
    expect(prompt, contains('runStep.claimToken'));
    // Without a token the argument (and its warning) must be absent.
    final without = compose(step());
    expect(without.contains('claimToken:'), isFalse);
  });

  test('protocol teaches retrying transient host cancellations', () {
    final pt = compose(step());
    final en = compose(step(), language: 'en');
    expect(pt, contains('user cancelled MCP tool call'));
    expect(pt, contains('REPITA a MESMA chamada'));
    expect(en, contains('user cancelled MCP tool call'));
    expect(en, contains('RETRY the SAME call'));
  });

  test('protocol supports native and programmatic MCP surfaces', () {
    final pt = compose(step());
    final en = compose(step(), language: 'en');
    expect(pt, contains('USE A SUPERFÍCIE MCP DISPONÍVEL'));
    expect(pt, contains('tools.mcp__oracle_ai__oracle_*'));
    expect(pt, contains('Não recuse a etapa'));
    expect(en, contains('USE THE MCP SURFACE AVAILABLE'));
    expect(en, contains('supported programmatic wrapper'));
  });
}
