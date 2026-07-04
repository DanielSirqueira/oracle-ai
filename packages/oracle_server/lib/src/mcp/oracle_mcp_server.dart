import 'dart:async';
import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart' as mcp;
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';

import '../backup/db_backup_service.dart';
import '../recall_service.dart';
import '../repo_root.dart';

/// Oracle AI MCP server (stdio). Exposes the tool surface, each tool wired to a
/// use case resolved from the DI container (which must already be committed by
/// the bootstrap).
class OracleMcpServer {
  final String name;
  final String version;

  OracleMcpServer({this.name = 'oracle-ai', this.version = '0.1.0'});

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
  Save reusable know-how with `oracle_skill_save` (stable kebab-case key; omit project/product for a
  global skill; re-saving the same key updates it).
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

  void _registerTools(mcp.McpServer server) {
    server.tool(
      'oracle_status',
      description: 'Returns Oracle AI server status.',
      toolInputSchema: const mcp.ToolInputSchema(properties: {}),
      callback: ({args, extra}) async => _ok({'name': name, 'version': version, 'ok': true}),
    );

    // --- project ---
    server.tool(
      'oracle_project_register',
      description: 'Register a project (the central scope unit).',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'name': {'type': 'string', 'description': 'Project name'},
          'description': {'type': 'string'},
          'repoPath': {'type': 'string', 'description': 'Absolute repository path'},
        },
        required: ['name'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<RegisterProjectUsecase>()(ProjectEntity(
          id: const IdVO.empty(),
          name: TextVO('${a['name'] ?? ''}'),
          description: a['description'] == null ? null : TextVO('${a['description']}'),
          repoPath: a['repoPath']?.toString(),
        ));
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
        final result = await injector.get<ListProjectsUsecase>()(ProjectFilter(
          search: '${a['search'] ?? ''}',
          limit: _clampLimit(a['limit'], fallback: 50, max: 200),
        ));
        return result.fold((list) => _ok(list.map(_projectJson).toList()), _err);
      },
    );

