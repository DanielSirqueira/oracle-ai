import 'package:flutter/material.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';

import '../../core/brand.dart';
import '../../core/fmt.dart';
import '../../core/l10n.dart';
import '../../core/oracle_connection.dart';
import '../../widgets/async_view.dart';
import '../../widgets/editor_dialog.dart';

enum _DupKind { memories, rules }

/// One item inside a near-duplicate cluster (a memory or a rule).
class _DupMember {
  final String id;
  final String title;
  final String meta; // pre-formatted subtitle line
  final double keepScore; // higher = better candidate to keep
  final DateTime? createdAt;
  const _DupMember(this.id, this.title, this.meta, this.keepScore, this.createdAt);
}

class _Pair {
  final _DupMember a;
  final _DupMember b;
  final double distance;
  const _Pair(this.a, this.b, this.distance);
}

/// A group of items that are mutually near-identical (by embedding distance).
class _DupCluster {
  final List<_DupMember> members;
  final double minDistance;
  const _DupCluster(this.members, this.minDistance);
}

/// Finds and cleans up near-duplicate memories and rules — the thing that piles
/// up when an agent saves similar items without reusing a stable `key`. Clusters
/// them by embedding proximity so you can keep one and retire the rest, and (for
/// memories) offers a one-click run of the automatic maintenance dedup sweep.
class DuplicatesPage extends StatefulWidget {
  final OracleConnection connection;
  final ValueNotifier<ProjectEntity?> project;
  const DuplicatesPage({super.key, required this.connection, required this.project});

  @override
  State<DuplicatesPage> createState() => _DuplicatesPageState();
}

class _DuplicatesPageState extends State<DuplicatesPage> {
  // A bit looser than the automatic sweep (0.05) so genuine duplicates surface
  // for manual review — retiring is a deliberate click, so a wider net is safe.
  static const _maxDistance = 0.1;

  _DupKind _kind = _DupKind.memories;
  Future<List<_DupCluster>>? _future;
  bool _busy = false;
  final Map<String, String> _keep = {}; // clusterKey -> id to keep

  @override
  void initState() {
    super.initState();
    widget.project.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.project.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    setState(() {
      _keep.clear();
      _future = _load();
    });
  }

  Future<List<_DupCluster>> _load() async {
    final project = widget.project.value;
    final db = widget.connection.database;
    if (project == null || db == null) return const [];
    final pairs = _kind == _DupKind.memories
        ? await _memoryPairs(db, project.id.value)
        : await _rulePairs(db, project.id.value);
    return _cluster(pairs);
  }

  Future<List<_Pair>> _memoryPairs(Database db, String pid) async {
    const sql = '''
      SELECT a.id a_id, a.title a_title, a.kind a_kind, a.importance a_imp, a.created_at a_created,
             b.id b_id, b.title b_title, b.kind b_kind, b.importance b_imp, b.created_at b_created,
             (a.embedding <=> b.embedding) distance
      FROM memories a
      JOIN memories b ON b.id > a.id
        AND a.is_latest AND b.is_latest AND a.retired_at IS NULL AND b.retired_at IS NULL
        AND a.embedding IS NOT NULL AND b.embedding IS NOT NULL
        AND a.kind = b.kind AND a.embedding_model = b.embedding_model
        AND a.project_id = :pid::uuid AND b.project_id = :pid::uuid
        AND (a.embedding <=> b.embedding) < :maxd
      ORDER BY distance LIMIT 300''';
    final res = await db.select(SqlStatement(sql, {'pid': pid, 'maxd': _maxDistance}));
    _DupMember mem(Map<String, dynamic> r, String p) {
      final imp = r['${p}_imp']?.toDouble() ?? 0;
      return _DupMember(
        r['${p}_id']?.toText() ?? '',
        r['${p}_title']?.toText() ?? '',
        '${r['${p}_kind']?.toText() ?? ''} · ${l10n.t('mem.importance').toLowerCase()} '
            '${imp.toStringAsFixed(2)} · ${fmtDateTime(r['${p}_created']?.toDateTime())}',
        imp, // higher importance = keep
        r['${p}_created']?.toDateTime(),
      );
    }

    return [
      for (final r in res.rows)
        _Pair(mem(r, 'a'), mem(r, 'b'), r['distance']?.toDouble() ?? 1.0)
    ];
  }

