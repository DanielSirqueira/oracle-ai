import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../recall_service.dart';
import '../repo_root.dart';
import '../transcript_usage.dart';

/// Local HTTP endpoint that speaks Claude Code's **hook protocol** (the `http`
/// hook type POSTs the exact hook-input JSON here and reads JSON back).
///
/// Capture shape (mirrors how the agents themselves work):
/// - A **session** IS the agent's own session — keyed by the payload
///   `session_id` (`external_id`). No status/lifecycle.
/// - Each **UserPromptSubmit** opens a **request** (the user's demand); its text
///   is embedded so past demands are semantically searchable.
/// - **Stop**/**PostToolUse** append **messages** (the agent's work) under the
///   session's latest request — messages belong to a request, not a session.
///
/// Two roles:
/// - **Inject** (`SessionStart`, `UserPromptSubmit`): responds with
///   `{ hookSpecificOutput: { hookEventName, additionalContext } }` so the
///   session identity + recalled memory/rules are added to the model context.
/// - **Capture** (`Stop`, `PostToolUse`, `PostCompact`): writes raw capture
///   fire-and-forget and returns `{}` immediately, never blocking the agent.
///
/// The project is resolved from the payload `cwd`, canonicalized to the git
/// root so subdirectories/worktrees map to one project.
class HooksServer {
  final String host;
  final int port;
  final RecallService _recall;

  /// Measurement harness toggle + experiment tag (defaults from env
  /// `ORACLE_METRICS_ENABLED` / `ORACLE_METRICS_LABEL`). Set the label per run
  /// to A/B compare (e.g. `oracle` vs `baseline`).
  final bool metricsEnabled;
  final String metricsLabel;
  HttpServer? _server;

  HooksServer({
    this.host = '127.0.0.1',
    this.port = 49500,
    RecallService recall = const RecallService(),
    bool? metricsEnabled,
    String? metricsLabel,
  })  : _recall = recall,
        metricsEnabled = metricsEnabled ??
            (Platform.environment['ORACLE_METRICS_ENABLED'] ?? 'true').toLowerCase() == 'true',
        metricsLabel = metricsLabel ?? (Platform.environment['ORACLE_METRICS_LABEL'] ?? 'default');