    server.tool(
      'oracle_project_resolve',
      description: 'Map a working directory (cwd / repo path) to a stable projectId, '
          'creating the project on first sight. Call this once at session start to get '
          'the projectId used by every other tool — no manual registration needed.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'repoPath': {'type': 'string', 'description': 'Absolute repository path (the agent cwd)'},
          'name': {'type': 'string', 'description': 'Optional; defaults to the directory name'},
          'productId': {'type': 'string', 'description': 'Optional ecosystem/product this repo belongs to'},
        },
        required: ['repoPath'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final repoPath = '${a['repoPath'] ?? ''}';
        // Canonicalize to the git root (as the hooks and session_brief do), so a
        // call from a subdirectory or worktree maps to the SAME project instead
        // of creating a duplicate disjoint from the hook-captured one.
        final result = await injector.get<ResolveProjectUsecase>()(
          repoPath.trim().isEmpty ? repoPath : repoRootOf(repoPath),
          name: a['name']?.toString(),
          productId: a['productId'] == null ? null : IdVO('${a['productId']}'),
        );
        return result.fold((p) => _ok(_projectJson(p)), _err);
      },
    );

    server.tool(
      'oracle_session_brief',
      description: 'Get oriented at the start of work: pass your repo path (cwd) and receive the projectId '
          'plus a brief — pending handoff + required rules + key memories. Call this first.',
      toolInputSchema: const mcp.ToolInputSchema(properties: {
        'repoPath': {'type': 'string', 'description': 'Absolute repo path (cwd); resolved to the project'},
        'projectId': {'type': 'string', 'description': 'Or pass a known projectId instead of repoPath'},
      }),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        IdVO? pid;
        if ('${a['projectId'] ?? ''}'.trim().isNotEmpty) {
          pid = IdVO('${a['projectId']}');
        } else if ('${a['repoPath'] ?? ''}'.trim().isNotEmpty) {
          final res = await injector.get<ResolveProjectUsecase>()(repoRootOf('${a['repoPath']}'));
          pid = res.getOrNull()?.id;
        }
        if (pid == null) return _ok({'note': 'pass repoPath (cwd) or projectId'});
        final brief = await const RecallService().sessionBrief(pid);
        return _ok({'projectId': pid.value, 'brief': brief ?? ''});
      },
    );

    // --- memory ---
    server.tool(
      'oracle_memory_save',
      description: 'Save a consolidated memory (decision/gotcha/rule/fact). Only save durable, '
          'non-trivial learnings. To AVOID DUPLICATES: give a recurring memory a stable `key` '
          '(kebab-case, e.g. "filter-rollout-progress") and re-save with the same key to update '
          'it in place instead of piling up near-duplicates — re-saving an unchanged keyed memory '
          'is a free no-op (no re-embedding). Alternatively pass `supersedes` with the id of a '
          'memory this one replaces. Recall first (oracle_memory_search) before creating a new one.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'projectId': {'type': 'string'},
          'productId': {'type': 'string'},
          'key': {
            'type': 'string',
            'description': 'Optional stable slug (kebab-case). Re-saving the same key in the same '
                'project/product supersedes the previous version — use it to update one memory '
                'instead of creating duplicates.'
          },
          'supersedes': {
            'type': 'string',
            'description': 'Optional id of a memory this one replaces (retired in the same write).'
          },
          'tier': {'type': 'string', 'description': 'episodic | semantic | procedural'},
          'kind': {'type': 'string', 'description': 'decision | gotcha | rule | fact'},
          'title': {'type': 'string'},
          'body': {'type': 'string'},
          'tags': {
            'type': 'array',
            'items': {'type': 'string'}
          },
          'importance': {
            'type': 'number',
            'description': '0..1; ranks memories in the session brief. Defaults to 0.5. '
                'Episodic memories below 0.3 that go unaccessed are eligible for auto-decay.'
          },
        },
        required: ['title', 'body'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final key = a['key']?.toString().trim();
        final supersedes = a['supersedes']?.toString().trim();
        final result = await injector.get<SaveMemoryUsecase>()(MemoryEntity(
          id: const IdVO.empty(),
          projectId: a['projectId'] == null ? null : IdVO('${a['projectId']}'),
          productId: a['productId'] == null ? null : IdVO('${a['productId']}'),
          key: (key == null || key.isEmpty) ? null : key,
          supersedes: (supersedes == null || supersedes.isEmpty) ? null : IdVO(supersedes),
          tier: MemoryTier.parse('${a['tier'] ?? 'semantic'}'),
          kind: MemoryKind.parse('${a['kind'] ?? 'fact'}'),
          title: TextVO('${a['title'] ?? ''}'),
          body: TextVO('${a['body'] ?? ''}'),
          tags: _stringList(a['tags']),
          // Default to a neutral 0.5 (not 0): a 0 importance sinks below the decay
          // threshold and makes the importance-ordered brief degenerate to newest-first.
          importance: (a['importance'] as num?)?.toDouble() ?? 0.5,
        ));
        if (result.isError()) return _err(result.exceptionOrNull()!);
        return _ok(await _memoryJsonWithSimilar(result.getOrThrow()));
      },
    );

    server.tool(
      'oracle_memory_search',
      description: 'Hybrid search over consolidated memory (vector + full-text, RRF).',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'query': {'type': 'string'},
          'projectId': {'type': 'string'},
          'productId': {'type': 'string'},
          'tiers': {
            'type': 'array',
            'items': {'type': 'string'}
          },
          'kinds': {
            'type': 'array',
            'items': {'type': 'string'}
          },
          'limit': {'type': 'integer', 'description': 'Default 10, max 50'},
          'full': {
            'type': 'boolean',
            'description': 'Default false → id+title+snippet per hit (cheap). '
                'true → full body (use only when you truly need every body inline).'
          },
        },
        required: ['query'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final full = a['full'] == true;
        final result = await injector.get<SearchMemoriesUsecase>()(MemorySearchFilter(
          query: '${a['query'] ?? ''}',
          projectId: a['projectId'] == null ? null : IdVO('${a['projectId']}'),
          productId: a['productId'] == null ? null : IdVO('${a['productId']}'),
          tiers: _stringList(a['tiers']).map(MemoryTier.parse).toList(),
          kinds: _stringList(a['kinds']).map(MemoryKind.parse).toList(),
          limit: _clampLimit(a['limit'], fallback: 10),
        ));
        return result.fold(
          (list) => _ok(list.map((e) => _memoryHit(e, full: full)).toList()),
          _err,
        );
      },
    );

    server.tool(
      'oracle_memory_get',
      description: 'Get a memory by id.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'id': {'type': 'string'}
        },
        required: ['id'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<GetMemoryByIdUsecase>()(IdVO('${a['id'] ?? ''}'));
        return result.fold((m) => _ok(_memoryJson(m)), _err);
      },
    );

    server.tool(
      'oracle_memory_forget',
      description: 'Forget a memory that is wrong or obsolete (bad memory is worse than no '
          'memory). Soft by default (dropped from recall, kept for audit with a reason); '
          'pass hard=true to delete it permanently.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'id': {'type': 'string'},
          'reason': {'type': 'string', 'description': 'Why it is being forgotten (audit)'},
          'hard': {'type': 'boolean', 'description': 'true = permanent delete (purge)'},
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
      description: 'Create or refine a development rule. Re-saving the same key in the '
          'same owner REFINES it: the previous version is superseded (kept as history) '
          'and the new content/severity/priority take over. Use this to improve a rule.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'projectId': {'type': 'string'},
          'productId': {'type': 'string'},
          'key': {'type': 'string', 'description': 'Stable slug (e.g. controllers-pattern)'},
          'scope': {'type': 'string', 'description': 'module / folder / area'},
          'title': {'type': 'string'},
          'content': {'type': 'string'},
          'severity': {'type': 'string', 'description': 'required | recommended (obligation)'},
          'priority': {
            'type': 'integer',
            'description': 'Ranking within a severity, 0..100 (default 50). Higher wins in rules_for_task.'
          },
          'tags': {
            'type': 'array',
            'items': {'type': 'string'}
          },
        },
        required: ['key', 'scope', 'title', 'content'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<SaveRuleUsecase>()(RuleEntity(
          id: const IdVO.empty(),
          projectId: a['projectId'] == null ? null : IdVO('${a['projectId']}'),
          productId: a['productId'] == null ? null : IdVO('${a['productId']}'),
          key: '${a['key'] ?? ''}',
          scope: '${a['scope'] ?? ''}',
          title: TextVO('${a['title'] ?? ''}'),
          content: TextVO('${a['content'] ?? ''}'),
          severity: RuleSeverity.parse('${a['severity'] ?? 'recommended'}'),
          priority: (a['priority'] as num?)?.toInt() ?? 50,
          tags: _stringList(a['tags']),
        ));
        if (result.isError()) return _err(result.exceptionOrNull()!);
        return _ok(await _ruleJsonWithSimilar(result.getOrThrow()));
      },
    );

    server.tool(
      'oracle_rule_set_priority',
      description: 'Re-rank an existing rule in place (no new version). Raise/lower how '
          'strongly a still-valid rule weighs in rules_for_task.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'id': {'type': 'string'},
          'priority': {'type': 'integer', 'description': '0..100'},
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
      description: 'Retire a rule that no longer applies. Soft by default (dropped from '
          'recall, kept for audit with a reason); pass hard=true to delete it permanently.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'id': {'type': 'string'},
          'reason': {'type': 'string', 'description': 'Why it is being retired (audit)'},
          'hard': {'type': 'boolean', 'description': 'true = permanent delete (purge)'},
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
      description: 'Applicable rules for a task in a project (product→project inheritance '
          'and override). Consult before generating code.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'projectId': {'type': 'string'},
          'scope': {'type': 'string', 'description': 'optional module/folder/area filter'},
          'limit': {'type': 'integer'},
        },
        required: ['projectId'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<RulesForTaskUsecase>()(RulesForTaskQuery(
          projectId: IdVO('${a['projectId'] ?? ''}'),
          scope: a['scope']?.toString(),
          limit: _clampLimit(a['limit'], fallback: 50, max: 100),
        ));
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
          'productId': {'type': 'string'},
          'scope': {'type': 'string'},
          'severities': {
            'type': 'array',
            'items': {'type': 'string'}
          },
          'limit': {'type': 'integer', 'description': 'Default 10, max 50'},
          'full': {
            'type': 'boolean',
            'description': 'Default false → id+title+snippet per hit; true → full content.'
          },
        },
        required: ['query'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final full = a['full'] == true;
        final result = await injector.get<SearchRulesUsecase>()(RuleSearchFilter(
          query: '${a['query'] ?? ''}',
          projectId: a['projectId'] == null ? null : IdVO('${a['projectId']}'),
          productId: a['productId'] == null ? null : IdVO('${a['productId']}'),
          scope: a['scope']?.toString(),
          severities: _stringList(a['severities']).map(RuleSeverity.parse).toList(),
          limit: _clampLimit(a['limit'], fallback: 10),
        ));
        return result.fold(
          (list) => _ok(list.map((e) => _ruleHit(e, full: full)).toList()),
          _err,
        );
      },
    );

    // --- product ---
    server.tool(
      'oracle_product_register',
      description: 'Register a product (the ecosystem scope above projects).',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'name': {'type': 'string'},
          'description': {'type': 'string'},
        },
        required: ['name'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<RegisterProductUsecase>()(ProductEntity(
          id: const IdVO.empty(),
          name: TextVO('${a['name'] ?? ''}'),
          description: a['description'] == null ? null : TextVO('${a['description']}'),
        ));
        return result.fold((p) => _ok(_productJson(p)), _err);
      },
    );

    server.tool(
      'oracle_product_list',
      description: 'List products.',
      toolInputSchema: const mcp.ToolInputSchema(properties: {
        'search': {'type': 'string'},
        'limit': {'type': 'integer'},
      }),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<ListProductsUsecase>()(ProductFilter(
          search: '${a['search'] ?? ''}',
          limit: _clampLimit(a['limit'], fallback: 50, max: 200),
        ));
        return result.fold((list) => _ok(list.map(_productJson).toList()), _err);
      },
    );

    // --- skill (centralized shared skill library) ---
    server.tool(
      'oracle_skill_save',
      description: 'Save a reusable skill (SKILL.md-style how-to) into the CENTRAL shared '
          'library — one copy for every agent, no per-agent folders. Use a stable kebab-case '
          '`key`; re-saving the same key in the same scope supersedes it. Omit projectId AND '
          'productId for a GLOBAL skill (visible everywhere). `description` is the recall '
          'trigger — write it as "what it does + when to use it". Re-saving unchanged content '
          'is a free no-op.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'key': {'type': 'string', 'description': 'Stable kebab-case slug (e.g. filter-rollout-recipe)'},
          'name': {'type': 'string', 'description': 'Display name'},
          'description': {
            'type': 'string',
            'description': 'What it does + when to use it (this is what searches match on)'
          },
          'content': {'type': 'string', 'description': 'The skill body (markdown, SKILL.md style)'},
          'projectId': {'type': 'string', 'description': 'Scope to one project (omit for wider scope)'},
          'productId': {'type': 'string', 'description': 'Scope to a product (omit for global)'},
          'tags': {
            'type': 'array',
            'items': {'type': 'string'}
          },
        },
        required: ['key', 'name', 'description', 'content'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<SaveSkillUsecase>()(SkillEntity(
          id: const IdVO.empty(),
          projectId: a['projectId'] == null ? null : IdVO('${a['projectId']}'),
          productId: a['productId'] == null ? null : IdVO('${a['productId']}'),
          key: '${a['key'] ?? ''}'.trim(),
          name: TextVO('${a['name'] ?? ''}'),
          description: TextVO('${a['description'] ?? ''}'),
          content: TextVO('${a['content'] ?? ''}'),
          tags: _stringList(a['tags']),
        ));
        return result.fold((s) => _ok(_skillJson(s)), _err);
      },
    );

    server.tool(
      'oracle_skill_search',
      description: 'Find skills in the shared library by task context (hybrid search: vector + '
          'full-text). Returns name+description+key per hit (cheap, progressive disclosure) — '
          'load the winner with oracle_skill_get. Global skills are always included; projectId/'
          'productId add their scoped skills.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'query': {'type': 'string', 'description': 'The task context (what you are about to do)'},
          'projectId': {'type': 'string'},
          'productId': {'type': 'string'},
          'limit': {'type': 'integer', 'description': 'Default 10, max 50'},
        },
        required: ['query'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<SearchSkillsUsecase>()(SkillSearchFilter(
          query: '${a['query'] ?? ''}',
          projectId: a['projectId'] == null ? null : IdVO('${a['projectId']}'),
          productId: a['productId'] == null ? null : IdVO('${a['productId']}'),
          limit: _clampLimit(a['limit'], fallback: 10),
        ));
        return result.fold(
          (list) => _ok(list
              .map((e) => {
                    'id': e.skill.id.value,
                    'key': e.skill.key,
                    'name': e.skill.name.value,
                    'description': e.skill.description.value,
                    'scope': e.skill.projectId != null
                        ? 'project'
                        : (e.skill.productId != null ? 'product' : 'global'),
                    'score': e.score,
                  })
              .toList()),
          _err,
        );
      },
    );

    server.tool(
      'oracle_skill_get',
      description: 'Load one skill\'s full content (the "use the skill" step after '
          'oracle_skill_search). Pass an id, or a key — a key resolves project → product → '
          'global, so a project-specific version overrides the shared one.',
      toolInputSchema: const mcp.ToolInputSchema(properties: {
        'id': {'type': 'string'},
        'key': {'type': 'string'},
        'projectId': {'type': 'string', 'description': 'Used for key resolution'},
        'productId': {'type': 'string', 'description': 'Used for key resolution'},
      }),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<GetSkillUsecase>()(
          id: a['id'] == null ? null : IdVO('${a['id']}'),
          key: a['key']?.toString(),
          projectId: a['projectId'] == null ? null : IdVO('${a['projectId']}'),
          productId: a['productId'] == null ? null : IdVO('${a['productId']}'),
        );
        return result.fold((s) => _ok(_skillJson(s)), _err);
      },
    );

    server.tool(
      'oracle_skill_list',
      description: 'Inventory of the current skills visible to a scope (global + product + '
          'project). Name+description+key only.',
      toolInputSchema: const mcp.ToolInputSchema(properties: {
        'projectId': {'type': 'string'},
        'productId': {'type': 'string'},
        'limit': {'type': 'integer', 'description': 'Default 200'},
      }),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<ListSkillsUsecase>()(
          projectId: a['projectId'] == null ? null : IdVO('${a['projectId']}'),
          productId: a['productId'] == null ? null : IdVO('${a['productId']}'),
          limit: _clampLimit(a['limit'], fallback: 200, max: 500),
        );
        return result.fold(
          (list) => _ok(list
              .map((s) => {
                    'id': s.id.value,
                    'key': s.key,
                    'name': s.name.value,
                    'description': s.description.value,
                    'scope': s.projectId != null
                        ? 'project'
                        : (s.productId != null ? 'product' : 'global'),
                  })
              .toList()),
          _err,
        );
      },
    );

    server.tool(
      'oracle_skill_retire',
      description: 'Retire a skill that is wrong or obsolete. Soft by default (kept for '
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
      description: 'Save or refine a project architecture page for an area. Re-saving the '
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
        final result = await injector.get<SaveArchitectureUsecase>()(ArchitectureEntity(
          id: const IdVO.empty(),
          projectId: IdVO('${a['projectId'] ?? ''}'),
          area: '${a['area'] ?? ''}',
          content: TextVO('${a['content'] ?? ''}'),
        ));
        return result.fold((x) => _ok(_architectureJson(x)), _err);
      },
    );

    server.tool(
      'oracle_architecture_get',
      description: 'Get the current architecture page for a project area.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'projectId': {'type': 'string'},
          'area': {'type': 'string'},
        },
        required: ['projectId', 'area'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<GetArchitectureByAreaUsecase>()(
          IdVO('${a['projectId'] ?? ''}'),
          '${a['area'] ?? ''}',
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
            'description': 'Default false → id+area+snippet per hit; true → full content. '
                'Architecture pages can be large — prefer the default, then get the area you need.'
          },
        },
        required: ['query'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final full = a['full'] == true;
        final result = await injector.get<SearchArchitectureUsecase>()(ArchitectureSearchFilter(
          query: '${a['query'] ?? ''}',
          projectId: a['projectId'] == null ? null : IdVO('${a['projectId']}'),
          area: a['area']?.toString(),
          limit: _clampLimit(a['limit'], fallback: 10),
        ));
        return result.fold(
          (list) => _ok(list.map((e) => _architectureHit(e, full: full)).toList()),
          _err,
        );
      },
    );

    server.tool(
      'oracle_architecture_retire',
      description: 'Retire an architecture page that no longer reflects the project. Soft '
          'by default (dropped from recall, kept for audit with a reason); pass hard=true '
          'to delete it permanently.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'id': {'type': 'string'},
          'reason': {'type': 'string', 'description': 'Why it is being retired (audit)'},
          'hard': {'type': 'boolean', 'description': 'true = permanent delete (purge)'},
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
            'items': {'type': 'string'}
          },
          'nextSteps': {
            'type': 'array',
            'items': {'type': 'string'}
          },
          'filesTouched': {
            'type': 'array',
            'items': {'type': 'string'}
          },
          'cwd': {'type': 'string'},
        },
        required: ['projectId', 'summary'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<BeginHandoffUsecase>()(HandoffEntity(
          id: const IdVO.empty(),
          projectId: IdVO('${a['projectId'] ?? ''}'),
          sourceSessionId: a['sourceSessionId'] == null ? null : IdVO('${a['sourceSessionId']}'),
          fromAgent: a['fromAgent']?.toString(),
          toAgent: a['toAgent']?.toString(),
          summary: TextVO('${a['summary'] ?? ''}'),
          openQuestions: _stringList(a['openQuestions']),
          nextSteps: _stringList(a['nextSteps']),
          filesTouched: _stringList(a['filesTouched']),
          cwd: a['cwd']?.toString(),
        ));
        return result.fold((h) => _ok(_handoffJson(h)), _err);
      },
    );

    server.tool(
      'oracle_handoff_pending',
      description: 'Pending handoff for a project (inject on session start).',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'projectId': {'type': 'string'}
        },
        required: ['projectId'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<PendingHandoffsUsecase>()(IdVO('${a['projectId'] ?? ''}'));
        return result.fold((list) => _ok(list.map(_handoffJson).toList()), _err);
      },
    );

    server.tool(
      'oracle_handoff_accept',
      description: 'Accept (consume) a handoff.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'id': {'type': 'string'}
        },
        required: ['id'],
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<AcceptHandoffUsecase>()(IdVO('${a['id'] ?? ''}'));
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
        return result.fold((list) => _ok(list.map(_sessionJson).toList()), _err);
      },
    );

    server.tool(
      'oracle_session_history',
      description: 'A session\'s messages, MOST RECENT FIRST (the agent work across every request '
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
        return result.fold((list) => _ok(list.map(_messageJson).toList()), _err);
      },
    );

    server.tool(
      'oracle_session_requests',
      description: 'The user demands (requests) made in a session, newest first.',
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
        return result.fold((list) => _ok(list.map(_requestJson).toList()), _err);
      },
    );

    server.tool(
      'oracle_request_messages',
      description: 'The agent work (messages) carrying out one specific request/demand, in order. '
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
        return result.fold((list) => _ok(list.map(_messageJson).toList()), _err);
      },
    );

    server.tool(
      'oracle_request_search',
      description: 'Semantic search over past USER DEMANDS in this project — "has the user '
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
        return result.fold((list) => _ok(list.map(_requestJson).toList()), _err);
      },
    );

    // --- maintenance ---
    server.tool(
      'oracle_maintenance_run',
      description: 'Run the deterministic maintenance sweep over memories (no LLM): decay '
          '(forget stale, low-value, rarely-accessed memories) + dedup (forget the weaker '
          'of near-duplicates). Soft + audited. Use dryRun=true to preview. Rules and '
          'architecture are never auto-forgotten.',
      toolInputSchema: const mcp.ToolInputSchema(
        properties: {
          'dryRun': {'type': 'boolean', 'description': 'Preview only; change nothing'},
          'decay': {'type': 'boolean', 'description': 'Run the decay pass (default true)'},
          'dedup': {'type': 'boolean', 'description': 'Run the dedup pass (default true)'},
          'tiers': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Tiers eligible for decay (default ["episodic"])'
          },
          'staleDays': {'type': 'integer', 'description': 'Forget if not accessed in N days (default 30)'},
          'minImportance': {'type': 'number', 'description': 'Forget below this importance (default 0.3)'},
          'minAccessCount': {'type': 'integer', 'description': 'Forget if accessed < N times (default 2)'},
          'dedupDistance': {'type': 'number', 'description': 'Cosine distance for near-dup (default 0.05)'},
          'limit': {'type': 'integer', 'description': 'Max memories retired per pass (default 500)'},
        },
      ),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final tiers = _stringList(a['tiers']);
        final result = await injector.get<RunMaintenanceUsecase>()(DecayPolicy(
          dryRun: a['dryRun'] == true,
          runDecay: a['decay'] != false,
          runDedup: a['dedup'] != false,
          eligibleTiers: tiers.isEmpty ? const ['episodic'] : tiers,
          staleDays: (a['staleDays'] as num?)?.toInt() ?? 30,
          minImportance: (a['minImportance'] as num?)?.toDouble() ?? 0.3,
          minAccessCount: (a['minAccessCount'] as num?)?.toInt() ?? 2,
          dedupDistance: (a['dedupDistance'] as num?)?.toDouble() ?? 0.05,
          limit: _clampLimit(a['limit'], fallback: 500, max: 5000),
        ));
        return result.fold((r) => _ok(_maintenanceJson(r)), _err);
      },
    );

    server.tool(
      'oracle_maintenance_lint',
      description: 'Read-only health check over the memory bank: counts of memories/rules '
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
      description: 'Re-embed rows whose vector is missing or was produced by a different '
          'embedding model, using the currently configured embedder — the fix for empty '
          'semantic recall after switching provider/model (see oracle_maintenance_lint '
          "vectorsWithStaleModel). Bounded per call; re-run while 'mayHaveMore' is true.",
      toolInputSchema: const mcp.ToolInputSchema(properties: {
        'limit': {'type': 'integer', 'description': 'Max rows to re-embed this pass (default 200, max 2000)'},
      }),
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
      description: 'Write a portable snapshot of the whole memory bank (all data, embeddings '
          'included) to a .sql seed file. The schema is owned by the migrations, so the seed is '
          'data only and restores into a fresh database — commit it to version the shared memory, '
          'or bring the stack up on a new volume to restore it automatically. Restoring is a CLI/'
          "boot operation (oracle_ai restore-db), not a tool, since it's destructive on a populated DB.",
      toolInputSchema: const mcp.ToolInputSchema(properties: {
        'path': {'type': 'string', 'description': 'Output file (default backups/oracle_seed.sql)'},
      }),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final raw = a['path']?.toString().trim();
        final path = (raw == null || raw.isEmpty) ? 'backups/oracle_seed.sql' : raw;
        try {
          final report = await DbBackupService(injector.get<Database>()).backup(path);
          return _ok({
            'path': report.path,
            'rows': report.rows,
            'bytes': report.bytes,
            'perTable': report.perTable,
          });
        } catch (error) {
          return _err(SystemFailure(errorMessage: 'backup failed: $error', stackTrace: StackTrace.current));
        }
      },
    );

    // --- metrics (measurement harness) ---
    server.tool(
      'oracle_metrics_summary',
      description: 'Aggregate session metrics per experiment label (tokens, cache-read ratio, '
          'compactions/session). Use to A/B compare runs (e.g. oracle vs baseline) and prove '
          'cost impact. Optional label filter.',
      toolInputSchema: const mcp.ToolInputSchema(properties: {
        'label': {'type': 'string', 'description': 'Filter to one experiment label'},
      }),
      callback: ({args, extra}) async {
        final a = args ?? const {};
        final result = await injector.get<MetricsSummaryUsecase>()(label: a['label']?.toString());
        return result.fold((list) => _ok(list.map(_metricsSummaryJson).toList()), _err);
      },
    );

    server.tool(
      'oracle_metrics_session',
      description: 'Recent per-session metric rows for a project (tokens, compactions, turns).',
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
        return result.fold((list) => _ok(list.map(_sessionMetricJson).toList()), _err);
      },
    );
  }

  // ── helpers ──

  static List<String> _stringList(Object? value) =>
      value is List ? value.map((e) => e.toString()).toList() : const [];

  /// Clamps a caller-supplied `limit` into `[1, max]`, defaulting to [fallback]
  /// when absent/invalid — so an oversized value can't force a giant scan or
  /// materialize a huge result on the shared daemon.
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

  static mcp.CallToolResult _ok(Object json) =>
      mcp.CallToolResult.fromContent(content: [mcp.TextContent(text: jsonEncode(json))]);

  static mcp.CallToolResult _err(SystemFailure failure) => mcp.CallToolResult.fromContent(
        content: [
          mcp.TextContent(
            text: jsonEncode({
              'error': failure.errorMessage,
              'fields': failure.fields.map((f) => f.toMap()).toList(),
            }),
          )
        ],
        isError: true,
      );

  static Map<String, dynamic> _projectJson(ProjectEntity p) => {
        'id': p.id.value,
        'productId': p.productId?.value,
        'name': p.name.value,
        'description': p.description?.value,
        'repoPath': p.repoPath,
        'createdAt': p.createdAt?.toIso8601String(),
        'updatedAt': p.updatedAt?.toIso8601String(),
      };

  static Map<String, dynamic> _memoryJson(MemoryEntity m) => {
        'id': m.id.value,
        'productId': m.productId?.value,
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
        'productId': r.productId?.value,
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
        'productId': s.productId?.value,
        'projectId': s.projectId?.value,
        'key': s.key,
        'name': s.name.value,
        'description': s.description.value,
        'content': s.content.value,
        'tags': s.tags,
        'scope': s.projectId != null ? 'project' : (s.productId != null ? 'product' : 'global'),
        'isLatest': s.isLatest,
        'createdAt': s.createdAt?.toIso8601String(),
      };

  /// Memory JSON augmented with a near-duplicate signal: latest same-model
  /// memories close to the one just saved, so the agent can consolidate (reuse
  /// a key / supersedes) instead of piling up duplicates. Uses the embedding
  /// already computed by the save — no extra embedding call.
  static Future<Map<String, dynamic>> _memoryJsonWithSimilar(MemoryEntity m) async {
    final json = _memoryJson(m);
    if (m.embedding == null || m.embeddingModel == null) return json;
    final near = await injector.get<MemoryRepository>().nearestByEmbedding(
          productId: m.productId,
          projectId: m.projectId,
          embedding: m.embedding!,
          embeddingModel: m.embeddingModel!,
          excludeId: m.id,
        );
    if (near.isNotEmpty) {
      json['similar'] = near
          .map((n) => {
                'id': n.memory.id.value,
                'key': n.memory.key,
                'title': n.memory.title.value,
                'distance': double.parse(n.distance.toStringAsFixed(3)),
              })
          .toList();
      json['similarNote'] = 'Near-duplicate memories already exist. To avoid piling up '
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
          productId: r.productId,
          projectId: r.projectId,
          embedding: r.embedding!,
          embeddingModel: r.embeddingModel!,
          excludeId: r.id,
        );
    if (near.isNotEmpty) {
      json['similar'] = near
          .map((n) => {
                'id': n.rule.id.value,
                'key': n.rule.key,
                'title': n.rule.title.value,
                'distance': double.parse(n.distance.toStringAsFixed(3)),
              })
          .toList();
      json['similarNote'] = 'A similar rule already exists. Prefer refining it (re-save with '
          'its key) over creating a near-duplicate rule.';
    }
    return json;
  }

  static Map<String, dynamic> _productJson(ProductEntity p) => {
        'id': p.id.value,
        'name': p.name.value,
        'description': p.description?.value,
        'createdAt': p.createdAt?.toIso8601String(),
      };

  static Map<String, dynamic> _architectureJson(ArchitectureEntity a) => {
        'id': a.id.value,
        'projectId': a.projectId.value,
        'area': a.area,
        'content': a.content.value,
        'isLatest': a.isLatest,
        'createdAt': a.createdAt?.toIso8601String(),
      };

  /// Max chars of a body/content returned by a SEARCH hit. Search is a discovery
  /// step, so hits default to a snippet + id (cheap in context); the agent fetches
  /// the full text with the get-by-id tool, or passes `full:true` to inline it.
  static const _searchSnippetChars = 240;

  static Map<String, dynamic> _memoryHit(MemorySearchResult e, {required bool full}) => full
      ? {'memory': _memoryJson(e.memory), 'score': e.score}
      : {
          'id': e.memory.id.value,
          'kind': e.memory.kind.code,
          'title': e.memory.title.value,
          'snippet': _snippet(e.memory.body.value, _searchSnippetChars),
          'importance': e.memory.importance,
          'score': e.score,
        };

  static Map<String, dynamic> _ruleHit(RuleSearchResult e, {required bool full}) => full
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

  static Map<String, dynamic> _architectureHit(ArchitectureSearchResult e, {required bool full}) =>
      full
          ? {'architecture': _architectureJson(e.architecture), 'score': e.score}
          : {
              'id': e.architecture.id.value,
              'area': e.architecture.area,
              'snippet': _snippet(e.architecture.content.value, _searchSnippetChars),
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
        'avgCompactionsPerSession': double.parse(s.avgCompactionsPerSession.toStringAsFixed(3)),
        'avgTokensPerSession': double.parse(s.avgTokensPerSession.toStringAsFixed(1)),
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
}