  Future<List<_Pair>> _rulePairs(Database db, String pid) async {
    const sql = '''
      SELECT a.id a_id, a.title a_title, a.key a_key, a.priority a_prio, a.created_at a_created,
             b.id b_id, b.title b_title, b.key b_key, b.priority b_prio, b.created_at b_created,
             (a.embedding <=> b.embedding) distance
      FROM rules a
      JOIN rules b ON b.id > a.id
        AND a.is_latest AND b.is_latest AND a.retired_at IS NULL AND b.retired_at IS NULL
        AND a.embedding IS NOT NULL AND b.embedding IS NOT NULL
        AND a.embedding_model = b.embedding_model
        AND a.project_id = :pid::uuid AND b.project_id = :pid::uuid
        AND (a.embedding <=> b.embedding) < :maxd
      ORDER BY distance LIMIT 300''';
    final res = await db.select(SqlStatement(sql, {'pid': pid, 'maxd': _maxDistance}));
    _DupMember rule(Map<String, dynamic> r, String p) {
      final prio = r['${p}_prio']?.toInt() ?? 50;
      return _DupMember(
        r['${p}_id']?.toText() ?? '',
        r['${p}_title']?.toText() ?? '',
        '${r['${p}_key']?.toText() ?? ''} · ${l10n.t('rule.priority').toLowerCase()} '
            '$prio · ${fmtDateTime(r['${p}_created']?.toDateTime())}',
        -prio.toDouble(), // lower priority number = more relevant = keep
        r['${p}_created']?.toDateTime(),
      );
    }

    return [
      for (final r in res.rows)
        _Pair(rule(r, 'a'), rule(r, 'b'), r['distance']?.toDouble() ?? 1.0)
    ];
  }

