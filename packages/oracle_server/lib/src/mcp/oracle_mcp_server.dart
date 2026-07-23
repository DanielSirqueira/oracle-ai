import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart' as mcp;
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';

import '../backup/db_backup_service.dart';
import '../bootstrap.dart' show DbReadyGate;
import '../recall_service.dart';
import '../repo_root.dart';

/// Oracle AI MCP server (stdio). Exposes the tool surface, each tool wired to a
/// use case resolved from the DI container (which must already be committed by
/// the bootstrap).
class OracleMcpServer {
  final String name;
  final String version;

  /// When set, the database is coming up in the BACKGROUND (resilient path):
  /// `initialize` is answered immediately and each tool call first awaits the
  /// gate — returning an actionable error instead of dying when the database
  /// is unreachable (which an MCP host would surface as the fatal
  /// "connection closed: initialize response").
  final DbReadyGate? dbGate;

  OracleMcpServer({this.name = 'oracle-ai', this.version = '0.1.0', this.dbGate});

  /// Standing guidance auto-injected ONCE by the client at connect time (MCP
  /// `instructions` → Claude Code's `mcp_instructions_delta`). Kept STATIC so it
  /// never busts the prompt cache; per-project rules are injected per-session by
  /// the SessionStart hook instead.
  static const instructions = '''
You have a persistent long-term memory bank for this codebase (the oracle_* tools). Use it: recall before you
re-derive, record durable learnings as you go.
- START: call `oracle_session_brief` with your repo path (cwd). It returns the projectId plus a brief (pending
  handoff + required rules + key memories). Reuse that projectId for every other call.
- Before coding, follow the required rules; recall with `oracle_memory_search` / `oracle_rule_search` instead
  of re-deriving context. If the task looks familiar, `oracle_request_search` finds past user demands like it
  (then `oracle_request_messages` shows how they were handled).
- Save durable, non-trivial learnings with `oracle_memory_save` (decision/gotcha/rule/fact) — not transient
  chatter. To avoid duplicates, recall first, and give a recurring memory a stable `key` so re-saving updates
  one memory in place instead of piling up near-duplicates (or pass `supersedes` with the id it replaces).
  Refine rules with `oracle_rule_save` (re-saving the same key supersedes it).
- SKILLS: a centralized, shared skill library (procedural how-to guides) lives here — one copy for every
  agent, no per-agent folders. Before starting a non-trivial kind of task, `oracle_skill_search` with the
  task context; load the winner with `oracle_skill_get` (searches return name+description only — cheap).
  Save reusable know-how with `oracle_skill_save` (stable kebab-case key; omit project/organization for a
  global skill; re-saving the same key updates it).
- RFCs (spec review): before implementing a non-trivial spec, publish it with `oracle_rfc_open` (a SECTIONED
  body: mark required sections + coverage). Reviewing agents find open RFCs with `oracle_rfc_list_open`, read
  with `oracle_rfc_get`, and post STRUCTURED findings with `oracle_rfc_comment` — each grounded (a
  gap/bug/blocker needs a proposedSolution). Back a finding with `oracle_rfc_evidence_add` — evidence must
  RESOLVE (a cited rule/memory/architecture/rfc by id, or a file+excerpt) to verify it; unverified criticals
  don't gate completion. Contest with `oracle_rfc_relate`, settle with `oracle_rfc_resolve`; bracket rounds
  with `oracle_rfc_round_start`/`_round_close` (novelty). Consolidate with `oracle_rfc_revise`; record
  decisions with `oracle_rfc_decide` (humanApproved gates product calls); check `oracle_rfc_status`; then
  `oracle_rfc_finalize` — approves + writes decisions back to memory, or parks in awaiting_human.
- FLOWS (loop engineering): a task can drive a full multi-agent development cycle. Define a process once with
  `oracle_flow_save` (steps = loops, edges = wiring), file work with `oracle_task_create`, and trigger it with
  `oracle_flow_run_start` — the deterministic Flow Runner executes the graph, launching a coding agent per
  step. INSIDE a step you are given a runStepId: call `oracle_flow_step_context` first (task + plan + blackboard
  + prior reports), write shared state with `oracle_flow_context_put`, record outputs with
  `oracle_flow_artifact_add`, and finish with `oracle_flow_step_report` (the runner verifies OUTSIDE you — never
  self-approve). Watch runs with `oracle_flow_run_status`; approve human gates with `oracle_flow_gate_decide`.
  As a flow step you run inside the run's git WORKTREE (`.oracle-worktrees/...`) — it belongs to the SAME
  project as the main repo (resolution follows the worktree back to it, and ORACLE_PROJECT_ID pins it). Never
  register a new project, never switch directories out of the workspace, and never stop to ask the user —
  if you truly cannot proceed, finish with `oracle_flow_step_report` status "blocked" + openQuestions and a
  human will be brought in.
- Call Oracle MCP tools through the tool surface the client exposes. Prefer a native direct `oracle_*` call when
  available. Some Codex clients expose MCP tools programmatically under `functions.exec` / `exec` as
  `tools.mcp__oracle_ai__oracle_*`; in that client, USE that supported wrapper and do not refuse the step merely
  because a native direct tool is absent. Never emulate Oracle by running its executable, curl, or shell commands.
  Always complete `oracle_flow_step_context` and the final `oracle_flow_step_report` through one of those MCP paths.
  If an Oracle call returns "user cancelled MCP tool call" (or any "cancelled" variant), that is a TRANSIENT
  cancellation by the host — not a user decision. Retry the SAME call up to 3 times before treating it as a
  failure. In a flow step, always pass the claimToken from your step prompt (or from
  `oracle_flow_step_context` → runStep.claimToken) to `oracle_flow_step_report`.
- At the end of a task / before context compaction, write a handoff with `oracle_handoff_begin`.
- Keep memory healthy: retire/forget what is wrong or obsolete. Bad memory is worse than none.
Capture is automatic — hooks record the session, each user request, and your work (messages) as
`Session -> Request -> Messages`. You never log them by hand; just save consolidated memories as above.''';

  /// Builds the server, registers the tools, connects over stdio, and completes
  /// when the transport closes (stdin EOF).
  Future<void> serveStdio() async {
    final server = mcp.McpServer(
      mcp.Implementation(name: name, version: version),
      options: const mcp.ServerOptions(instructions: instructions),
    );
    _registerTools(server);

    final done = Completer<void>();
    server.server.onclose = () {
      if (!done.isCompleted) done.complete();
    };
    await server.connect(mcp.StdioServerTransport());
    await done.future;
  }

  void _registerTools(mcp.McpServer rawServer) {
    // mcp_dart intentionally defaults unannotated tools to destructive and
    // open-world. Headless agents running with approval=never may therefore
    // cancel even a read-only Oracle call before it reaches this server. Route
    // every registration through one registrar so the complete surface is
    // advertised with accurate safety hints (and gated on DB readiness).
    final server = _OracleToolRegistrar(rawServer, dbGate);
    server.tool(
      'oracle_status',
      description: 'Returns Oracle AI server status.',
      toolInputSchema: const mcp.ToolInputSchema(properties: {}),
      callback: ({args, extra}) async =>
          _ok({'name': name, 'version': version, 'ok': true}),
    );

    // --- project ---
    server.tool(
      'oracle_project_register',
      description: 'Register a project (the central scope unit).',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'name': {'type': 'string', 'description': 'Project name'},
          'description': {'type': 'string'},
          'repoPath': {
            'type': 'string',
            'description': 'Absolute repository path',
          },
        },
        required: ['name'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<RegisterProjectUsecase>()(
          ProjectEntity(
            id: const IdVO.empty(),
            name: TextVO('${a['name'] ?? ''}'),
            description: a['description'] == null
                ? null
                : TextVO('${a['description']}'),
            repoPath: a['repoPath']?.toString(),
          ),
        );
        return result.fold((p) => _ok(_projectJson(p)), _err);
      },
    );