  Future<void> start() async {
    final router = Router()
      ..get('/health', (Request _) => Response.ok('ok'))
      ..post('/hook', _handleHook);
    _server = await shelf_io.serve(router.call, host, port);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<Response> _handleHook(Request request) async {
    Map<String, dynamic> p;
    try {
      p = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return Response.badRequest(body: 'invalid json');
    }

    final event = '${p['hook_event_name'] ?? p['event'] ?? ''}';
    final cwd = '${p['cwd'] ?? ''}';

    switch (event) {
      case 'SessionStart':
        return _inject('SessionStart', await _sessionStart(p, cwd));
      case 'UserPromptSubmit':
        return _inject('UserPromptSubmit', await _userPromptSubmit(p, cwd));
      case 'Stop':
      case 'PostToolUse':
      case 'PostCompact':
      case 'SessionEnd':
      // legacy event names (pre-Claude-Code-protocol)
      case 'session_start':
      case 'message':
      case 'session_end':
        unawaited(_capture(event, p, cwd).catchError((_) {}));
        return _ok(const {});
      default:
        return _ok(const {});
    }
  }

  // ── inject events (synchronous) ──

  Future<String?> _sessionStart(Map<String, dynamic> p, String cwd) async {
    final projectId = await _resolveProject(cwd);
    if (projectId == null) return null;
    // Ensure the session synchronously so its identity can be injected and so a
    // request opened on the first prompt has a session to hang off.
    final session = await _ensureSession(projectId, p, cwd);
    final brief = await _recall.sessionBrief(projectId);
    return _join(session == null ? null : _sessionHeader(projectId, session), brief);
  }

  Future<String?> _userPromptSubmit(Map<String, dynamic> p, String cwd) async {
    final projectId = await _resolveProject(cwd);
    if (projectId == null) return null;
    final prompt = '${p['prompt'] ?? ''}';
    if (prompt.trim().isEmpty) return null;

    final session = await _ensureSession(projectId, p, cwd);
    if (session == null) return _recall.promptRecall(projectId, prompt);

    // Embed the prompt ONCE: reused for both the request row (searchable demand)
    // and the recall below. Best-effort — a down embedder degrades, never blocks.
    List<double>? vec;
    try {
      vec = await injector.get<Embedder>().embed(prompt);
    } catch (_) {/* keep null */}

    // Open the request (the demand) BEFORE the agent works, so the messages it
    // produces (Stop/PostToolUse) attach to it via latestRequest.
    try {
      await injector.get<CaptureRepository>().openRequest(RequestEntity(
            id: const IdVO.empty(),
            sessionId: session.id,
            userText: TextVO(prompt),
            embedding: vec,
            embeddingModel: vec == null ? null : injector.get<Embedder>().model,
          ));
    } catch (_) {/* never block the prompt on capture */}

    return _recall.promptRecallFor(projectId, vec);
  }

  // ── capture events (fire-and-forget) ──

  Future<void> _capture(String event, Map<String, dynamic> p, String cwd) async {
    final projectId = await _resolveProject(cwd);
    if (projectId == null) return;

    switch (event) {
      case 'Stop':
        await _captureMessage(
            projectId, p, cwd, MessageRole.assistant, '${p['last_assistant_message'] ?? ''}');
        // One Stop = one completed turn; record its token usage from the transcript.
        await _recordMetric(projectId, p,
            usage: lastTurnUsage('${p['transcript_path'] ?? ''}'), turns: 1);
      case 'PostToolUse':
        final name = '${p['tool_name'] ?? 'tool'}';
        final resp = _truncate('${p['tool_response'] ?? ''}', 2000);
        await _captureMessage(projectId, p, cwd, MessageRole.tool, '$name: $resp');
        await _recordMetric(projectId, p, toolUses: 1);
      case 'PostCompact':
        await _recordMetric(projectId, p, compactions: 1);
        final summary = '${p['compact_summary'] ?? ''}';
        if (summary.trim().isNotEmpty) {
          await injector.get<SaveMemoryUsecase>()(MemoryEntity(
            id: const IdVO.empty(),
            projectId: projectId,
            tier: MemoryTier.parse('episodic'),
            kind: MemoryKind.parse('fact'),
            title: const TextVO('Session summary (compacted)'),
            body: TextVO(summary),
          ));
        }
      case 'message': // legacy: a turn-style payload → message under latest request
        await _captureMessage(projectId, p, cwd,
            MessageRole.parse('${p['role'] ?? 'assistant'}'), '${p['content'] ?? ''}');
      case 'session_start': // legacy
        await _ensureSession(projectId, p, cwd);
    }
  }

  /// Append a message under the session's latest request (the demand in flight).
  /// No request yet (e.g. a resumed session whose first event is a Stop) → skip:
  /// messages only make sense as work carrying out a request.
  Future<void> _captureMessage(
    IdVO projectId,
    Map<String, dynamic> p,
    String cwd,
    MessageRole role,
    String content,
  ) async {
    if (content.trim().isEmpty) return;
    final session = await _ensureSession(projectId, p, cwd);
    if (session == null) return;
    final request = (await injector.get<CaptureRepository>().latestRequest(session.id)).getOrNull();
    if (request == null) return;
    await injector.get<CaptureRepository>().appendMessage(MessageEntity(
          id: const IdVO.empty(),
          requestId: request.id,
          role: role,
          content: TextVO(content),
        ));
  }

  String _sessionHeader(IdVO projectId, SessionEntity s) {
    final ext = (s.externalId == null || s.externalId!.isEmpty) ? '(none)' : s.externalId;
    return '# Oracle AI — session\n'
        'Oracle session ${s.id.value} for ${s.agent} session $ext '
        '(projectId ${projectId.value}). Resume this same session id to continue.';
  }

  Future<SessionEntity?> _ensureSession(IdVO projectId, Map<String, dynamic> p, String cwd) async {
    final externalId = '${p['session_id'] ?? p['externalSessionId'] ?? ''}';
    final result = await injector.get<CaptureRepository>().startSession(SessionEntity(
          id: const IdVO.empty(),
          projectId: projectId,
          agent: '${p['agent'] ?? 'claude-code'}',
          externalId: externalId.isEmpty ? null : externalId,
          cwd: cwd.isEmpty ? null : cwd,
        ));
    return result.getOrNull();
  }

  Future<IdVO?> _resolveProject(String cwd) async {
    if (cwd.trim().isEmpty) return null;
    final result = await injector.get<ResolveProjectUsecase>()(repoRootOf(cwd));
    return result.getOrNull()?.id;
  }

  Future<void> _recordMetric(
    IdVO projectId,
    Map<String, dynamic> p, {
    TurnUsage usage = TurnUsage.zero,
    int turns = 0,
    int toolUses = 0,
    int compactions = 0,
  }) async {
    if (!metricsEnabled) return;
    final ext = '${p['session_id'] ?? p['externalSessionId'] ?? ''}';
    if (ext.isEmpty) return;
    await injector.get<AddSessionMetricUsecase>()(MetricDelta(
      projectId: projectId,
      externalId: ext,
      label: metricsLabel,
      inputTokens: usage.input,
      outputTokens: usage.output,
      cacheCreationTokens: usage.cacheCreation,
      cacheReadTokens: usage.cacheRead,
      turns: turns,
      toolUses: toolUses,
      compactions: compactions,
    ));
  }

  // ── responses ──

  Response _inject(String eventName, String? context) {
    if (context == null || context.trim().isEmpty) return _ok(const {});
    return _ok({
      'hookSpecificOutput': {'hookEventName': eventName, 'additionalContext': context},
    });
  }

  Response _ok(Object json) =>
      Response.ok(jsonEncode(json), headers: {'content-type': 'application/json'});

  /// Join two optional context blocks with a blank line, dropping empties.
  static String? _join(String? a, String? b) {
    final parts = [a, b].where((s) => s != null && s.trim().isNotEmpty).cast<String>();
    return parts.isEmpty ? null : parts.join('\n\n');
  }

  static String _truncate(String s, int max) => s.length <= max ? s : '${s.substring(0, max)}…';
}