  List<_DupCluster> _cluster(List<_Pair> pairs) {
    final parent = <String, String>{};
    final members = <String, _DupMember>{};
    final minDist = <String, double>{};

    String find(String x) {
      var root = x;
      while (parent[root] != root) {
        root = parent[root]!;
      }
      parent[x] = root;
      return root;
    }

    void union(String a, String b) {
      final ra = find(a), rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    for (final p in pairs) {
      if (p.a.id.isEmpty || p.b.id.isEmpty) continue;
      parent.putIfAbsent(p.a.id, () => p.a.id);
      parent.putIfAbsent(p.b.id, () => p.b.id);
      members[p.a.id] = p.a;
      members[p.b.id] = p.b;
      union(p.a.id, p.b.id);
    }
    for (final p in pairs) {
      if (p.a.id.isEmpty) continue;
      final root = find(p.a.id);
      minDist[root] =
          minDist[root] == null ? p.distance : (p.distance < minDist[root]! ? p.distance : minDist[root]!);
    }

    final grouped = <String, List<_DupMember>>{};
    for (final id in members.keys) {
      grouped.putIfAbsent(find(id), () => []).add(members[id]!);
    }

    final clusters = <_DupCluster>[];
    grouped.forEach((root, list) {
      if (list.length < 2) return;
      list.sort((a, b) {
        final byScore = b.keepScore.compareTo(a.keepScore);
        if (byScore != 0) return byScore;
        return (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
      });
      _keep.putIfAbsent(root, () => list.first.id);
      clusters.add(_DupCluster(list, minDist[root] ?? 0));
    });
    clusters.sort((a, b) => a.minDistance.compareTo(b.minDistance));
    return clusters;
  }

  String _clusterKey(_DupCluster c) =>
      c.members.map((m) => m.id).reduce((a, b) => a.compareTo(b) < 0 ? a : b);

  Future<void> _retire(String id) async {
    if (_kind == _DupKind.memories) {
      await injector
          .get<ForgetMemoryUsecase>()(IdVO(id), reason: 'duplicate (via Oracle Studio)', hard: false);
    } else {
      await injector
          .get<RetireRuleUsecase>()(IdVO(id), reason: 'duplicate (via Oracle Studio)', hard: false);
    }
  }

  Future<void> _runSweep() async {
    setState(() => _busy = true);
    // Dedup pass only (no decay) — retire the weaker of each near-duplicate pair.
    final result = await injector
        .get<RunMaintenanceUsecase>()(const DecayPolicy(runDecay: false, runDedup: true));
    if (!mounted) return;
    setState(() => _busy = false);
    result.fold(
      (_) {
        showSnack(context, l10n.t('dup.sweepDone'));
        _reload();
      },
      (f) => showSnack(context, '${l10n.t('common.failure')}: ${f.errorMessage}'),
    );
  }

  Future<void> _retireOthers(_DupCluster cluster) async {
    final keepId = _keep[_clusterKey(cluster)];
    final losers = cluster.members.where((m) => m.id != keepId).toList();
    if (losers.isEmpty) return;
    final ok = await confirmAction(
      context,
      title: l10n.t('dup.retireQ'),
      message: l10n.t('dup.retireMsg').replaceFirst('{n}', '${losers.length}'),
      okLabel: l10n.t('dup.retire'),
      destructive: true,
    );
    if (!ok) return;
    setState(() => _busy = true);
    for (final m in losers) {
      await _retire(m.id);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    showSnack(context, l10n.t('dup.retired'));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.project.value == null) {
      return Center(child: Text(l10n.t('common.selectProject')));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            SegmentedButton<_DupKind>(
              segments: [
                ButtonSegment(
                    value: _DupKind.memories,
                    label: Text(l10n.t('dup.memories')),
                    icon: const Icon(Icons.psychology_outlined, size: 16)),
                ButtonSegment(
                    value: _DupKind.rules,
                    label: Text(l10n.t('dup.rules')),
                    icon: const Icon(Icons.rule_outlined, size: 16)),
              ],
              selected: {_kind},
              onSelectionChanged: _busy
                  ? null
                  : (s) => setState(() {
                        _kind = s.first;
                        _reload();
                      }),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _busy ? null : _reload,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.t('dup.rescan')),
            ),
            if (_kind == _DupKind.memories) ...[
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _busy ? null : _runSweep,
                icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                label: Text(l10n.t('dup.runSweep')),
              ),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(l10n.t('dup.intro'),
                style: const TextStyle(fontSize: 12, color: OracleBrand.gray400)),
          ),
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: AsyncView<List<_DupCluster>>(
            future: _future!,
            builder: (context, clusters) => clusters.isEmpty
                ? Center(child: Text(l10n.t('dup.none')))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: clusters.length,
                    itemBuilder: (context, i) => _ClusterCard(
                      cluster: clusters[i],
                      keepId: _keep[_clusterKey(clusters[i])],
                      onKeep: (id) => setState(() => _keep[_clusterKey(clusters[i])] = id),
                      onRetire: () => _retireOthers(clusters[i]),
                      busy: _busy,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ClusterCard extends StatelessWidget {
  final _DupCluster cluster;
  final String? keepId;
  final ValueChanged<String> onKeep;
  final VoidCallback onRetire;
  final bool busy;
  const _ClusterCard({
    required this.cluster,
    required this.keepId,
    required this.onKeep,
    required this.onRetire,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              MetaChip('${cluster.members.length} ${l10n.t('dup.items')}',
                  icon: Icons.content_copy_outlined),
              const SizedBox(width: 8),
              MetaChip('~${cluster.minDistance.toStringAsFixed(3)}', icon: Icons.straighten),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: busy ? null : onRetire,
                icon: const Icon(Icons.auto_delete_outlined, size: 16),
                label: Text(l10n.t('dup.retireOthers')),
              ),
            ]),
            const SizedBox(height: 8),
            for (final m in cluster.members)
              ListTile(
                dense: true,
                onTap: busy ? null : () => onKeep(m.id),
                leading: Icon(
                  m.id == keepId ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: 18,
                  color: m.id == keepId ? OracleBrand.violetSoft : OracleBrand.gray500,
                ),
                title: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(m.meta, style: const TextStyle(fontSize: 11)),
                trailing: m.id == keepId
                    ? Tooltip(
                        message: l10n.t('dup.keep'),
                        child: const Icon(Icons.star, color: OracleBrand.violetSoft, size: 18))
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}