    server.tool(
      'oracle_project_list',
      description: 'List projects.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'search': {'type': 'string'},
          'limit': {'type': 'integer'},
        },
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<ListProjectsUsecase>()(
          ProjectFilter(
            search: '${a['search'] ?? ''}',
            limit: _clampLimit(a['limit'], fallback: 50, max: 200),
          ),
        );
        return result.fold(
          (list) => _ok(list.map(_projectJson).toList()),
          _err,
        );
      },
    );

    server.tool(
      'oracle_project_resolve',
      description:
          'Map a working directory (cwd / repo path) to a stable projectId, '
          'creating the project on first sight. Call this once at session start to get '
          'the projectId used by every other tool — no manual registration needed.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'repoPath': {
            'type': 'string',
            'description': 'Absolute repository path (the agent cwd)',
          },
          'name': {
            'type': 'string',
            'description': 'Optional; defaults to the directory name',
          },
          'organizationId': {
            'type': 'string',
            'description':
                'Optional ecosystem/organization this repo belongs to',
          },
        },
        required: ['repoPath'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        // A flow-step agent carries ORACLE_PROJECT_ID (set by the runner and
        // inherited by this process): the run's project ALWAYS wins — the cwd
        // may be a worktree or temp dir and must never mint a new project.
        final pinned = _envProjectId;
        if (pinned != null) {
          final byId = await injector.get<GetProjectByIdUsecase>()(pinned);
          if (byId.isSuccess()) return _ok(_projectJson(byId.getOrThrow()));
        }
        final repoPath = '${a['repoPath'] ?? ''}';
        // Canonicalize to the git root (as the hooks and session_brief do), so a
        // call from a subdirectory or worktree maps to the SAME project instead
        // of creating a duplicate disjoint from the hook-captured one.
        final result = await injector.get<ResolveProjectUsecase>()(
          repoPath.trim().isEmpty ? repoPath : repoRootOf(repoPath),
          name: a['name']?.toString(),
          organizationId: a['organizationId'] == null
              ? null
              : IdVO('${a['organizationId']}'),
        );
        return result.fold((p) => _ok(_projectJson(p)), _err);
      },
    );

    server.tool(
      'oracle_module_resolve',
      description:
          'Map a working SUBPATH (under the project repo root) to a stable moduleId, '
          'creating the module on first sight. Use this instead of registering a submodule as a '
          'separate project — a project has many modules (a service, layer, package). Pass the '
          'module subpath (e.g. "services/auth"), or a `cwd` to derive it. An empty/root path '
          'means the work is project-level (no module).',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'projectId': {
            'type': 'string',
            'description': 'The project this module belongs to',
          },
          'path': {
            'type': 'string',
            'description':
                'Module subpath under the repo root, e.g. services/auth',
          },
          'cwd': {
            'type': 'string',
            'description':
                'Optional; a cwd to derive the subpath from (relative to the git root)',
          },
          'name': {
            'type': 'string',
            'description': 'Optional; defaults to the last path segment',
          },
          'description': {
            'type': 'string',
            'description': 'Optional module description',
          },
        },
        required: ['projectId'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final projectId = '${a['projectId'] ?? ''}'.trim();
        var path = '${a['path'] ?? ''}'.trim();
        if (path.isEmpty && '${a['cwd'] ?? ''}'.trim().isNotEmpty) {
          path = _relativeSubpath('${a['cwd']}');
        }
        if (path.isEmpty) {
          return _ok(<String, dynamic>{
            'module': null,
            'note':
                'Path is the repo root — this work is project-level; no module was created.',
          });
        }
        final result = await injector.get<ResolveModuleUsecase>()(
          IdVO(projectId),
          path,
          name: a['name']?.toString(),
          description: a['description']?.toString(),
        );
        return result.fold((m) => _ok(_moduleJson(m)), _err);
      },
    );

    server.tool(
      'oracle_module_list',
      description: "List a project's modules (id, key, name, path).",
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'projectId': {'type': 'string'},
          'limit': {'type': 'integer', 'description': 'Default 100'},
        },
        required: ['projectId'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<ListModulesUsecase>()(
          ModuleFilter(
            projectId: IdVO('${a['projectId'] ?? ''}'),
            limit: (a['limit'] as num?)?.toInt() ?? 100,
          ),
        );
        return result.fold((list) => _ok(list.map(_moduleJson).toList()), _err);
      },
    );

    server.tool(
      'oracle_session_brief',
      description:
          'Get oriented at the start of work: pass your repo path (cwd) and receive the projectId '
          'plus a brief — pending handoff + required rules + key memories. Call this first.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'repoPath': {
            'type': 'string',
            'description': 'Absolute repo path (cwd); resolved to the project',
          },
          'projectId': {
            'type': 'string',
            'description': 'Or pass a known projectId instead of repoPath',
          },
        },
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        IdVO? pid = _envProjectId; // flow-run attribution always wins
        if (pid == null && '${a['projectId'] ?? ''}'.trim().isNotEmpty) {
          pid = IdVO('${a['projectId']}');
        } else if (pid == null && '${a['repoPath'] ?? ''}'.trim().isNotEmpty) {
          final res = await injector.get<ResolveProjectUsecase>()(
            repoRootOf('${a['repoPath']}'),
          );
          pid = res.getOrNull()?.id;
        }
        if (pid == null) {
          return _ok({'note': 'pass repoPath (cwd) or projectId'});
        }
        final brief = await const RecallService().sessionBrief(pid);
        return _ok({'projectId': pid.value, 'brief': brief ?? ''});
      },
    );

    // --- memory ---
    server.tool(
      'oracle_memory_save',
      description:
          'Save a consolidated memory (decision/gotcha/rule/fact). Only save durable, '
          'non-trivial learnings. To AVOID DUPLICATES: give a recurring memory a stable `key` '
          '(kebab-case, e.g. "filter-rollout-progress") and re-save with the same key to update '
          'it in place instead of piling up near-duplicates — re-saving an unchanged keyed memory '
          'is a free no-op (no re-embedding). Alternatively pass `supersedes` with the id of a '
          'memory this one replaces. Recall first (oracle_memory_search) before creating a new one.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'projectId': {'type': 'string'},
          'organizationId': {'type': 'string'},
          'key': {
            'type': 'string',
            'description':
                'Optional stable slug (kebab-case). Re-saving the same key in the same '
                'project/organization supersedes the previous version — use it to update one memory '
                'instead of creating duplicates.',
          },
          'supersedes': {
            'type': 'string',
            'description':
                'Optional id of a memory this one replaces (retired in the same write).',
          },
          'tier': {
            'type': 'string',
            'description': 'episodic | semantic | procedural',
          },
          'kind': {
            'type': 'string',
            'description': 'decision | gotcha | rule | fact',
          },
          'title': {'type': 'string'},
          'body': {'type': 'string'},
          'tags': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'importance': {
            'type': 'number',
            'description':
                '0..1; ranks memories in the session brief. Defaults to 0.5. '
                'Episodic memories below 0.3 that go unaccessed are eligible for auto-decay.',
          },
        },
        required: ['title', 'body'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final key = a['key']?.toString().trim();
        final supersedes = a['supersedes']?.toString().trim();
        final result = await injector.get<SaveMemoryUsecase>()(
          MemoryEntity(
            id: const IdVO.empty(),
            projectId: a['projectId'] == null
                ? null
                : IdVO('${a['projectId']}'),
            organizationId: a['organizationId'] == null
                ? null
                : IdVO('${a['organizationId']}'),
            moduleId: a['moduleId'] == null ? null : IdVO('${a['moduleId']}'),
            key: (key == null || key.isEmpty) ? null : key,
            supersedes: (supersedes == null || supersedes.isEmpty)
                ? null
                : IdVO(supersedes),
            tier: MemoryTier.parse('${a['tier'] ?? 'semantic'}'),
            kind: MemoryKind.parse('${a['kind'] ?? 'fact'}'),
            title: TextVO('${a['title'] ?? ''}'),
            body: TextVO('${a['body'] ?? ''}'),
            tags: _stringList(a['tags']),
            // Default to a neutral 0.5 (not 0): a 0 importance sinks below the decay
            // threshold and makes the importance-ordered brief degenerate to newest-first.
            importance: (a['importance'] as num?)?.toDouble() ?? 0.5,
          ),
        );
        if (result.isError()) return _err(result.exceptionOrNull()!);
        return _ok(await _memoryJsonWithSimilar(result.getOrThrow()));
      },
    );

    server.tool(
      'oracle_memory_search',
      description:
          'Hybrid search over consolidated memory (vector + full-text, RRF).',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'query': {'type': 'string'},
          'projectId': {'type': 'string'},
          'organizationId': {'type': 'string'},
          'tiers': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'kinds': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'limit': {'type': 'integer', 'description': 'Default 10, max 50'},
          'full': {
            'type': 'boolean',
            'description':
                'Default false → id+title+snippet per hit (cheap). '
                'true → full body (use only when you truly need every body inline).',
          },
        },
        required: ['query'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final full = a['full'] == true;
        final sw = Stopwatch()..start();
        final result = await injector.get<SearchMemoriesUsecase>()(
          MemorySearchFilter(
            query: '${a['query'] ?? ''}',
            projectId: a['projectId'] == null
                ? null
                : IdVO('${a['projectId']}'),
            organizationId: a['organizationId'] == null
                ? null
                : IdVO('${a['organizationId']}'),
            moduleId: a['moduleId'] == null ? null : IdVO('${a['moduleId']}'),
            tiers: _stringList(a['tiers']).map(MemoryTier.parse).toList(),
            kinds: _stringList(a['kinds']).map(MemoryKind.parse).toList(),
            limit: _clampLimit(a['limit'], fallback: 10),
          ),
        );
        return result.fold((list) {
          _logSearch(
            tool: 'memory',
            query: '${a['query'] ?? ''}',
            scope: _scopeOf(a),
            results: [
              for (final e in list)
                _searchResult(
                  id: e.memory.id.value,
                  score: e.score,
                  title: e.memory.title.value,
                  subtitle: '${e.memory.kind.code} · ${e.memory.tier.code}',
                  content: e.memory.body.value,
                ),
            ],
            latencyMs: sw.elapsedMilliseconds,
          );
          return _ok(list.map((e) => _memoryHit(e, full: full)).toList());
        }, _err);
      },
    );

    server.tool(
      'oracle_memory_get',
      description: 'Get a memory by id.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'id': {'type': 'string'},
        },
        required: ['id'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<GetMemoryByIdUsecase>()(
          IdVO('${a['id'] ?? ''}'),
        );
        return result.fold((m) => _ok(_memoryJson(m)), _err);
      },
    );

    server.tool(
      'oracle_memory_forget',
      description:
          'Forget a memory that is wrong or obsolete (bad memory is worse than no '
          'memory). Soft by default (dropped from recall, kept for audit with a reason); '
          'pass hard=true to delete it permanently.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'id': {'type': 'string'},
          'reason': {
            'type': 'string',
            'description': 'Why it is being forgotten (audit)',
          },
          'hard': {
            'type': 'boolean',
            'description': 'true = permanent delete (purge)',
          },
        },
        required: ['id'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<ForgetMemoryUsecase>()(
          IdVO('${a['id'] ?? ''}'),
          reason: a['reason']?.toString(),
          hard: a['hard'] == true,
        );
        return result.fold((m) => _ok(_memoryJson(m)), _err);
      },
    );

    // --- rule ---
    server.tool(
      'oracle_rule_save',
      description:
          'Create or refine a development rule. Re-saving the same key in the '
          'same owner REFINES it: the previous version is superseded (kept as history) '
          'and the new content/severity/priority take over. Use this to improve a rule.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'projectId': {'type': 'string'},
          'organizationId': {'type': 'string'},
          'key': {
            'type': 'string',
            'description': 'Stable slug (e.g. controllers-pattern)',
          },
          'scope': {'type': 'string', 'description': 'module / folder / area'},
          'title': {'type': 'string'},
          'content': {'type': 'string'},
          'severity': {
            'type': 'string',
            'description': 'required | recommended (obligation)',
          },
          'priority': {
            'type': 'integer',
            'description':
                'Ranking within a severity, 0..100 (default 50). LOWER wins — 1 is most relevant, delivered first in rules_for_task.',
          },
          'tags': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
        required: ['key', 'scope', 'title', 'content'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<SaveRuleUsecase>()(
          RuleEntity(
            id: const IdVO.empty(),
            projectId: a['projectId'] == null
                ? null
                : IdVO('${a['projectId']}'),
            organizationId: a['organizationId'] == null
                ? null
                : IdVO('${a['organizationId']}'),
            moduleId: a['moduleId'] == null ? null : IdVO('${a['moduleId']}'),
            key: '${a['key'] ?? ''}',
            scope: '${a['scope'] ?? ''}',
            title: TextVO('${a['title'] ?? ''}'),
            content: TextVO('${a['content'] ?? ''}'),
            severity: RuleSeverity.parse('${a['severity'] ?? 'recommended'}'),
            priority: (a['priority'] as num?)?.toInt() ?? 50,
            tags: _stringList(a['tags']),
          ),
        );
        if (result.isError()) return _err(result.exceptionOrNull()!);
        return _ok(await _ruleJsonWithSimilar(result.getOrThrow()));
      },
    );

    server.tool(
      'oracle_rule_set_priority',
      description:
          'Re-rank an existing rule in place (no new version). Set how strongly a '
          'still-valid rule weighs in rules_for_task — LOWER is stronger (1 = most relevant).',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'id': {'type': 'string'},
          'priority': {
            'type': 'integer',
            'description': '0..100 — lower = more relevant (1 first)',
          },
        },
        required: ['id', 'priority'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<SetRulePriorityUsecase>()(
          IdVO('${a['id'] ?? ''}'),
          (a['priority'] as num?)?.toInt() ?? 50,
        );
        return result.fold((r) => _ok(_ruleJson(r)), _err);
      },
    );

    server.tool(
      'oracle_rule_retire',
      description:
          'Retire a rule that no longer applies. Soft by default (dropped from '
          'recall, kept for audit with a reason); pass hard=true to delete it permanently.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'id': {'type': 'string'},
          'reason': {
            'type': 'string',
            'description': 'Why it is being retired (audit)',
          },
          'hard': {
            'type': 'boolean',
            'description': 'true = permanent delete (purge)',
          },
        },
        required: ['id'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<RetireRuleUsecase>()(
          IdVO('${a['id'] ?? ''}'),
          reason: a['reason']?.toString(),
          hard: a['hard'] == true,
        );
        return result.fold((r) => _ok(_ruleJson(r)), _err);
      },
    );

    server.tool(
      'oracle_rules_for_task',
      description:
          'Applicable rules for a task in a project (organization→project inheritance '
          'and override). Consult before generating code.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'projectId': {'type': 'string'},
          'scope': {
            'type': 'string',
            'description': 'optional module/folder/area filter',
          },
          'limit': {'type': 'integer'},
        },
        required: ['projectId'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<RulesForTaskUsecase>()(
          RulesForTaskQuery(
            projectId: IdVO('${a['projectId'] ?? ''}'),
            moduleId: a['moduleId'] == null ? null : IdVO('${a['moduleId']}'),
            scope: a['scope']?.toString(),
            limit: _clampLimit(a['limit'], fallback: 50, max: 100),
          ),
        );
        return result.fold((list) => _ok(list.map(_ruleJson).toList()), _err);
      },
    );

    server.tool(
      'oracle_rule_search',
      description: 'Hybrid search over development rules.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'query': {'type': 'string'},
          'projectId': {'type': 'string'},
          'organizationId': {'type': 'string'},
          'scope': {'type': 'string'},
          'severities': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'limit': {'type': 'integer', 'description': 'Default 10, max 50'},
          'full': {
            'type': 'boolean',
            'description':
                'Default false → id+title+snippet per hit; true → full content.',
          },
        },
        required: ['query'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final full = a['full'] == true;
        final sw = Stopwatch()..start();
        final result = await injector.get<SearchRulesUsecase>()(
          RuleSearchFilter(
            query: '${a['query'] ?? ''}',
            projectId: a['projectId'] == null
                ? null
                : IdVO('${a['projectId']}'),
            organizationId: a['organizationId'] == null
                ? null
                : IdVO('${a['organizationId']}'),
            moduleId: a['moduleId'] == null ? null : IdVO('${a['moduleId']}'),
            scope: a['scope']?.toString(),
            severities: _stringList(
              a['severities'],
            ).map(RuleSeverity.parse).toList(),
            limit: _clampLimit(a['limit'], fallback: 10),
          ),
        );
        return result.fold((list) {
          _logSearch(
            tool: 'rule',
            query: '${a['query'] ?? ''}',
            scope: _scopeOf(a),
            results: [
              for (final e in list)
                _searchResult(
                  id: e.rule.id.value,
                  score: e.score,
                  title: e.rule.title.value,
                  subtitle:
                      '${e.rule.key} · ${e.rule.scope} · ${e.rule.severity.code}',
                  content: e.rule.content.value,
                ),
            ],
            latencyMs: sw.elapsedMilliseconds,
          );
          return _ok(list.map((e) => _ruleHit(e, full: full)).toList());
        }, _err);
      },
    );

    // --- organization ---
    server.tool(
      'oracle_organization_register',
      description:
          'Register a organization (the ecosystem scope above projects).',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'name': {'type': 'string'},
          'description': {'type': 'string'},
        },
        required: ['name'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<RegisterOrganizationUsecase>()(
          OrganizationEntity(
            id: const IdVO.empty(),
            name: TextVO('${a['name'] ?? ''}'),
            description: a['description'] == null
                ? null
                : TextVO('${a['description']}'),
          ),
        );
        return result.fold((p) => _ok(_organizationJson(p)), _err);
      },
    );

    server.tool(
      'oracle_organization_list',
      description: 'List organizations.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'search': {'type': 'string'},
          'limit': {'type': 'integer'},
        },
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<ListOrganizationsUsecase>()(
          OrganizationFilter(
            search: '${a['search'] ?? ''}',
            limit: _clampLimit(a['limit'], fallback: 50, max: 200),
          ),
        );
        return result.fold(
          (list) => _ok(list.map(_organizationJson).toList()),
          _err,
        );
      },
    );

    // --- skill (centralized shared skill library) ---
    server.tool(
      'oracle_skill_save',
      description:
          'Save a reusable skill (SKILL.md-style how-to) into the CENTRAL shared '
          'library — one copy for every agent, no per-agent folders. Use a stable kebab-case '
          '`key`; re-saving the same key in the same scope supersedes it. Omit projectId AND '
          'organizationId for a GLOBAL skill (visible everywhere). `description` is the recall '
          'trigger — write it as "what it does + when to use it". Re-saving unchanged content '
          'is a free no-op.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'key': {
            'type': 'string',
            'description':
                'Stable kebab-case slug (e.g. filter-rollout-recipe)',
          },
          'name': {'type': 'string', 'description': 'Display name'},
          'description': {
            'type': 'string',
            'description':
                'What it does + when to use it (this is what searches match on)',
          },
          'content': {
            'type': 'string',
            'description': 'The skill body (markdown, SKILL.md style)',
          },
          'projectId': {
            'type': 'string',
            'description': 'Scope to one project (omit for wider scope)',
          },
          'organizationId': {
            'type': 'string',
            'description': 'Scope to a organization (omit for global)',
          },
          'tags': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
        required: ['key', 'name', 'description', 'content'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<SaveSkillUsecase>()(
          SkillEntity(
            id: const IdVO.empty(),
            projectId: a['projectId'] == null
                ? null
                : IdVO('${a['projectId']}'),
            organizationId: a['organizationId'] == null
                ? null
                : IdVO('${a['organizationId']}'),
            moduleId: a['moduleId'] == null ? null : IdVO('${a['moduleId']}'),
            key: '${a['key'] ?? ''}'.trim(),
            name: TextVO('${a['name'] ?? ''}'),
            description: TextVO('${a['description'] ?? ''}'),
            content: TextVO('${a['content'] ?? ''}'),
            tags: _stringList(a['tags']),
          ),
        );
        if (result.isError()) return _err(result.exceptionOrNull()!);
        return _ok(await _skillJsonWithSimilar(result.getOrThrow()));
      },
    );

    server.tool(
      'oracle_skill_search',
      description:
          'Find skills in the shared library by task context (hybrid search: vector + '
          'full-text). Returns name+description+key per hit (cheap, progressive disclosure) — '
          'load the winner with oracle_skill_get. Global skills are always included; projectId/'
          'organizationId add their scoped skills.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'query': {
            'type': 'string',
            'description': 'The task context (what you are about to do)',
          },
          'projectId': {'type': 'string'},
          'organizationId': {'type': 'string'},
          'limit': {'type': 'integer', 'description': 'Default 10, max 50'},
        },
        required: ['query'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final sw = Stopwatch()..start();
        final result = await injector.get<SearchSkillsUsecase>()(
          SkillSearchFilter(
            query: '${a['query'] ?? ''}',
            projectId: a['projectId'] == null
                ? null
                : IdVO('${a['projectId']}'),
            organizationId: a['organizationId'] == null
                ? null
                : IdVO('${a['organizationId']}'),
            moduleId: a['moduleId'] == null ? null : IdVO('${a['moduleId']}'),
            limit: _clampLimit(a['limit'], fallback: 10),
          ),
        );
        final sk = result.getOrNull();
        if (sk != null) {
          _logSearch(
            tool: 'skill',
            query: '${a['query'] ?? ''}',
            scope: _scopeOf(a),
            results: [
              for (final e in sk)
                _searchResult(
                  id: e.skill.id.value,
                  score: e.score,
                  title: e.skill.name.value,
                  subtitle: '${e.skill.key} · ${e.skill.description.value}',
                  content: e.skill.content.value,
                ),
            ],
            latencyMs: sw.elapsedMilliseconds,
          );
        }
        return result.fold(
          (list) => _ok(
            list
                .map(
                  (e) => {
                    'id': e.skill.id.value,
                    'key': e.skill.key,
                    'name': e.skill.name.value,
                    'description': e.skill.description.value,
                    'scope': e.skill.projectId != null
                        ? 'project'
                        : (e.skill.organizationId != null
                              ? 'organization'
                              : 'global'),
                    'score': e.score,
                  },
                )
                .toList(),
          ),
          _err,
        );
      },
    );

    server.tool(
      'oracle_skill_get',
      description:
          'Load one skill\'s full content (the "use the skill" step after '
          'oracle_skill_search). Pass an id, or a key — a key resolves project → organization → '
          'global, so a project-specific version overrides the shared one.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'id': {'type': 'string'},
          'key': {'type': 'string'},
          'projectId': {
            'type': 'string',
            'description': 'Used for key resolution',
          },
          'organizationId': {
            'type': 'string',
            'description': 'Used for key resolution',
          },
        },
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<GetSkillUsecase>()(
          id: a['id'] == null ? null : IdVO('${a['id']}'),
          key: a['key']?.toString(),
          projectId: a['projectId'] == null ? null : IdVO('${a['projectId']}'),
          organizationId: a['organizationId'] == null
              ? null
              : IdVO('${a['organizationId']}'),
        );
        return result.fold((s) => _ok(_skillJson(s)), _err);
      },
    );

    server.tool(
      'oracle_skill_list',
      description:
          'Inventory of the current skills visible to a scope (global + organization + '
          'project). Name+description+key only.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'projectId': {'type': 'string'},
          'organizationId': {'type': 'string'},
          'limit': {'type': 'integer', 'description': 'Default 200'},
        },
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<ListSkillsUsecase>()(
          projectId: a['projectId'] == null ? null : IdVO('${a['projectId']}'),
          organizationId: a['organizationId'] == null
              ? null
              : IdVO('${a['organizationId']}'),
          limit: _clampLimit(a['limit'], fallback: 200, max: 500),
        );
        return result.fold(
          (list) => _ok(
            list
                .map(
                  (s) => {
                    'id': s.id.value,
                    'key': s.key,
                    'name': s.name.value,
                    'description': s.description.value,
                    'scope': s.projectId != null
                        ? 'project'
                        : (s.organizationId != null
                              ? 'organization'
                              : 'global'),
                  },
                )
                .toList(),
          ),
          _err,
        );
      },
    );

    server.tool(
      'oracle_skill_retire',
      description:
          'Retire a skill that is wrong or obsolete. Soft by default (kept for '
          'audit with a reason); pass hard=true to delete permanently.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'id': {'type': 'string'},
          'reason': {'type': 'string'},
          'hard': {'type': 'boolean'},
        },
        required: ['id'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<RetireSkillUsecase>()(
          IdVO('${a['id'] ?? ''}'),
          reason: a['reason']?.toString(),
          hard: a['hard'] == true,
        );
        return result.fold((s) => _ok(_skillJson(s)), _err);
      },
    );

    // --- architecture ---
    server.tool(
      'oracle_architecture_save',
      description:
          'Save or refine a project architecture page for an area. Re-saving the '
          'same area supersedes the previous page (kept as history) — use it to keep the '
          'architecture up to date as it changes.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'projectId': {'type': 'string'},
          'area': {'type': 'string', 'description': 'module / layer'},
          'content': {'type': 'string'},
        },
        required: ['projectId', 'area', 'content'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<SaveArchitectureUsecase>()(
          ArchitectureEntity(
            id: const IdVO.empty(),
            projectId: a['projectId'] == null
                ? null
                : IdVO('${a['projectId']}'),
            organizationId: a['organizationId'] == null
                ? null
                : IdVO('${a['organizationId']}'),
            moduleId: a['moduleId'] == null ? null : IdVO('${a['moduleId']}'),
            area: '${a['area'] ?? ''}',
            content: TextVO('${a['content'] ?? ''}'),
          ),
        );
        return result.fold((x) => _ok(_architectureJson(x)), _err);
      },
    );

    server.tool(
      'oracle_architecture_get',
      description: 'Get the current architecture page for a project area.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'projectId': {'type': 'string'},
          'organizationId': {'type': 'string'},
          'moduleId': {'type': 'string'},
          'area': {'type': 'string'},
        },
        required: ['area'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<GetArchitectureByAreaUsecase>()(
          organizationId: a['organizationId'] == null
              ? null
              : IdVO('${a['organizationId']}'),
          projectId: a['projectId'] == null ? null : IdVO('${a['projectId']}'),
          moduleId: a['moduleId'] == null ? null : IdVO('${a['moduleId']}'),
          area: '${a['area'] ?? ''}',
        );
        return result.fold((x) => _ok(_architectureJson(x)), _err);
      },
    );

    server.tool(
      'oracle_architecture_search',
      description: 'Hybrid search over project architecture.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'query': {'type': 'string'},
          'projectId': {'type': 'string'},
          'area': {'type': 'string'},
          'limit': {'type': 'integer', 'description': 'Default 10, max 50'},
          'full': {
            'type': 'boolean',
            'description':
                'Default false → id+area+snippet per hit; true → full content. '
                'Architecture pages can be large — prefer the default, then get the area you need.',
          },
        },
        required: ['query'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final full = a['full'] == true;
        final sw = Stopwatch()..start();
        final result = await injector.get<SearchArchitectureUsecase>()(
          ArchitectureSearchFilter(
            query: '${a['query'] ?? ''}',
            projectId: a['projectId'] == null
                ? null
                : IdVO('${a['projectId']}'),
            organizationId: a['organizationId'] == null
                ? null
                : IdVO('${a['organizationId']}'),
            moduleId: a['moduleId'] == null ? null : IdVO('${a['moduleId']}'),
            area: a['area']?.toString(),
            limit: _clampLimit(a['limit'], fallback: 10),
          ),
        );
        final arch = result.getOrNull();
        if (arch != null) {
          _logSearch(
            tool: 'architecture',
            query: '${a['query'] ?? ''}',
            scope: _scopeOf(a),
            results: [
              for (final e in arch)
                _searchResult(
                  id: e.architecture.id.value,
                  score: e.score,
                  title: e.architecture.area,
                  subtitle: 'architecture',
                  content: e.architecture.content.value,
                ),
            ],
            latencyMs: sw.elapsedMilliseconds,
          );
        }
        return result.fold(
          (list) =>
              _ok(list.map((e) => _architectureHit(e, full: full)).toList()),
          _err,
        );
      },
    );

    server.tool(
      'oracle_architecture_retire',
      description:
          'Retire an architecture page that no longer reflects the project. Soft '
          'by default (dropped from recall, kept for audit with a reason); pass hard=true '
          'to delete it permanently.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'id': {'type': 'string'},
          'reason': {
            'type': 'string',
            'description': 'Why it is being retired (audit)',
          },
          'hard': {
            'type': 'boolean',
            'description': 'true = permanent delete (purge)',
          },
        },
        required: ['id'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<RetireArchitectureUsecase>()(
          IdVO('${a['id'] ?? ''}'),
          reason: a['reason']?.toString(),
          hard: a['hard'] == true,
        );
        return result.fold((x) => _ok(_architectureJson(x)), _err);
      },
    );

    // --- handoff ---
    server.tool(
      'oracle_handoff_begin',
      description: 'Write a handoff (state passed to the next session/agent).',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'projectId': {'type': 'string'},
          'summary': {'type': 'string'},
          'fromAgent': {'type': 'string'},
          'toAgent': {'type': 'string'},
          'sourceSessionId': {'type': 'string'},
          'openQuestions': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'nextSteps': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'filesTouched': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'cwd': {'type': 'string'},
        },
        required: ['projectId', 'summary'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<BeginHandoffUsecase>()(
          HandoffEntity(
            id: const IdVO.empty(),
            projectId: IdVO('${a['projectId'] ?? ''}'),
            sourceSessionId: a['sourceSessionId'] == null
                ? null
                : IdVO('${a['sourceSessionId']}'),
            fromAgent: a['fromAgent']?.toString(),
            toAgent: a['toAgent']?.toString(),
            summary: TextVO('${a['summary'] ?? ''}'),
            openQuestions: _stringList(a['openQuestions']),
            nextSteps: _stringList(a['nextSteps']),
            filesTouched: _stringList(a['filesTouched']),
            cwd: a['cwd']?.toString(),
          ),
        );
        return result.fold((h) => _ok(_handoffJson(h)), _err);
      },
    );

    server.tool(
      'oracle_handoff_pending',
      description: 'Pending handoff for a project (inject on session start).',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'projectId': {'type': 'string'},
        },
        required: ['projectId'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<PendingHandoffsUsecase>()(
          IdVO('${a['projectId'] ?? ''}'),
        );
        return result.fold(
          (list) => _ok(list.map(_handoffJson).toList()),
          _err,
        );
      },
    );

    server.tool(
      'oracle_handoff_accept',
      description: 'Accept (consume) a handoff.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'id': {'type': 'string'},
        },
        required: ['id'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<AcceptHandoffUsecase>()(
          IdVO('${a['id'] ?? ''}'),
        );
        return result.fold((h) => _ok(_handoffJson(h)), _err);
      },
    );

    // --- capture (reads) ---
    server.tool(
      'oracle_session_recent',
      description: 'Recent sessions for a project.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'projectId': {'type': 'string'},
          'limit': {'type': 'integer'},
        },
        required: ['projectId'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<RecentSessionsUsecase>()(
          IdVO('${a['projectId'] ?? ''}'),
          limit: _clampLimit(a['limit'], fallback: 20, max: 100),
        );
        return result.fold(
          (list) => _ok(list.map(_sessionJson).toList()),
          _err,
        );
      },
    );

    server.tool(
      'oracle_session_history',
      description:
          'A session\'s messages, MOST RECENT FIRST (the agent work across every request '
          'in that session) — so you see the latest activity immediately. For one demand only, '
          'use oracle_request_messages. Content is capped per message; raw turns live in the host.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'sessionId': {'type': 'string'},
          'limit': {'type': 'integer'},
        },
        required: ['sessionId'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<SessionHistoryUsecase>()(
          IdVO('${a['sessionId'] ?? ''}'),
          limit: _clampLimit(a['limit'], fallback: 40, max: 200),
        );
        return result.fold(
          (list) => _ok(list.map(_messageJson).toList()),
          _err,
        );
      },
    );

    server.tool(
      'oracle_session_requests',
      description:
          'The user demands (requests) made in a session, newest first.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'sessionId': {'type': 'string'},
          'limit': {'type': 'integer'},
        },
        required: ['sessionId'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<SessionRequestsUsecase>()(
          IdVO('${a['sessionId'] ?? ''}'),
          limit: _clampLimit(a['limit'], fallback: 50, max: 200),
        );
        return result.fold(
          (list) => _ok(list.map(_requestJson).toList()),
          _err,
        );
      },
    );

    server.tool(
      'oracle_request_messages',
      description:
          'The agent work (messages) carrying out one specific request/demand, in order. '
          'Content is capped per message.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'requestId': {'type': 'string'},
          'limit': {'type': 'integer'},
        },
        required: ['requestId'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<RequestMessagesUsecase>()(
          IdVO('${a['requestId'] ?? ''}'),
          limit: _clampLimit(a['limit'], fallback: 100, max: 500),
        );
        return result.fold(
          (list) => _ok(list.map(_messageJson).toList()),
          _err,
        );
      },
    );

    server.tool(
      'oracle_request_search',
      description:
          'Semantic search over past USER DEMANDS in this project — "has the user '
          'asked for something like this before?". Returns matching requests (with their ids, '
          'so you can pull their messages via oracle_request_messages).',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'projectId': {'type': 'string'},
          'query': {'type': 'string'},
          'limit': {'type': 'integer'},
        },
        required: ['projectId', 'query'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<RequestSearchUsecase>()(
          IdVO('${a['projectId'] ?? ''}'),
          '${a['query'] ?? ''}',
          limit: _clampLimit(a['limit'], fallback: 10, max: 50),
        );
        return result.fold(
          (list) => _ok(list.map(_requestJson).toList()),
          _err,
        );
      },
    );

    // --- maintenance ---
    server.tool(
      'oracle_maintenance_run',
      description:
          'Run the deterministic maintenance sweep over memories (no LLM): decay '
          '(forget stale, low-value, rarely-accessed memories) + dedup (forget the weaker '
          'of near-duplicates). Soft + audited. Use dryRun=true to preview. Rules and '
          'architecture are never auto-forgotten.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'dryRun': {
            'type': 'boolean',
            'description': 'Preview only; change nothing',
          },
          'decay': {
            'type': 'boolean',
            'description': 'Run the decay pass (default true)',
          },
          'dedup': {
            'type': 'boolean',
            'description': 'Run the dedup pass (default true)',
          },
          'tiers': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Tiers eligible for decay (default ["episodic"])',
          },
          'staleDays': {
            'type': 'integer',
            'description': 'Forget if not accessed in N days (default 30)',
          },
          'minImportance': {
            'type': 'number',
            'description': 'Forget below this importance (default 0.3)',
          },
          'minAccessCount': {
            'type': 'integer',
            'description': 'Forget if accessed < N times (default 2)',
          },
          'dedupDistance': {
            'type': 'number',
            'description': 'Cosine distance for near-dup (default 0.05)',
          },
          'limit': {
            'type': 'integer',
            'description': 'Max memories retired per pass (default 500)',
          },
        },
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final tiers = _stringList(a['tiers']);
        final result = await injector.get<RunMaintenanceUsecase>()(
          DecayPolicy(
            dryRun: a['dryRun'] == true,
            runDecay: a['decay'] != false,
            runDedup: a['dedup'] != false,
            eligibleTiers: tiers.isEmpty ? const ['episodic'] : tiers,
            staleDays: (a['staleDays'] as num?)?.toInt() ?? 30,
            minImportance: (a['minImportance'] as num?)?.toDouble() ?? 0.3,
            minAccessCount: (a['minAccessCount'] as num?)?.toInt() ?? 2,
            dedupDistance: (a['dedupDistance'] as num?)?.toDouble() ?? 0.05,
            limit: _clampLimit(a['limit'], fallback: 500, max: 5000),
          ),
        );
        return result.fold((r) => _ok(_maintenanceJson(r)), _err);
      },
    );

    server.tool(
      'oracle_maintenance_lint',
      description:
          'Read-only health check over the memory bank: counts of memories/rules '
          'without an embedding (invisible to semantic recall), old user demands the agent '
          'never answered (requests with no messages), and vectors whose embedding model '
          'differs from the configured one (invisible to same-model recall until re-embedded '
          'via oracle_maintenance_reembed). Changes nothing.',
      toolInputSchema: const mcp.ToolInputSchema(properties: {}),
      callback: ({args, extra}) async {
        final result = await injector.get<LintUsecase>()();
        return result.fold(
          (r) => _ok({
            'clean': r.clean,
            'memoriesWithoutEmbedding': r.memoriesWithoutEmbedding,
            'rulesWithoutEmbedding': r.rulesWithoutEmbedding,
            'requestsWithoutMessages': r.requestsWithoutMessages,
            'vectorsWithStaleModel': r.vectorsWithStaleModel,
            'currentModel': r.currentModel,
          }),
          _err,
        );
      },
    );

    server.tool(
      'oracle_maintenance_reembed',
      description:
          'Re-embed rows whose vector is missing or was produced by a different '
          'embedding model, using the currently configured embedder — the fix for empty '
          'semantic recall after switching provider/model (see oracle_maintenance_lint '
          "vectorsWithStaleModel). Bounded per call; re-run while 'mayHaveMore' is true.",
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'limit': {
            'type': 'integer',
            'description':
                'Max rows to re-embed this pass (default 200, max 2000)',
          },
        },
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<ReembedUsecase>()(
          limit: _clampLimit(a['limit'], fallback: 200, max: 2000),
        );
        return result.fold(
          (r) => _ok({
            'model': r.model,
            'scanned': r.scanned,
            'reembedded': r.reembedded,
            'failed': r.failed,
            'mayHaveMore': r.mayHaveMore,
          }),
          _err,
        );
      },
    );

    server.tool(
      'oracle_maintenance_backup',
      description:
          'Write a portable snapshot of the whole memory bank (all data, embeddings '
          'included) to a .sql seed file. The schema is owned by the migrations, so the seed is '
          'data only and restores into a fresh database — commit it to version the shared memory, '
          'or bring the stack up on a new volume to restore it automatically. Restoring is a CLI/'
          "boot operation (oracle_ai restore-db), not a tool, since it's destructive on a populated DB.",
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'path': {
            'type': 'string',
            'description': 'Output file (default backups/oracle_seed.sql)',
          },
        },
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final raw = a['path']?.toString().trim();
        final path = (raw == null || raw.isEmpty)
            ? 'backups/oracle_seed.sql'
            : raw;
        try {
          final report = await DbBackupService(
            injector.get<Database>(),
          ).backup(path);
          return _ok({
            'path': report.path,
            'rows': report.rows,
            'bytes': report.bytes,
            'perTable': report.perTable,
          });
        } catch (error) {
          return _err(
            SystemFailure(
              errorMessage: 'backup failed: $error',
              stackTrace: StackTrace.current,
            ),
          );
        }
      },
    );

    // --- metrics (measurement harness) ---
    server.tool(
      'oracle_metrics_summary',
      description:
          'Aggregate session metrics per experiment label (tokens, cache-read ratio, '
          'compactions/session). Use to A/B compare runs (e.g. oracle vs baseline) and prove '
          'cost impact. Optional label filter.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'label': {
            'type': 'string',
            'description': 'Filter to one experiment label',
          },
        },
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<MetricsSummaryUsecase>()(
          label: a['label']?.toString(),
        );
        return result.fold(
          (list) => _ok(list.map(_metricsSummaryJson).toList()),
          _err,
        );
      },
    );

    server.tool(
      'oracle_metrics_session',
      description:
          'Recent per-session metric rows for a project (tokens, compactions, turns).',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'projectId': {'type': 'string'},
          'limit': {'type': 'integer'},
        },
        required: ['projectId'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<RecentMetricsUsecase>()(
          IdVO('${a['projectId'] ?? ''}'),
          limit: _clampLimit(a['limit'], fallback: 20, max: 100),
        );
        return result.fold(
          (list) => _ok(list.map(_sessionMetricJson).toList()),
          _err,
        );
      },
    );

    // --- rfc (multi-agent spec review) ---
    server.tool(
      'oracle_rfc_open',
      description:
          'Open an RFC (Request for Comments) — publish a technical spec for multi-agent '
          'review. Provide the SECTIONED body: each sections[] entry is a checklist section '
          '(context, problem, business_rules, data_model, acceptance_criteria, ...). Mark the '
          'sections your rfc_type requires with required=true and set coverage (missing|thin|covered) '
          'so completion can be gated. Anchors on organization/project/module like memories.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'projectId': {'type': 'string'},
          'organizationId': {'type': 'string'},
          'moduleId': {'type': 'string'},
          'title': {'type': 'string'},
          'rfcType': {
            'type': 'string',
            'description':
                'Checklist profile: backend|frontend|fullstack|data|infra|generic',
          },
          'authorAgent': {
            'type': 'string',
            'description':
                "Author agent id (e.g. 'claude-code', 'codex'). Default claude-code.",
          },
          'summary': {
            'type': 'string',
            'description': 'Executive summary of v1 (embedded for recall).',
          },
          'sections': {
            'type': 'array',
            'description':
                'Sectioned body. Each item: {key, content, required?, coverage?}. '
                'coverage = missing|thin|covered.',
            'items': {
              'type': 'object',
              'properties': {
                'key': {'type': 'string'},
                'content': {'type': 'string'},
                'required': {'type': 'boolean'},
                'coverage': {'type': 'string'},
              },
            },
          },
        },
        required: ['title', 'sections'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final author = '${a['authorAgent'] ?? 'claude-code'}';
        final rfc = RfcEntity(
          id: const IdVO.empty(),
          organizationId: a['organizationId'] == null
              ? null
              : IdVO('${a['organizationId']}'),
          projectId: a['projectId'] == null ? null : IdVO('${a['projectId']}'),
          moduleId: a['moduleId'] == null ? null : IdVO('${a['moduleId']}'),
          title: TextVO('${a['title'] ?? ''}'),
          rfcType: '${a['rfcType'] ?? 'generic'}',
          authorAgent: author,
        );
        final version = RfcVersionEntity(
          id: const IdVO.empty(),
          rfcId: const IdVO.empty(),
          versionNo: 1,
          summary: TextVO('${a['summary'] ?? ''}'),
          authorAgent: author,
        );
        final result = await injector.get<OpenRfcUsecase>()(
          rfc,
          version,
          _rfcSectionsArg(a['sections']),
        );
        return result.fold((r) => _ok(_rfcJson(r)), _err);
      },
    );

    server.tool(
      'oracle_rfc_list_open',
      description:
          'List RFCs still open for review (open_for_comments | in_review) in scope — how a '
          'reviewing agent discovers what to review. A module scope also surfaces its project and '
          'organization RFCs (most specific first).',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'organizationId': {'type': 'string'},
          'projectId': {'type': 'string'},
          'moduleId': {'type': 'string'},
          'limit': {'type': 'integer', 'description': 'Default 50, max 200'},
        },
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<ListOpenRfcsUsecase>()(
          organizationId: a['organizationId'] == null
              ? null
              : IdVO('${a['organizationId']}'),
          projectId: a['projectId'] == null ? null : IdVO('${a['projectId']}'),
          moduleId: a['moduleId'] == null ? null : IdVO('${a['moduleId']}'),
          limit: _clampLimit(a['limit'], fallback: 50, max: 200),
        );
        return result.fold((list) => _ok(list.map(_rfcJson).toList()), _err);
      },
    );

    server.tool(
      'oracle_rfc_get',
      description:
          'Get an RFC bundle for review: header + latest version + its sections + open '
          'findings, PLUS a `grounding` block — project rules and prior decisions relevant to the '
          'RFC content, each with its id — so your findings cite REAL Oracle entities as evidence '
          '(oracle_rfc_evidence_add) instead of guessing. Read this before reviewing so you comment '
          'against the current version and section ids.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'id': {'type': 'string'},
        },
        required: ['id'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<GetRfcUsecase>()(
          IdVO('${a['id'] ?? ''}'),
        );
        if (result.isError()) return _err(result.exceptionOrNull()!);
        final bundle = result.getOrThrow();
        final json = _rfcBundleJson(bundle);
        json['grounding'] = await _rfcGrounding(bundle);
        return _ok(json);
      },
    );

    server.tool(
      'oracle_rfc_comment',
      description:
          'Post a structured technical finding on an RFC — NOT chat. A finding must name the '
          'problem; gap/inconsistency/bug/blocker findings must also carry a proposedSolution. '
          'Anchor it to a section (sectionId) when possible. Near-duplicate findings on the same RFC '
          'are auto-demoted to status=duplicate and linked to the original.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'rfcId': {'type': 'string'},
          'versionId': {'type': 'string'},
          'sectionId': {
            'type': 'string',
            'description': 'Section this finding anchors to (strong anchor).',
          },
          'authorAgent': {'type': 'string'},
          'reviewerRole': {
            'type': 'string',
            'description':
                'architect|dba|security|backend|frontend|ux|infra|qa|domain|critic|consolidator',
          },
          'type': {
            'type': 'string',
            'description':
                'gap|inconsistency|risk|bug|question|improvement|blocker|nit',
          },
          'severity': {
            'type': 'string',
            'description': 'critical|major|minor|info',
          },
          'area': {'type': 'string'},
          'anchorQuote': {
            'type': 'string',
            'description': 'Quoted excerpt of the section this refers to.',
          },
          'problem': {'type': 'string'},
          'rationale': {'type': 'string'},
          'impact': {'type': 'string'},
          'proposedSolution': {
            'type': 'string',
            'description':
                'Required for gap/inconsistency/bug/blocker findings.',
          },
          'confidence': {
            'type': 'number',
            'description': '0..1 self-declared confidence.',
          },
          'roundNo': {'type': 'integer'},
        },
        required: ['rfcId', 'versionId', 'problem'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final comment = RfcCommentEntity(
          id: const IdVO.empty(),
          rfcId: IdVO('${a['rfcId'] ?? ''}'),
          versionId: IdVO('${a['versionId'] ?? ''}'),
          sectionId: a['sectionId'] == null ? null : IdVO('${a['sectionId']}'),
          authorAgent: '${a['authorAgent'] ?? 'claude-code'}',
          reviewerRole: a['reviewerRole']?.toString(),
          type: RfcCommentType.parse('${a['type'] ?? 'improvement'}'),
          severity: RfcSeverity.parse('${a['severity'] ?? 'info'}'),
          area: a['area']?.toString(),
          anchorQuote: a['anchorQuote']?.toString(),
          problem: TextVO('${a['problem'] ?? ''}'),
          rationale: TextVO('${a['rationale'] ?? ''}'),
          impact: TextVO('${a['impact'] ?? ''}'),
          proposedSolution: TextVO('${a['proposedSolution'] ?? ''}'),
          confidence: (a['confidence'] as num?)?.toDouble() ?? 0.5,
          roundNo: (a['roundNo'] as num?)?.toInt() ?? 0,
        );
        final result = await injector.get<AddCommentUsecase>()(comment);
        return result.fold((c) => _ok(_rfcCommentJson(c)), _err);
      },
    );

    server.tool(
      'oracle_rfc_evidence_add',
      description:
          'Attach verifiable evidence to a finding — the anti-hallucination core. An '
          'oracle_entity reference (a cited rule/memory/decision/architecture/prior_rfc by refId) '
          'must EXIST in the Oracle, or a file reference (refKind=file) must point at a real file '
          'whose content contains the excerpt, or `resolved` stays false and the finding is NOT '
          'verified — an unverified critical does not gate completion. external (URI) references are '
          'recorded but not resolved. Resolving evidence flips the comment to verified.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'commentId': {'type': 'string'},
          'kind': {
            'type': 'string',
            'description':
                'rule|memory|decision|architecture|code|api_contract|test|log|data_model|'
                'diagram|business_req|prior_rfc',
          },
          'refKind': {
            'type': 'string',
            'description':
                'oracle_entity|file|external (default oracle_entity)',
          },
          'refId': {
            'type': 'string',
            'description':
                'Id of the cited rule/memory/architecture/rfc when refKind=oracle_entity. '
                'Must resolve to a real entity or the evidence stays unresolved.',
          },
          'locator': {
            'type': 'string',
            'description': 'path:lines or URI for file/external.',
          },
          'excerpt': {'type': 'string', 'description': 'Literal quoted text.'},
        },
        required: ['commentId', 'kind'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final refKind = '${a['refKind'] ?? 'oracle_entity'}';
        final locator = a['locator']?.toString();
        final excerpt = a['excerpt']?.toString();
        // file references resolve here (dart:io): the file must exist and, when an
        // excerpt is given, contain it. oracle_entity refs are resolved in the
        // datasource (SELECT EXISTS); external refs stay unresolved.
        final fileResolved =
            refKind == 'file' && _fileEvidenceResolves(locator, excerpt);
        final evidence = RfcEvidenceEntity(
          id: const IdVO.empty(),
          commentId: IdVO('${a['commentId'] ?? ''}'),
          kind: '${a['kind'] ?? ''}',
          refKind: refKind,
          refId: a['refId'] == null ? null : IdVO('${a['refId']}'),
          locator: locator,
          excerpt: excerpt,
          resolved: fileResolved,
        );
        final result = await injector.get<AddEvidenceUsecase>()(evidence);
        return result.fold((e) => _ok(_rfcEvidenceJson(e)), _err);
      },
    );

    server.tool(
      'oracle_rfc_revise',
      description:
          'Consolidate a new RFC version (one review round). Supply the RFC id, the new '
          'versionNo, an updated summary and the FULL sectioned body — accepted findings folded in, '
          'invalidated ones removed. Retires the prior version and bumps the round.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'rfcId': {'type': 'string'},
          'versionNo': {'type': 'integer'},
          'summary': {'type': 'string'},
          'authorAgent': {'type': 'string'},
          'sections': {
            'type': 'array',
            'description':
                'Full sectioned body of the new version. Each: {key, content, required?, coverage?}.',
            'items': {
              'type': 'object',
              'properties': {
                'key': {'type': 'string'},
                'content': {'type': 'string'},
                'required': {'type': 'boolean'},
                'coverage': {'type': 'string'},
              },
            },
          },
        },
        required: ['rfcId', 'versionNo', 'sections'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final version = RfcVersionEntity(
          id: const IdVO.empty(),
          rfcId: IdVO('${a['rfcId'] ?? ''}'),
          versionNo: (a['versionNo'] as num?)?.toInt() ?? 1,
          summary: TextVO('${a['summary'] ?? ''}'),
          authorAgent: '${a['authorAgent'] ?? 'claude-code'}',
        );
        final result = await injector.get<ReviseRfcUsecase>()(
          version,
          _rfcSectionsArg(a['sections']),
        );
        return result.fold((v) => _ok(_rfcVersionJson(v)), _err);
      },
    );

    server.tool(
      'oracle_rfc_status',
      description:
          'Completion snapshot of an RFC: open critical/major findings and required-section '
          'coverage of the current version. 0 open criticals + checklist covered are NECESSARY '
          '(not sufficient) to move toward approval — the full review loop also needs novelty to '
          'settle and product decisions to be human-approved.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'rfcId': {'type': 'string'},
        },
        required: ['rfcId'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<RfcStatusUsecase>()(
          IdVO('${a['rfcId'] ?? ''}'),
        );
        return result.fold((s) => _ok(_rfcStatusJson(s)), _err);
      },
    );

    server.tool(
      'oracle_rfc_relate',
      description:
          'Link two findings in the argumentation graph — a typed edge with a reason. '
          'Refuting is as demanding as asserting: a refutation must carry its own ground. Use to '
          'connect a finding that supports/refutes/duplicates/supersedes/refines/depends_on another.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'fromComment': {'type': 'string'},
          'toComment': {'type': 'string'},
          'relation': {
            'type': 'string',
            'description':
                'supports|refutes|duplicates|supersedes|refines|depends_on',
          },
          'ground': {
            'type': 'string',
            'description':
                'architectural_conflict|business_rule|missing_evidence|out_of_scope|'
                'factual_error|redundant',
          },
          'reason': {'type': 'string'},
        },
        required: ['fromComment', 'toComment', 'relation'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final relation = RfcRelationEntity(
          id: const IdVO.empty(),
          fromComment: IdVO('${a['fromComment'] ?? ''}'),
          toComment: IdVO('${a['toComment'] ?? ''}'),
          relation: '${a['relation'] ?? ''}',
          ground: a['ground']?.toString(),
          reason: TextVO('${a['reason'] ?? ''}'),
        );
        final result = await injector.get<RelateCommentsUsecase>()(relation);
        return result.fold((r) => _ok(_rfcRelationJson(r)), _err);
      },
    );

    server.tool(
      'oracle_rfc_resolve',
      description:
          'Resolve a finding: record its outcome (accepted|rejected|deferred|duplicate) with '
          'a reason, and stamp the comment with that status. May cite the required rule (ruleId) that '
          'invalidated the finding.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'commentId': {'type': 'string'},
          'decision': {
            'type': 'string',
            'description': 'accepted|rejected|deferred|duplicate',
          },
          'ground': {'type': 'string'},
          'reason': {'type': 'string'},
          'resolverAgent': {'type': 'string'},
          'ruleId': {
            'type': 'string',
            'description': 'Rule that invalidated the finding.',
          },
        },
        required: ['commentId', 'decision'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final resolution = RfcResolutionEntity(
          id: const IdVO.empty(),
          commentId: IdVO('${a['commentId'] ?? ''}'),
          resolverAgent: '${a['resolverAgent'] ?? 'claude-code'}',
          decision: '${a['decision'] ?? ''}',
          ground: a['ground']?.toString(),
          reason: TextVO('${a['reason'] ?? ''}'),
          ruleId: a['ruleId'] == null ? null : IdVO('${a['ruleId']}'),
        );
        final result = await injector.get<ResolveCommentUsecase>()(resolution);
        return result.fold((r) => _ok(_rfcResolutionJson(r)), _err);
      },
    );

    server.tool(
      'oracle_rfc_round_start',
      description:
          'Open a review round on an RFC. Pass roundNo=0 to auto-number it to the next round. '
          'Record the participants (agents/roles) that will review this round.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'rfcId': {'type': 'string'},
          'versionId': {'type': 'string'},
          'roundNo': {
            'type': 'integer',
            'description': '0 = auto next round number.',
          },
          'participants': {
            'type': 'array',
            'description': 'Agents/roles reviewing this round.',
            'items': {'type': 'string'},
          },
        },
        required: ['rfcId'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final round = RfcRoundEntity(
          id: const IdVO.empty(),
          rfcId: IdVO('${a['rfcId'] ?? ''}'),
          versionId: a['versionId'] == null ? null : IdVO('${a['versionId']}'),
          roundNo: (a['roundNo'] as num?)?.toInt() ?? 0,
          participants: _stringList(a['participants']),
        );
        final result = await injector.get<StartRoundUsecase>()(round);
        return result.fold((r) => _ok(_rfcRoundJson(r)), _err);
      },
    );

    server.tool(
      'oracle_rfc_round_close',
      description:
          'Close a review round: computes the novelty_score (non-duplicated fraction of the '
          'round) plus the new criticals/majors over the round\'s latest findings, and stamps its end. '
          'Novelty settling is one of the necessary signals to move an RFC toward approval.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'rfcId': {'type': 'string'},
          'roundNo': {'type': 'integer'},
        },
        required: ['rfcId', 'roundNo'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<CloseRoundUsecase>()(
          rfcId: IdVO('${a['rfcId'] ?? ''}'),
          roundNo: (a['roundNo'] as num?)?.toInt() ?? 0,
        );
        return result.fold((r) => _ok(_rfcRoundJson(r)), _err);
      },
    );

    server.tool(
      'oracle_rfc_decide',
      description:
          'Record an important/product decision on an RFC — the question, the chosen option, '
          'the rationale, and the findings (commentIds) that motivated it. humanApproved=true is the '
          'human gate for product decisions.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'rfcId': {'type': 'string'},
          'question': {'type': 'string'},
          'chosenOption': {'type': 'string'},
          'rationale': {'type': 'string'},
          'commentIds': {
            'type': 'array',
            'description': 'Findings that motivated the decision.',
            'items': {'type': 'string'},
          },
          'humanApproved': {
            'type': 'boolean',
            'description': 'Human gate for product decisions.',
          },
        },
        required: ['rfcId', 'question'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final decision = RfcDecisionEntity(
          id: const IdVO.empty(),
          rfcId: IdVO('${a['rfcId'] ?? ''}'),
          question: TextVO('${a['question'] ?? ''}'),
          chosenOption: TextVO('${a['chosenOption'] ?? ''}'),
          rationale: TextVO('${a['rationale'] ?? ''}'),
          commentIds: _stringList(a['commentIds']),
          humanApproved: a['humanApproved'] == true,
        );
        final result = await injector.get<RecordDecisionUsecase>()(decision);
        return result.fold((d) => _ok(_rfcDecisionJson(d)), _err);
      },
    );

    server.tool(
      'oracle_rfc_finalize',
      description:
          'Finalize an RFC. Enforces the termination gate: no VERIFIED critical finding open '
          'AND every required section covered. If the gate holds but a decision is not humanApproved, '
          'the RFC moves to awaiting_human (an agent never self-approves a product decision). When it '
          'passes, the RFC is approved and its decisions are written back to long-term memory '
          '(kind=decision), closing the loop. Returns an error listing blockers when not ready.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'rfcId': {'type': 'string'},
        },
        required: ['rfcId'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<FinalizeRfcUsecase>()(
          IdVO('${a['rfcId'] ?? ''}'),
        );
        return result.fold((r) => _ok(_rfcJson(r)), _err);
      },
    );

    // --- flow (loop engineering) ---
    server.tool(
      'oracle_task_create',
      description:
          'Create a development task in the backlog. Anchor it to a scope '
          '(projectId / organizationId / moduleId) and, when it has a spec, link the rfcId. '
          'Creating a task and running it with a flow triggers the full development cycle.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'title': {'type': 'string'},
          'description': {'type': 'string'},
          'projectId': {'type': 'string'},
          'organizationId': {'type': 'string'},
          'moduleId': {'type': 'string'},
          'priority': {'type': 'integer', 'description': '0..100 (default 50)'},
          'source': {'type': 'string', 'description': 'human | agent | flow'},
          'rfcId': {'type': 'string'},
          'createdBy': {'type': 'string'},
        },
        required: ['title'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final task = TaskEntity(
          id: const IdVO.empty(),
          organizationId: a['organizationId'] == null
              ? null
              : IdVO('${a['organizationId']}'),
          projectId: a['projectId'] == null ? null : IdVO('${a['projectId']}'),
          moduleId: a['moduleId'] == null ? null : IdVO('${a['moduleId']}'),
          title: TextVO('${a['title'] ?? ''}'),
          description: '${a['description'] ?? ''}',
          priority: (a['priority'] as num?)?.toInt() ?? 50,
          source: '${a['source'] ?? 'human'}',
          rfcId: a['rfcId'] == null ? null : IdVO('${a['rfcId']}'),
          createdBy: '${a['createdBy'] ?? 'human'}',
        );
        final result = await injector.get<CreateTaskUsecase>()(task);
        return result.fold((t) => _ok(_taskJson(t)), _err);
      },
    );

    server.tool(
      'oracle_task_list',
      description:
          'List backlog tasks (scope union), optionally filtered by status and a text search.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'projectId': {'type': 'string'},
          'organizationId': {'type': 'string'},
          'moduleId': {'type': 'string'},
          'status': {'type': 'string'},
          'search': {'type': 'string'},
          'limit': {'type': 'integer'},
        },
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<ListTasksUsecase>()(
          organizationId: a['organizationId'] == null
              ? null
              : IdVO('${a['organizationId']}'),
          projectId: a['projectId'] == null ? null : IdVO('${a['projectId']}'),
          moduleId: a['moduleId'] == null ? null : IdVO('${a['moduleId']}'),
          status: a['status'] == null ? null : '${a['status']}',
          search: a['search'] == null ? null : '${a['search']}',
          limit: _clampLimit(a['limit'], fallback: 50, max: 200),
        );
        return result.fold((list) => _ok(list.map(_taskJson).toList()), _err);
      },
    );

    server.tool(
      'oracle_task_update',
      description:
          'Update a task: status (backlog|ready|running|blocked|done|cancelled), priority and/or description.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'id': {'type': 'string'},
          'status': {'type': 'string'},
          'priority': {'type': 'integer'},
          'description': {'type': 'string'},
        },
        required: ['id'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<UpdateTaskUsecase>()(
          IdVO('${a['id'] ?? ''}'),
          status: a['status'] == null
              ? null
              : TaskStatus.parse('${a['status']}'),
          priority: (a['priority'] as num?)?.toInt(),
          description: a['description'] == null ? null : '${a['description']}',
        );
        return result.fold((t) => _ok(_taskJson(t)), _err);
      },
    );

    server.tool(
      'oracle_flow_save',
      description:
          'Define/version a process (the "n8n workflow"): its steps (each a loop) and edges, in one '
          'call. Re-saving the same key in the same scope supersedes. Each steps[] = '
          '{key, name?, kind?, agent?, model?, role?, promptTemplate?, command?, exitCriteria?, outputSchema?, '
          'permissions?, maxIterations?, timeoutMinutes?, onFail?, position?}. Each edges[] = '
          '{from, to, condition?, verdict?} where from/to are step keys.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'key': {'type': 'string'},
          'name': {'type': 'string'},
          'projectId': {'type': 'string'},
          'organizationId': {'type': 'string'},
          'moduleId': {'type': 'string'},
          'description': {'type': 'string'},
          'orchestratorAgent': {'type': 'string'},
          'entryStepKey': {'type': 'string'},
          'budgets': {'type': 'object'},
          'steps': {
            'type': 'array',
            'items': {'type': 'object'},
          },
          'edges': {
            'type': 'array',
            'items': {'type': 'object'},
            'description':
                'Each: {from, to, condition: success|failure|verdict|always, '
                'verdict?, instruction?}. A verdict edge\'s `instruction` says WHEN to take '
                'that route — it is rendered into the step agent\'s prompt, making any node '
                'a decision point.',
          },
        },
        required: ['key', 'name', 'steps'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final flow = FlowEntity(
          id: const IdVO.empty(),
          organizationId: a['organizationId'] == null
              ? null
              : IdVO('${a['organizationId']}'),
          projectId: a['projectId'] == null ? null : IdVO('${a['projectId']}'),
          moduleId: a['moduleId'] == null ? null : IdVO('${a['moduleId']}'),
          key: '${a['key'] ?? ''}',
          name: TextVO('${a['name'] ?? ''}'),
          description: '${a['description'] ?? ''}',
          orchestratorAgent: '${a['orchestratorAgent'] ?? 'claude-code'}',
          entryStepKey: '${a['entryStepKey'] ?? ''}',
          budgets: _jsonField(a['budgets'], '{}'),
        );
        final result = await injector.get<SaveFlowUsecase>()(
          flow,
          _flowStepsArg(a['steps']),
          _flowEdgesArg(a['edges']),
        );
        return result.fold((g) => _ok(_flowGraphJson(g)), _err);
      },
    );

    server.tool(
      'oracle_flow_list',
      description: 'List available processes (latest only), scope union.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'projectId': {'type': 'string'},
          'organizationId': {'type': 'string'},
          'moduleId': {'type': 'string'},
          'limit': {'type': 'integer'},
        },
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<ListFlowsUsecase>()(
          organizationId: a['organizationId'] == null
              ? null
              : IdVO('${a['organizationId']}'),
          projectId: a['projectId'] == null ? null : IdVO('${a['projectId']}'),
          moduleId: a['moduleId'] == null ? null : IdVO('${a['moduleId']}'),
          limit: _clampLimit(a['limit'], fallback: 50, max: 200),
        );
        return result.fold((list) => _ok(list.map(_flowJson).toList()), _err);
      },
    );

    server.tool(
      'oracle_flow_get',
      description:
          'The full definition (graph) of a process, by id or by key + scope.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'id': {'type': 'string'},
          'key': {'type': 'string'},
          'projectId': {'type': 'string'},
          'organizationId': {'type': 'string'},
          'moduleId': {'type': 'string'},
        },
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<GetFlowUsecase>()(
          id: a['id'] == null ? null : IdVO('${a['id']}'),
          key: a['key'] == null ? null : '${a['key']}',
          organizationId: a['organizationId'] == null
              ? null
              : IdVO('${a['organizationId']}'),
          projectId: a['projectId'] == null ? null : IdVO('${a['projectId']}'),
          moduleId: a['moduleId'] == null ? null : IdVO('${a['moduleId']}'),
        );
        return result.fold((g) => _ok(_flowGraphJson(g)), _err);
      },
    );

    server.tool(
      'oracle_flow_run_start',
      description:
          'Enqueue a run of a flow for a task (status queued). Resolve the flow by flowId or by '
          'flowKey + scope. The Flow Runner (Studio or `oracle_ai flow-worker`) executes it.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'taskId': {'type': 'string'},
          'flowId': {'type': 'string'},
          'flowKey': {'type': 'string'},
          'projectId': {'type': 'string'},
          'organizationId': {'type': 'string'},
          'moduleId': {'type': 'string'},
          'budgets': {'type': 'object'},
          'startedBy': {'type': 'string'},
        },
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<StartFlowRunUsecase>()(
          taskId: a['taskId'] == null ? null : IdVO('${a['taskId']}'),
          flowId: a['flowId'] == null ? null : IdVO('${a['flowId']}'),
          flowKey: a['flowKey'] == null ? null : '${a['flowKey']}',
          organizationId: a['organizationId'] == null
              ? null
              : IdVO('${a['organizationId']}'),
          projectId: a['projectId'] == null ? null : IdVO('${a['projectId']}'),
          moduleId: a['moduleId'] == null ? null : IdVO('${a['moduleId']}'),
          budgets: a['budgets'] == null ? null : _jsonField(a['budgets'], '{}'),
          startedBy: '${a['startedBy'] ?? 'human'}',
        );
        return result.fold((r) => _ok(_flowRunJson(r)), _err);
      },
    );

    server.tool(
      'oracle_flow_run_status',
      description:
          'Monitoring snapshot of a run: header + step iterations + blackboard context + artifacts + '
          'recent timeline events. Each step links its captured session id.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'runId': {'type': 'string'},
        },
        required: ['runId'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<FlowRunStatusUsecase>()(
          IdVO('${a['runId'] ?? ''}'),
        );
        return result.fold((b) => _ok(_flowRunBundleJson(b)), _err);
      },
    );

    server.tool(
      'oracle_flow_run_list',
      description:
          'Recent / active runs, optionally scoped by project and status.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'projectId': {'type': 'string'},
          'status': {'type': 'string'},
          'limit': {'type': 'integer'},
        },
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<ListFlowRunsUsecase>()(
          projectId: a['projectId'] == null ? null : IdVO('${a['projectId']}'),
          status: a['status'] == null ? null : '${a['status']}',
          limit: _clampLimit(a['limit'], fallback: 50, max: 200),
        );
        return result.fold(
          (list) => _ok(list.map(_flowRunJson).toList()),
          _err,
        );
      },
    );

    server.tool(
      'oracle_flow_run_control',
      description:
          'Control a run: action = pause | resume | cancel. Recorded on the timeline.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'runId': {'type': 'string'},
          'action': {'type': 'string'},
        },
        required: ['runId', 'action'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        if ((Platform.environment['ORACLE_RUN_ID'] ?? '').isNotEmpty) {
          return _flowPinError('action', 'human or operator');
        }
        final result = await injector.get<ControlFlowRunUsecase>()(
          IdVO('${a['runId'] ?? ''}'),
          '${a['action'] ?? ''}',
        );
        return result.fold((r) => _ok(_flowRunJson(r)), _err);
      },
    );

    server.tool(
      'oracle_flow_gate_decide',
      description:
          'Resolve a human gate on a run parked in awaiting_human. approved=true releases it back to '
          'running; false fails it. The decision is stamped on the timeline (human-in-the-loop audit).',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'runId': {'type': 'string'},
          'approved': {'type': 'boolean'},
          'reason': {'type': 'string'},
        },
        required: ['runId', 'approved'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        if ((Platform.environment['ORACLE_RUN_ID'] ?? '').isNotEmpty) {
          return _flowPinError('decision', 'human or operator');
        }
        final result = await injector.get<DecideGateUsecase>()(
          IdVO('${a['runId'] ?? ''}'),
          approved: a['approved'] == true,
          reason: a['reason'] == null ? null : '${a['reason']}',
        );
        return result.fold((r) => _ok(_flowRunJson(r)), _err);
      },
    );

    server.tool(
      'oracle_flow_step_context',
      description:
          'The bundle a step\'s agent pulls at start: the task, the run, the step definition, the '
          'blackboard context, prior step reports and artifacts. Call this FIRST inside a step. '
          'The response includes runStep.claimToken — pass it to oracle_flow_step_report.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'runStepId': {'type': 'string'},
        },
        required: ['runStepId'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final denied = _denyForeignFlowTarget(
          runStepId: '${a['runStepId'] ?? ''}',
        );
        if (denied != null) return denied;
        final result = await injector.get<StepContextUsecase>()(
          IdVO('${a['runStepId'] ?? ''}'),
        );
        return result.fold((c) => _ok(_stepContextJson(c)), _err);
      },
    );

    server.tool(
      'oracle_flow_context_put',
      description:
          'Write a key→value entry to the run\'s blackboard (upsert on runId+key). value is any JSON.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'runId': {'type': 'string'},
          'runStepId': {'type': 'string'},
          'key': {'type': 'string'},
          'value': {},
        },
        required: ['runId', 'key'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final denied = _denyForeignFlowTarget(
          runId: '${a['runId'] ?? ''}',
          runStepId: a['runStepId'] == null ? null : '${a['runStepId']}',
        );
        if (denied != null) return denied;
        final result = await injector.get<PutContextUsecase>()(
          FlowRunContextEntity(
            runId: IdVO('${a['runId'] ?? ''}'),
            key: '${a['key'] ?? ''}',
            // Encode the raw value to valid JSON (a string → "x", an object → {…})
            // so the jsonb cast never rejects a bare scalar.
            value: a['value'] == null ? '{}' : jsonEncode(a['value']),
            updatedBy: a['runStepId'] == null
                ? null
                : IdVO('${a['runStepId']}'),
          ),
        );
        return result.fold(
          (c) => _ok({'runId': c.runId.value, 'key': c.key, 'value': c.value}),
          _err,
        );
      },
    );

    server.tool(
      'oracle_flow_artifact_add',
      description:
          'Record an artifact a step produced: kind = branch|commit|pr|rfc|doc|file|memory|other, '
          'locator = URL / path / id.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'runId': {'type': 'string'},
          'runStepId': {'type': 'string'},
          'kind': {'type': 'string'},
          'locator': {'type': 'string'},
          'meta': {'type': 'object'},
        },
        required: ['runId', 'kind', 'locator'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final denied = _denyForeignFlowTarget(
          runId: '${a['runId'] ?? ''}',
          runStepId: a['runStepId'] == null ? null : '${a['runStepId']}',
        );
        if (denied != null) return denied;
        final result = await injector.get<AddArtifactUsecase>()(
          FlowArtifactEntity(
            id: const IdVO.empty(),
            runId: IdVO('${a['runId'] ?? ''}'),
            runStepId: a['runStepId'] == null
                ? null
                : IdVO('${a['runStepId']}'),
            kind: '${a['kind'] ?? 'other'}',
            locator: '${a['locator'] ?? ''}',
            meta: _jsonField(a['meta'], '{}'),
          ),
        );
        return result.fold((art) => _ok(_flowArtifactJson(art)), _err);
      },
    );

    server.tool(
      'oracle_flow_step_report',
      description:
          'Close a step from your side — the structured handoff. status = done | blocked. Store what '
          'you did, the outputs, files touched and open questions. This triggers the runner to run the '
          'verifiers (outside you) and advance; do NOT self-approve. Pass the claimToken exactly as '
          'given in your step prompt (or from oracle_flow_step_context runStep.claimToken) — without '
          'it the report is rejected when the host does not forward the worker\'s environment.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'runStepId': {'type': 'string'},
          'summary': {'type': 'string'},
          'status': {'type': 'string', 'description': 'done | blocked'},
          'outputs': {'type': 'object'},
          'filesTouched': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'openQuestions': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'claimToken': {
            'type': 'string',
            'description':
                'The step attempt\'s claim token, given literally in the step prompt and in '
                'oracle_flow_step_context (runStep.claimToken). Required in practice: the '
                'environment fallback only works when the host forwards ORACLE_RUN_STEP_TOKEN.',
          },
        },
        required: ['runStepId', 'summary'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final denied = _denyForeignFlowTarget(
          runStepId: '${a['runStepId'] ?? ''}',
        );
        if (denied != null) return denied;
        final reportJson = jsonEncode({
          'summary': '${a['summary'] ?? ''}',
          'outputs': a['outputs'],
          'filesTouched': _stringList(a['filesTouched']),
          'openQuestions': _stringList(a['openQuestions']),
        });
        final result = await injector.get<ReportStepUsecase>()(
          IdVO('${a['runStepId'] ?? ''}'),
          reportJson: reportJson,
          blocked: '${a['status'] ?? 'done'}' == 'blocked',
          claimToken:
              '${a['claimToken'] ?? Platform.environment['ORACLE_RUN_STEP_TOKEN'] ?? ''}',
        );
        return result.fold((s) => _ok(_flowRunStepJson(s)), _err);
      },
    );
  }

  /// MCP safety hints used by every Oracle tool. Oracle is a closed-world local
  /// service; reads never mutate it, normal writes are additive/stateful, and
  /// only explicit retire/forget operations are destructive.
  static mcp.ToolAnnotations toolAnnotationsFor(String toolName) {
    const readOnly = <String>{
      'oracle_status',
      'oracle_project_list',
      'oracle_project_resolve',
      'oracle_organization_list',
      'oracle_module_list',
      'oracle_module_resolve',
      'oracle_memory_get',
      'oracle_memory_search',
      'oracle_rule_search',
      'oracle_rules_for_task',
      'oracle_architecture_get',
      'oracle_architecture_search',
      'oracle_skill_get',
      'oracle_skill_list',
      'oracle_skill_search',
      'oracle_session_brief',
      'oracle_session_history',
      'oracle_session_recent',
      'oracle_session_requests',
      'oracle_request_messages',
      'oracle_request_search',
      'oracle_handoff_pending',
      'oracle_metrics_session',
      'oracle_metrics_summary',
      'oracle_rfc_get',
      'oracle_rfc_list_open',
      'oracle_rfc_status',
      'oracle_task_list',
      'oracle_flow_get',
      'oracle_flow_list',
      'oracle_flow_run_list',
      'oracle_flow_run_status',
      'oracle_flow_step_context',
    };
    const destructive = <String>{
      'oracle_memory_forget',
      'oracle_rule_retire',
      'oracle_architecture_retire',
      'oracle_skill_retire',
    };
    const idempotent = <String>{
      'oracle_flow_context_put',
      'oracle_flow_step_report',
      'oracle_project_register',
      'oracle_organization_register',
      'oracle_memory_save',
      'oracle_rule_save',
      'oracle_architecture_save',
      'oracle_skill_save',
      'oracle_flow_save',
    };
    final isReadOnly = readOnly.contains(toolName);
    return mcp.ToolAnnotations(
      title: toolName,
      readOnlyHint: isReadOnly,
      destructiveHint: !isReadOnly && destructive.contains(toolName),
      idempotentHint: !isReadOnly && idempotent.contains(toolName),
      openWorldHint: false,
    );
  }

  // ── helpers ──

  /// Resolves a file evidence reference: the file in [locator] must exist and,
  /// when an [excerpt] is given, contain it (whitespace-normalized). [locator]
  /// may carry a trailing `:line` / `:start-end` range, which is stripped.
  static bool _fileEvidenceResolves(String? locator, String? excerpt) {
    if (locator == null || locator.trim().isEmpty) return false;
    var path = locator.trim();
    final range = RegExp(r'^(.*?):\d+(?:-\d+)?$').firstMatch(path);
    if (range != null) path = range.group(1)!;
    final file = File(path);
    if (!file.existsSync()) return false;
    if (excerpt == null || excerpt.trim().isEmpty) return true;
    try {
      String norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
      return norm(file.readAsStringSync()).contains(norm(excerpt));
    } catch (_) {
      return false;
    }
  }

  static List<String> _stringList(Object? value) =>
      value is List ? value.map((e) => e.toString()).toList() : const [];

  /// Clamps a caller-supplied `limit` into `[1, max]`, defaulting to [fallback]
  /// when absent/invalid — so an oversized value can't force a giant scan or
  /// materialize a huge result on the shared daemon.
  /// Flow-run attribution: the runner exports ORACLE_PROJECT_ID to the step
  /// agent, and this MCP process (spawned by the agent) inherits it. When set,
  /// it pins the project for resolution-style tools — a worktree/temp cwd must
  /// never mint a new project for a run.
  static IdVO? get _envProjectId {
    final v = Platform.environment['ORACLE_PROJECT_ID']?.trim();
    return (v == null || v.isEmpty) ? null : IdVO(v);
  }

  /// Internal Oracle session created by the flow runner for this iteration.
  static IdVO? get _envSessionId {
    final v = Platform.environment['ORACLE_SESSION_ID']?.trim();
    return (v == null || v.isEmpty) ? null : IdVO(v);
  }

  static mcp.CallToolResult? _denyForeignFlowTarget({
    String? runId,
    String? runStepId,
  }) {
    final pinnedRun = Platform.environment['ORACLE_RUN_ID']?.trim();
    final pinnedStep = Platform.environment['ORACLE_RUN_STEP_ID']?.trim();
    if (pinnedRun != null &&
        pinnedRun.isNotEmpty &&
        runId != null &&
        runId != pinnedRun) {
      return _flowPinError('runId', pinnedRun);
    }
    if (pinnedStep != null &&
        pinnedStep.isNotEmpty &&
        runStepId != null &&
        runStepId != pinnedStep) {
      return _flowPinError('runStepId', pinnedStep);
    }
    return null;
  }

  static mcp.CallToolResult _flowPinError(String field, String expected) =>
      mcp.CallToolResult.fromContent(
        content: [
          mcp.TextContent(
            text: jsonEncode({
              'error': 'This agent is pinned to its active process step',
              'field': field,
              'expected': expected,
            }),
          ),
        ],
        isError: true,
      );

  static int _clampLimit(Object? raw, {int fallback = 10, int max = 50}) {
    // Tolerate a string-typed number ("20"), a frequent LLM tool-call shape, and
    // any other type, degrading to [fallback] instead of throwing a TypeError.
    final n = switch (raw) {
      final num v => v.toInt(),
      final String v => int.tryParse(v.trim()) ?? fallback,
      _ => fallback,
    };
    if (n < 1) return 1;
    return n > max ? max : n;
  }

  /// Caps a raw-capture field (message content / request text) so list and
  /// history payloads stay cheap in the agent's context. Truncation keeps the
  /// leading content intact (no whitespace reflow, so code survives up to the
  /// cut). Curated text (memory/rule/architecture bodies) is returned in full.
  static String _snippet(String text, [int max = 600]) =>
      text.length <= max ? text : '${text.substring(0, max)}…';

  static mcp.CallToolResult _ok(Object json) => mcp.CallToolResult.fromContent(
    content: [mcp.TextContent(text: jsonEncode(json))],
  );

  static mcp.CallToolResult _err(SystemFailure failure) =>
      mcp.CallToolResult.fromContent(
        content: [
          mcp.TextContent(
            text: jsonEncode({
              'error': failure.errorMessage,
              'fields': failure.fields.map((f) => f.toMap()).toList(),
            }),
          ),
        ],
        isError: true,
      );

  // ── flow (loop engineering) helpers ──

  /// Normalizes a jsonb tool arg to VALID JSON text so the `::jsonb` cast never
  /// rejects it: a Map/List is encoded; a String that is already valid JSON is
  /// kept, otherwise it is encoded as a JSON string (`dart test` → `"dart test"`);
  /// null/empty degrades to [def].
  static String _jsonField(Object? v, String def) {
    if (v == null) return def;
    if (v is String) {
      final t = v.trim();
      if (t.isEmpty) return def;
      try {
        jsonDecode(t);
        return t;
      } catch (_) {
        return jsonEncode(v);
      }
    }
    return jsonEncode(v);
  }

  static Map<String, dynamic> _taskJson(TaskEntity t) => {
    'id': t.id.value,
    'organizationId': t.organizationId?.value,
    'projectId': t.projectId?.value,
    'moduleId': t.moduleId?.value,
    'title': t.title.value,
    'description': t.description,
    'status': t.status.code,
    'priority': t.priority,
    'source': t.source,
    'rfcId': t.rfcId?.value,
    'createdBy': t.createdBy,
    'createdAt': t.createdAt?.toIso8601String(),
    'updatedAt': t.updatedAt?.toIso8601String(),
  };

  static Map<String, dynamic> _flowJson(FlowEntity f) => {
    'id': f.id.value,
    'organizationId': f.organizationId?.value,
    'projectId': f.projectId?.value,
    'moduleId': f.moduleId?.value,
    'key': f.key,
    'name': f.name.value,
    'description': f.description,
    'orchestratorAgent': f.orchestratorAgent,
    'entryStepKey': f.entryStepKey,
    'budgets': f.budgets,
    'versionNo': f.versionNo,
    'isLatest': f.isLatest,
    'createdAt': f.createdAt?.toIso8601String(),
    'updatedAt': f.updatedAt?.toIso8601String(),
  };

  static Map<String, dynamic> _flowStepJson(FlowStepEntity s) => {
    'id': s.id.value,
    'stepKey': s.stepKey,
    'name': s.name,
    'kind': s.kind.code,
    'agent': s.agent,
    'model': s.model,
    'role': s.role,
    'promptTemplate': s.promptTemplate,
    'command': s.command,
    'outputSchema': s.outputSchema,
    'permissions': s.permissions,
    'exitCriteria': s.exitCriteria,
    'maxIterations': s.maxIterations,
    'tokenBudget': s.tokenBudget,
    'timeoutMinutes': s.timeoutMinutes,
    'onFail': s.onFail,
    'config': s.config,
    'position': s.position,
  };

  static Map<String, dynamic> _flowEdgeJson(FlowEdgeEntity e) => {
    'id': e.id.value,
    'fromStep': e.fromStep.value,
    'toStep': e.toStep.value,
    'condition': e.condition,
    'verdictValue': e.verdictValue,
    'instruction': e.instruction,
  };

  static Map<String, dynamic> _flowGraphJson(FlowGraph g) => {
    'flow': _flowJson(g.flow),
    'steps': g.steps.map(_flowStepJson).toList(),
    'edges': g.edges.map(_flowEdgeJson).toList(),
  };

  static Map<String, dynamic> _flowRunJson(FlowRunEntity r) => {
    'id': r.id.value,
    'flowId': r.flowId.value,
    'taskId': r.taskId?.value,
    'projectId': r.projectId?.value,
    'status': r.status.code,
    'currentStepId': r.currentStepId?.value,
    'branchName': r.branchName,
    'worktreePath': r.worktreePath,
    'tokensUsed': r.tokensUsed,
    'startedBy': r.startedBy,
    'error': r.error,
    'createdAt': r.createdAt?.toIso8601String(),
    'startedAt': r.startedAt?.toIso8601String(),
    'endedAt': r.endedAt?.toIso8601String(),
  };

  static Map<String, dynamic> _flowRunStepJson(FlowRunStepEntity s) => {
    'id': s.id.value,
    'runId': s.runId.value,
    'stepId': s.stepId.value,
    'iteration': s.iteration,
    'status': s.status.code,
    'agent': s.agent,
    'sessionId': s.sessionId?.value,
    'report': s.report,
    'verifier': s.verifier,
    'tokensUsed': s.tokensUsed,
    'startedAt': s.startedAt?.toIso8601String(),
    'endedAt': s.endedAt?.toIso8601String(),
  };

  static Map<String, dynamic> _flowArtifactJson(FlowArtifactEntity a) => {
    'id': a.id.value,
    'runStepId': a.runStepId?.value,
    'kind': a.kind,
    'locator': a.locator,
    'meta': a.meta,
    'createdAt': a.createdAt?.toIso8601String(),
  };

  static Map<String, dynamic> _flowRunBundleJson(FlowRunBundle b) => {
    'run': _flowRunJson(b.run),
    'steps': b.steps.map(_flowRunStepJson).toList(),
    'context': b.context
        .map(
          (c) => {
            'key': c.key,
            'value': c.value,
            'updatedAt': c.updatedAt?.toIso8601String(),
          },
        )
        .toList(),
    'artifacts': b.artifacts.map(_flowArtifactJson).toList(),
    'events': b.events
        .map(
          (e) => {
            'kind': e.kind,
            'payload': e.payload,
            'runStepId': e.runStepId?.value,
            'createdAt': e.createdAt?.toIso8601String(),
          },
        )
        .toList(),
  };

  static Map<String, dynamic> _stepContextJson(StepContext c) => {
    // claimToken is exposed HERE (and only here): agent hosts that spawn the
    // MCP server without the worker's environment (Codex) cannot rely on the
    // ORACLE_RUN_STEP_TOKEN fallback, and the report is rejected without it.
    'runStep': {
      ..._flowRunStepJson(c.runStep),
      'claimToken': c.runStep.claimToken,
    },
    'run': _flowRunJson(c.run),
    'step': _flowStepJson(c.step),
    'task': c.task == null ? null : _taskJson(c.task!),
    'context': c.context.map((x) => {'key': x.key, 'value': x.value}).toList(),
    'priorReports': c.priorReports
        .map(
          (s) => {
            'stepId': s.stepId.value,
            'status': s.status.code,
            'report': s.report,
          },
        )
        .toList(),
    'artifacts': c.artifacts.map(_flowArtifactJson).toList(),
  };

  static List<FlowStepEntity> _flowStepsArg(Object? raw) {
    if (raw is! List) return const [];
    final maps = raw.whereType<Map<String, dynamic>>().toList();
    return [
      for (var i = 0; i < maps.length; i++)
        () {
          final s = maps[i].cast<String, dynamic>();
          return FlowStepEntity(
            id: const IdVO.empty(),
            flowId: const IdVO.empty(),
            stepKey: '${s['key'] ?? s['stepKey'] ?? ''}',
            name: '${s['name'] ?? ''}',
            kind: FlowStepKind.parse('${s['kind'] ?? 'agent'}'),
            agent: s['agent']?.toString(),
            model: s['model']?.toString(),
            role: s['role']?.toString(),
            promptTemplate: '${s['promptTemplate'] ?? s['prompt'] ?? ''}',
            command: s['command']?.toString(),
            outputSchema: s['outputSchema'] == null
                ? null
                : _jsonField(s['outputSchema'], '{}'),
            permissions: _jsonField(s['permissions'], '{}'),
            exitCriteria: _jsonField(s['exitCriteria'], '{}'),
            maxIterations: (s['maxIterations'] as num?)?.toInt() ?? 3,
            tokenBudget: (s['tokenBudget'] as num?)?.toInt(),
            timeoutMinutes: (s['timeoutMinutes'] as num?)?.toInt() ?? 30,
            onFail: '${s['onFail'] ?? 'park'}',
            config: _jsonField(s['config'], '{}'),
            position: (s['position'] as num?)?.toInt() ?? i,
          );
        }(),
    ];
  }

  static List<FlowEdgeEntity> _flowEdgesArg(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().map((m) {
      final e = m.cast<String, dynamic>();
      return FlowEdgeEntity(
        id: const IdVO.empty(),
        flowId: const IdVO.empty(),
        fromStep: IdVO('${e['from'] ?? e['fromStep'] ?? ''}'),
        toStep: IdVO('${e['to'] ?? e['toStep'] ?? ''}'),
        condition: '${e['condition'] ?? 'success'}',
        verdictValue: e['verdict']?.toString() ?? e['verdictValue']?.toString(),
        instruction: e['instruction']?.toString(),
      );
    }).toList();
  }

  static Map<String, dynamic> _projectJson(ProjectEntity p) => {
    'id': p.id.value,
    'organizationId': p.organizationId?.value,
    'name': p.name.value,
    'description': p.description?.value,
    'repoPath': p.repoPath,
    'createdAt': p.createdAt?.toIso8601String(),
    'updatedAt': p.updatedAt?.toIso8601String(),
  };

  static Map<String, dynamic> _moduleJson(ModuleEntity m) => {
    'id': m.id.value,
    'projectId': m.projectId.value,
    'key': m.key,
    'name': m.name.value,
    'path': m.path,
    'description': m.description?.value,
    'createdAt': m.createdAt?.toIso8601String(),
    'updatedAt': m.updatedAt?.toIso8601String(),
  };

  /// Fire-and-forget log of one agent recall (never blocks or fails the search).
  static void _logSearch({
    required String tool,
    required String query,
    required Map<String, dynamic> scope,
    Map<String, dynamic> filters = const {},
    required List<Map<String, dynamic>> results,
    required int latencyMs,
  }) {
    try {
      injector.get<LogSearchUsecase>()(
        AgentSearchEntity(
          id: const IdVO.empty(),
          sessionId: _envSessionId,
          tool: tool,
          query: query,
          scope: scope,
          filters: filters,
          results: results,
          hits: results.length,
          latencyMs: latencyMs,
        ),
      );
    } catch (_) {
      /* logging is best-effort */
    }
  }

  /// A compact, immutable snapshot makes the audit useful even if the source
  /// record is later superseded or retired. Full content remains available via
  /// the source id; the snapshot is capped to keep search logging inexpensive.
  static Map<String, dynamic> _searchResult({
    required String id,
    required num score,
    required String title,
    required String subtitle,
    required String content,
  }) {
    final clean = content.trim();
    return {
      'id': id,
      'score': score,
      'title': title,
      'subtitle': subtitle,
      'content': clean.length <= 1600 ? clean : '${clean.substring(0, 1600)}…',
    };
  }

  /// The scope map (organization/project/module ids) stored with a search log.
  static Map<String, dynamic> _scopeOf(Map<String, dynamic> a) => {
    if (a['organizationId'] != null) 'organizationId': '${a['organizationId']}',
    if (a['projectId'] != null) 'projectId': '${a['projectId']}',
    if (a['moduleId'] != null) 'moduleId': '${a['moduleId']}',
  };

  /// A cwd relative to its git root — the module subpath (empty at the root).
  static String _relativeSubpath(String cwd) {
    final root = repoRootOf(cwd).replaceAll(r'\', '/');
    final c = cwd.trim().replaceAll(r'\', '/');
    if (c.length > root.length && c.startsWith(root)) {
      return c.substring(root.length).replaceAll(RegExp(r'^/+|/+$'), '');
    }
    return '';
  }

  static Map<String, dynamic> _memoryJson(MemoryEntity m) => {
    'id': m.id.value,
    'organizationId': m.organizationId?.value,
    'projectId': m.projectId?.value,
    'key': m.key,
    'tier': m.tier.code,
    'kind': m.kind.code,
    'title': m.title.value,
    'body': m.body.value,
    'tags': m.tags,
    'importance': m.importance,
    'embeddingModel': m.embeddingModel,
    'isLatest': m.isLatest,
    'createdAt': m.createdAt?.toIso8601String(),
  };

  static Map<String, dynamic> _ruleJson(RuleEntity r) => {
    'id': r.id.value,
    'organizationId': r.organizationId?.value,
    'projectId': r.projectId?.value,
    'key': r.key,
    'scope': r.scope,
    'title': r.title.value,
    'content': r.content.value,
    'severity': r.severity.code,
    'priority': r.priority,
    'tags': r.tags,
    'isLatest': r.isLatest,
    'createdAt': r.createdAt?.toIso8601String(),
  };

  static Map<String, dynamic> _skillJson(SkillEntity s) => {
    'id': s.id.value,
    'organizationId': s.organizationId?.value,
    'projectId': s.projectId?.value,
    'key': s.key,
    'name': s.name.value,
    'description': s.description.value,
    'content': s.content.value,
    'tags': s.tags,
    'scope': s.projectId != null
        ? 'project'
        : (s.organizationId != null ? 'organization' : 'global'),
    'isLatest': s.isLatest,
    'createdAt': s.createdAt?.toIso8601String(),
  };

  /// Memory JSON augmented with a near-duplicate signal: latest same-model
  /// memories close to the one just saved, so the agent can consolidate (reuse
  /// a key / supersedes) instead of piling up duplicates. Uses the embedding
  /// already computed by the save — no extra embedding call.
  static Future<Map<String, dynamic>> _memoryJsonWithSimilar(
    MemoryEntity m,
  ) async {
    final json = _memoryJson(m);
    if (m.embedding == null || m.embeddingModel == null) return json;
    final near = await injector.get<MemoryRepository>().nearestByEmbedding(
      organizationId: m.organizationId,
      projectId: m.projectId,
      embedding: m.embedding!,
      embeddingModel: m.embeddingModel!,
      excludeId: m.id,
    );
    if (near.isNotEmpty) {
      json['similar'] = near
          .map(
            (n) => {
              'id': n.memory.id.value,
              'key': n.memory.key,
              'title': n.memory.title.value,
              'distance': double.parse(n.distance.toStringAsFixed(3)),
            },
          )
          .toList();
      json['similarNote'] =
          'Near-duplicate memories already exist. To avoid piling up '
          'duplicates, prefer updating one of these — re-save with its key, or pass '
          'supersedes=<id> — instead of keeping a separate near-identical memory.';
    }
    return json;
  }

  /// Rule JSON augmented with the same near-duplicate signal, so the agent
  /// refines an existing rule (reuse its key) instead of creating a duplicate.
  static Future<Map<String, dynamic>> _ruleJsonWithSimilar(RuleEntity r) async {
    final json = _ruleJson(r);
    if (r.embedding == null || r.embeddingModel == null) return json;
    final near = await injector.get<RuleRepository>().nearestByEmbedding(
      organizationId: r.organizationId,
      projectId: r.projectId,
      embedding: r.embedding!,
      embeddingModel: r.embeddingModel!,
      excludeId: r.id,
    );
    if (near.isNotEmpty) {
      json['similar'] = near
          .map(
            (n) => {
              'id': n.rule.id.value,
              'key': n.rule.key,
              'title': n.rule.title.value,
              'distance': double.parse(n.distance.toStringAsFixed(3)),
            },
          )
          .toList();
      json['similarNote'] =
          'A similar rule already exists. Prefer refining it (re-save with '
          'its key) over creating a near-duplicate rule.';
    }
    return json;
  }

  /// Skill JSON augmented with the same near-duplicate signal, so the agent
  /// refines an existing skill (reuse its key) instead of creating a duplicate.
  static Future<Map<String, dynamic>> _skillJsonWithSimilar(
    SkillEntity s,
  ) async {
    final json = _skillJson(s);
    if (s.embedding == null || s.embeddingModel == null) return json;
    final near = await injector.get<SkillRepository>().nearestByEmbedding(
      organizationId: s.organizationId,
      projectId: s.projectId,
      embedding: s.embedding!,
      embeddingModel: s.embeddingModel!,
      excludeId: s.id,
    );
    if (near.isNotEmpty) {
      json['similar'] = near
          .map(
            (n) => {
              'id': n.skill.id.value,
              'key': n.skill.key,
              'name': n.skill.name.value,
              'distance': double.parse(n.distance.toStringAsFixed(3)),
            },
          )
          .toList();
      json['similarNote'] =
          'A similar skill already exists. Prefer refining it (re-save with '
          'its key) over creating a near-duplicate skill.';
    }
    return json;
  }

  static Map<String, dynamic> _organizationJson(OrganizationEntity p) => {
    'id': p.id.value,
    'name': p.name.value,
    'description': p.description?.value,
    'createdAt': p.createdAt?.toIso8601String(),
  };

  static Map<String, dynamic> _architectureJson(ArchitectureEntity a) => {
    'id': a.id.value,
    'organizationId': a.organizationId?.value,
    'projectId': a.projectId?.value,
    'moduleId': a.moduleId?.value,
    'area': a.area,
    'content': a.content.value,
    'isLatest': a.isLatest,
    'createdAt': a.createdAt?.toIso8601String(),
  };

  /// Max chars of a body/content returned by a SEARCH hit. Search is a discovery
  /// step, so hits default to a snippet + id (cheap in context); the agent fetches
  /// the full text with the get-by-id tool, or passes `full:true` to inline it.
  static const _searchSnippetChars = 240;

  static Map<String, dynamic> _memoryHit(
    MemorySearchResult e, {
    required bool full,
  }) => full
      ? {'memory': _memoryJson(e.memory), 'score': e.score}
      : {
          'id': e.memory.id.value,
          'kind': e.memory.kind.code,
          'title': e.memory.title.value,
          'snippet': _snippet(e.memory.body.value, _searchSnippetChars),
          'importance': e.memory.importance,
          'score': e.score,
        };

  static Map<String, dynamic> _ruleHit(
    RuleSearchResult e, {
    required bool full,
  }) => full
      ? {'rule': _ruleJson(e.rule), 'score': e.score}
      : {
          'id': e.rule.id.value,
          'scope': e.rule.scope,
          'title': e.rule.title.value,
          'severity': e.rule.severity.code,
          'priority': e.rule.priority,
          'snippet': _snippet(e.rule.content.value, _searchSnippetChars),
          'score': e.score,
        };

  static Map<String, dynamic> _architectureHit(
    ArchitectureSearchResult e, {
    required bool full,
  }) => full
      ? {'architecture': _architectureJson(e.architecture), 'score': e.score}
      : {
          'id': e.architecture.id.value,
          'area': e.architecture.area,
          'snippet': _snippet(
            e.architecture.content.value,
            _searchSnippetChars,
          ),
          'score': e.score,
        };

  static Map<String, dynamic> _handoffJson(HandoffEntity h) => {
    'id': h.id.value,
    'projectId': h.projectId.value,
    'sourceSessionId': h.sourceSessionId?.value,
    'fromAgent': h.fromAgent,
    'toAgent': h.toAgent,
    'summary': h.summary.value,
    'openQuestions': h.openQuestions,
    'nextSteps': h.nextSteps,
    'filesTouched': h.filesTouched,
    'status': h.status.code,
    'createdAt': h.createdAt?.toIso8601String(),
    'acceptedAt': h.acceptedAt?.toIso8601String(),
  };

  static Map<String, dynamic> _sessionJson(SessionEntity s) => {
    'id': s.id.value,
    'projectId': s.projectId.value,
    'agent': s.agent,
    'externalId': s.externalId,
    'cwd': s.cwd,
    'createdAt': s.createdAt?.toIso8601String(),
  };

  static Map<String, dynamic> _requestJson(RequestEntity r) => {
    'id': r.id.value,
    'sessionId': r.sessionId.value,
    'userText': _snippet(r.userText.value, 500),
    'createdAt': r.createdAt?.toIso8601String(),
  };

  static Map<String, dynamic> _metricsSummaryJson(MetricsSummary s) => {
    'label': s.label,
    'sessions': s.sessions,
    'inputTokens': s.inputTokens,
    'outputTokens': s.outputTokens,
    'cacheCreationTokens': s.cacheCreationTokens,
    'cacheReadTokens': s.cacheReadTokens,
    'totalTokens': s.totalTokens,
    'compactions': s.compactions,
    'turns': s.turns,
    'cacheReadRatio': double.parse(s.cacheReadRatio.toStringAsFixed(4)),
    'avgCompactionsPerSession': double.parse(
      s.avgCompactionsPerSession.toStringAsFixed(3),
    ),
    'avgTokensPerSession': double.parse(
      s.avgTokensPerSession.toStringAsFixed(1),
    ),
  };

  static Map<String, dynamic> _sessionMetricJson(SessionMetricEntity m) => {
    'externalId': m.externalId,
    'label': m.label,
    'inputTokens': m.inputTokens,
    'outputTokens': m.outputTokens,
    'cacheCreationTokens': m.cacheCreationTokens,
    'cacheReadTokens': m.cacheReadTokens,
    'totalInputTokens': m.totalInputTokens,
    'compactions': m.compactions,
    'toolUses': m.toolUses,
    'turns': m.turns,
    'cacheReadRatio': double.parse(m.cacheReadRatio.toStringAsFixed(4)),
    'updatedAt': m.updatedAt?.toIso8601String(),
  };

  static Map<String, dynamic> _maintenanceJson(MaintenanceReport r) => {
    'dryRun': r.dryRun,
    'decayedCount': r.decayedCount,
    'dedupedCount': r.dedupedCount,
    'decayed': r.decayed.map((i) => {'id': i.id, 'title': i.title}).toList(),
    'deduped': r.deduped.map((i) => {'id': i.id, 'title': i.title}).toList(),
  };

  static Map<String, dynamic> _messageJson(MessageEntity m) => {
    'id': m.id.value,
    'requestId': m.requestId.value,
    'role': m.role.code,
    'content': _snippet(m.content.value, 600),
    'tokenCount': m.tokenCount,
    'createdAt': m.createdAt?.toIso8601String(),
  };

  // ── rfc ──

  /// Parses the tool's `sections` array (list of {key, content, required?,
  /// coverage?}) into section entities. Ids/versionId are wired by the datasource.
  static List<RfcSectionEntity> _rfcSectionsArg(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().map((s) {
      return RfcSectionEntity(
        id: const IdVO.empty(),
        versionId: const IdVO.empty(),
        sectionKey: '${s['key'] ?? ''}',
        content: TextVO('${s['content'] ?? ''}'),
        required: s['required'] == true,
        coverage: '${s['coverage'] ?? 'missing'}',
      );
    }).toList();
  }

  static Map<String, dynamic> _rfcJson(RfcEntity r) => {
    'id': r.id.value,
    'organizationId': r.organizationId?.value,
    'projectId': r.projectId?.value,
    'moduleId': r.moduleId?.value,
    'title': r.title.value,
    'rfcType': r.rfcType,
    'status': r.status.code,
    'currentVersionId': r.currentVersionId?.value,
    'authorAgent': r.authorAgent,
    'roundCount': r.roundCount,
    'supersedes': r.supersedes?.value,
    'createdAt': r.createdAt?.toIso8601String(),
    'updatedAt': r.updatedAt?.toIso8601String(),
  };

  static Map<String, dynamic> _rfcVersionJson(RfcVersionEntity v) => {
    'id': v.id.value,
    'rfcId': v.rfcId.value,
    'versionNo': v.versionNo,
    'summary': v.summary.value,
    'isLatest': v.isLatest,
    'supersedes': v.supersedes?.value,
    'authorAgent': v.authorAgent,
    'createdAt': v.createdAt?.toIso8601String(),
  };

  static Map<String, dynamic> _rfcSectionJson(RfcSectionEntity s) => {
    'id': s.id.value,
    'versionId': s.versionId.value,
    'key': s.sectionKey,
    'content': s.content.value,
    'required': s.required,
    'coverage': s.coverage,
  };

  static Map<String, dynamic> _rfcCommentJson(RfcCommentEntity c) => {
    'id': c.id.value,
    'rfcId': c.rfcId.value,
    'versionId': c.versionId.value,
    'sectionId': c.sectionId?.value,
    'authorAgent': c.authorAgent,
    'reviewerRole': c.reviewerRole,
    'type': c.type.code,
    'severity': c.severity.code,
    'area': c.area,
    'anchorQuote': c.anchorQuote,
    'problem': c.problem.value,
    'rationale': c.rationale.value,
    'impact': c.impact.value,
    'proposedSolution': c.proposedSolution.value,
    'confidence': c.confidence,
    'status': c.status,
    'parentCommentId': c.parentCommentId?.value,
    'verified': c.verified,
    'roundNo': c.roundNo,
    'createdAt': c.createdAt?.toIso8601String(),
  };

  static Map<String, dynamic> _rfcBundleJson(RfcBundle b) => {
    'rfc': _rfcJson(b.rfc),
    'version': b.version == null ? null : _rfcVersionJson(b.version!),
    'sections': b.sections.map(_rfcSectionJson).toList(),
    'comments': b.comments.map(_rfcCommentJson).toList(),
  };

  /// Retrieval grounding for a reviewer: project rules and prior decisions
  /// relevant to the RFC content, each with its id, so findings can cite real
  /// entities as evidence instead of hallucinating. Best-effort — a failed or
  /// empty search degrades to empty lists and never fails the get.
  static Future<Map<String, dynamic>> _rfcGrounding(RfcBundle b) async {
    final rfc = b.rfc;
    // Concise retrieval signal — title + summary. The semantic leg (query
    // embedding vs stored rule/memory vectors) carries relevance; a longer query
    // would only over-constrain the lexical AND leg.
    final query = [
      rfc.title.value,
      b.version?.summary.value ?? '',
    ].where((s) => s.trim().isNotEmpty).join('\n');
    final rules = <Map<String, dynamic>>[];
    final decisions = <Map<String, dynamic>>[];
    if (query.trim().isEmpty) return {'rules': rules, 'decisions': decisions};
    try {
      final r = await injector.get<SearchRulesUsecase>()(
        RuleSearchFilter(
          query: query,
          organizationId: rfc.organizationId,
          projectId: rfc.projectId,
          moduleId: rfc.moduleId,
          limit: 8,
        ),
      );
      r.fold((list) {
        for (final e in list) {
          rules.add({
            'id': e.rule.id.value,
            'title': e.rule.title.value,
            'severity': e.rule.severity.code,
            'snippet': _snippet(e.rule.content.value, 300),
          });
        }
      }, (_) {});
    } catch (_) {
      /* grounding is best-effort */
    }
    try {
      final m = await injector.get<SearchMemoriesUsecase>()(
        MemorySearchFilter(
          query: query,
          organizationId: rfc.organizationId,
          projectId: rfc.projectId,
          moduleId: rfc.moduleId,
          kinds: const [MemoryKind.decision],
          limit: 5,
        ),
      );
      m.fold((list) {
        for (final e in list) {
          decisions.add({
            'id': e.memory.id.value,
            'title': e.memory.title.value,
            'snippet': _snippet(e.memory.body.value, 300),
          });
        }
      }, (_) {});
    } catch (_) {
      /* best-effort */
    }
    return {'rules': rules, 'decisions': decisions};
  }

  static Map<String, dynamic> _rfcEvidenceJson(RfcEvidenceEntity e) => {
    'id': e.id.value,
    'commentId': e.commentId.value,
    'kind': e.kind,
    'refKind': e.refKind,
    'refId': e.refId?.value,
    'locator': e.locator,
    'excerpt': e.excerpt,
    'resolved': e.resolved,
    'resolvedAt': e.resolvedAt?.toIso8601String(),
    'createdAt': e.createdAt?.toIso8601String(),
  };

  static Map<String, dynamic> _rfcStatusJson(RfcStatusReport s) => {
    'openCriticals': s.openCriticals,
    'blockingCriticals': s.blockingCriticals,
    'openMajors': s.openMajors,
    'totalComments': s.totalComments,
    'requiredSections': s.requiredSections,
    'coveredRequired': s.coveredRequired,
    'checklistComplete': s.checklistComplete,
  };

  static Map<String, dynamic> _rfcRelationJson(RfcRelationEntity r) => {
    'id': r.id.value,
    'fromComment': r.fromComment.value,
    'toComment': r.toComment.value,
    'relation': r.relation,
    'ground': r.ground,
    'reason': r.reason.value,
    'evidence': r.evidence,
    'createdAt': r.createdAt?.toIso8601String(),
  };

  static Map<String, dynamic> _rfcResolutionJson(RfcResolutionEntity r) => {
    'id': r.id.value,
    'commentId': r.commentId.value,
    'resolverAgent': r.resolverAgent,
    'decision': r.decision,
    'ground': r.ground,
    'reason': r.reason.value,
    'ruleId': r.ruleId?.value,
    'decidedAt': r.decidedAt?.toIso8601String(),
  };

  static Map<String, dynamic> _rfcRoundJson(RfcRoundEntity r) => {
    'id': r.id.value,
    'rfcId': r.rfcId.value,
    'versionId': r.versionId?.value,
    'roundNo': r.roundNo,
    'participants': r.participants,
    'newCriticals': r.newCriticals,
    'newMajors': r.newMajors,
    'noveltyScore': r.noveltyScore,
    'startedAt': r.startedAt?.toIso8601String(),
    'endedAt': r.endedAt?.toIso8601String(),
  };

  static Map<String, dynamic> _rfcDecisionJson(RfcDecisionEntity d) => {
    'id': d.id.value,
    'rfcId': d.rfcId.value,
    'question': d.question.value,
    'chosenOption': d.chosenOption.value,
    'rationale': d.rationale.value,
    'commentIds': d.commentIds,
    'humanApproved': d.humanApproved,
    'memoryId': d.memoryId?.value,
    'createdAt': d.createdAt?.toIso8601String(),
  };
}

/// Narrow adapter that guarantees every registered tool carries Oracle's
/// safety metadata. Keeping this wrapper local to the MCP server prevents a
/// future tool from accidentally falling back to mcp_dart's destructive
/// defaults.
class _OracleToolRegistrar {
  final mcp.McpServer _server;
  final DbReadyGate? _gate;

  const _OracleToolRegistrar(this._server, this._gate);

  void tool(
    String name, {
    String? description,
    mcp.ToolInputSchema? toolInputSchema,
    mcp.ToolOutputSchema? toolOutputSchema,
    required mcp.ToolCallback callback,
  }) {
    final gate = _gate;
    // oracle_status needs no database — keep it as an always-on liveness probe.
    final gated = (gate == null || name == 'oracle_status')
        ? callback
        : ({Map<String, dynamic>? args, mcp.RequestHandlerExtra? extra}) async {
            if (!gate.isReady && !await gate.wait(const Duration(seconds: 15))) {
              return mcp.CallToolResult.fromContent(
                content: [
                  mcp.TextContent(
                    text: jsonEncode({
                      'error':
                          'Oracle database is not available yet: '
                          '${gate.lastError ?? 'still connecting'}. '
                          'Check that PostgreSQL is running and reachable '
                          '(docker: oracle-postgres, port from .env) and that '
                          'this process is allowed outbound network access, '
                          'then retry this call.',
                    }),
                  ),
                ],
                isError: true,
              );
            }
            return callback(args: args, extra: extra);
          };
    _server.tool(
      name,
      description: description,
      toolInputSchema: toolInputSchema,
      toolOutputSchema: toolOutputSchema,
      annotations: OracleMcpServer.toolAnnotationsFor(name),
      callback: gated,
    );
  }
}
