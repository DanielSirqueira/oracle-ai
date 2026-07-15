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

  /// Optional shared secret (`ORACLE_HOOK_TOKEN`). When set, every `/hook` POST
  /// must carry `Authorization: Bearer <token>`. Since the endpoint can write and
  /// read long-term memory, set this whenever the port is not strictly loopback.
  final String? hookToken;

  /// Hard cap on a hook request body. A hook payload is small; anything larger is
  /// rejected before buffering, so one giant POST can't OOM the shared daemon.
  static const _maxBodyBytes = 4 * 1024 * 1024;

  HttpServer? _server;

  HooksServer({
    this.host = '127.0.0.1',
    this.port = 47500,
    RecallService recall = const RecallService(),
    bool? metricsEnabled,
    String? metricsLabel,
    String? hookToken,
  })  : _recall = recall,
        metricsEnabled = metricsEnabled ??
            (Platform.environment['ORACLE_METRICS_ENABLED'] ?? 'true').toLowerCase() == 'true',
        metricsLabel = metricsLabel ?? (Platform.environment['ORACLE_METRICS_LABEL'] ?? 'default'),
        hookToken = hookToken ??
            (Platform.environment['ORACLE_HOOK_TOKEN']?.trim().isNotEmpty ?? false
                ? Platform.environment['ORACLE_HOOK_TOKEN']!.trim()
                : null);

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

  /// Reads the request body bytes, aborting (returns null) once they exceed
  /// [_maxBodyBytes] — bounds even chunked/unknown-length uploads. Decoding is
  /// left to the caller so a non-UTF-8 body surfaces as a 400, not silent U+FFFD.
  Future<List<int>?> _readBounded(Request request) async {
    final bytes = <int>[];
    await for (final chunk in request.read()) {
      bytes.addAll(chunk);
      if (bytes.length > _maxBodyBytes) return null;
    }
    return bytes;
  }

  /// Length-independent string compare, to avoid leaking the token via timing.
  static bool _secureEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<Response> _handleHook(Request request) async {
    // Auth: when a token is configured, require it. Constant-work compare.
    if (hookToken != null) {
      final auth = request.headers['authorization'] ?? '';
      if (!_secureEquals(auth, 'Bearer $hookToken')) {
        return Response.forbidden('unauthorized');
      }
    }

    // Reject oversized bodies before buffering the whole thing into memory.
    final declared = request.contentLength;
    if (declared != null && declared > _maxBodyBytes) {
      return Response(413, body: 'payload too large');
    }

    // Read (bounded) + decode + parse under ONE guard: a mid-body abort, non-UTF-8
    // bytes, or malformed JSON must return 400 — never a 500 stack trace in the
    // daemon log, and never lossily-decoded text persisted into long-term capture.
    Map<String, dynamic> p;
    try {
      final bytes = await _readBounded(request);
      if (bytes == null) return Response(413, body: 'payload too large');
      p = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      return Response.badRequest(body: 'invalid request body');
    }

    p = _normalize(p);
    final rawEvent = '${p['hook_event_name'] ?? p['event'] ?? ''}';
    final event = _canonicalEvent(rawEvent);
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

  /// Canonicalizes an incoming hook event name to the ones the receiver acts on.
  /// Agents name the same lifecycle moment differently — Cursor uses camelCase
  /// (`sessionStart`, `beforeSubmitPrompt`, `stop`, `after*`), Gemini uses
  /// `AfterTool`, Claude Code / Codex / VS Code use PascalCase. Unknown names
  /// pass through (→ default → 200 no-op). Legacy snake_case names are NOT
  /// remapped here — they keep their existing capture-only behavior below.
  static String _canonicalEvent(String raw) => switch (raw) {
        'sessionStart' => 'SessionStart',
        'beforeSubmitPrompt' => 'UserPromptSubmit',
        'stop' => 'Stop',
        'postToolUse' ||
        'afterFileEdit' ||
        'afterShellExecution' ||
        'afterMCPExecution' ||
        'AfterTool' =>
          'PostToolUse',
        'postCompact' => 'PostCompact',
        'sessionEnd' => 'SessionEnd',
        _ => raw,
      };

  /// Fills canonical payload keys from agent-specific aliases so the capture path
  /// (which reads `cwd`, `session_id`, `tool_name`, `tool_response`,
  /// `last_assistant_message`) works no matter which agent sent the event.
  static Map<String, dynamic> _normalize(Map<String, dynamic> p) {
    // Working directory — Cursor sends `workspace_roots: [..]` instead of `cwd`.
    if ('${p['cwd'] ?? ''}'.trim().isEmpty) {
      final roots = p['workspace_roots'];
      p['cwd'] = (roots is List && roots.isNotEmpty)
          ? '${roots.first}'
          : (p['project_dir'] ?? p['worktree'] ?? '');
    }
    // Session identity — Cursor `conversation_id`, Codex notify `thread-id`.
    p['session_id'] ??= p['conversation_id'] ??
        p['thread_id'] ??
        p['thread-id'] ??
        p['threadId'] ??
        p['externalSessionId'];
    // Tool result — Cursor `tool_output`/`result_json`/`output`.
    p['tool_response'] ??= p['tool_output'] ?? p['result_json'] ?? p['output'];
    // Final assistant text — Codex notify hyphenates it.
    p['last_assistant_message'] ??= p['last-assistant-message'];

    // Tool events with no tool name (Cursor shell/file hooks): synthesize one so
    // the captured message reads sensibly, and back-fill a response body.
    final raw = '${p['hook_event_name'] ?? p['event'] ?? ''}';
    if ('${p['tool_name'] ?? ''}'.trim().isEmpty) {
      p['tool_name'] = switch (raw) {
        'afterShellExecution' => 'shell',
        'afterFileEdit' => 'edit',
        _ => p['tool_name'],
      };
    }
    if ('${p['tool_response'] ?? ''}'.trim().isEmpty) {
      if (raw == 'afterShellExecution') p['tool_response'] = p['command'];
      if (raw == 'afterFileEdit') p['tool_response'] = p['file_path'];
    }
    return p;
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
        final usage = lastTurnUsage('${p['transcript_path'] ?? ''}');
        await _recordMetric(projectId, p, usage: usage, turns: 1);
        // Roll the turn's tokens into the session's aggregate so the dashboard can
        // show tokens per session and roll them up to module/project/organization.
        if (usage.input + usage.output > 0) {
          final session = await _ensureSession(projectId, p, cwd);
          if (session != null) {
            await injector
                .get<CaptureRepository>()
                .addSessionTokens(session.id, input: usage.input, output: usage.output);
          }
        }
      case 'PostToolUse':
        final name = '${p['tool_name'] ?? 'tool'}';
        final resp = _truncate('${p['tool_response'] ?? ''}', 2000);
        await _captureMessage(projectId, p, cwd, MessageRole.tool, '$name: $resp');
        await _recordMetric(projectId, p, toolUses: 1);
      case 'PostCompact':
        await _recordMetric(projectId, p, compactions: 1);
        final summary = '${p['compact_summary'] ?? ''}';
        if (summary.trim().isNotEmpty) {
          // Key the summary by session so repeated compactions of the same
          // session update ONE memory instead of piling up "Session summary
          // (compacted)" duplicates. Keyless fallback when the session id is
          // unknown (keeps the old append-only behavior rather than collapsing
          // unrelated sessions under an empty key).
          final sessionId = '${p['session_id'] ?? p['externalSessionId'] ?? ''}'.trim();
          await injector.get<SaveMemoryUsecase>()(MemoryEntity(
            id: const IdVO.empty(),
            projectId: projectId,
            key: sessionId.isEmpty ? null : 'session-compaction:$sessionId',
            tier: MemoryTier.parse('episodic'),
            kind: MemoryKind.parse('fact'),
            title: const TextVO('Session summary (compacted)'),
            body: TextVO(summary),
            // Low importance: a running compaction summary is context, not a
            // durable learning — eligible for decay if never accessed.
            importance: 0.2,
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
