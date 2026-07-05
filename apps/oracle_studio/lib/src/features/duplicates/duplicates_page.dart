import 'package:flutter/material.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';

import '../../core/brand.dart';
import '../../core/fmt.dart';
import '../../core/l10n.dart';
import '../../core/oracle_connection.dart';
import '../../widgets/async_view.dart';
import '../../widgets/editor_dialog.dart';

/// One memory inside a near-duplicate cluster.
class _DupMember {
  final String id;
  final String title;
  final String kind;
  final double importance;
  final DateTime? createdAt;
  const _DupMember(this.id, this.title, this.kind, this.importance, this.createdAt);
}

/// A group of memories that are mutually near-identical (by embedding distance).
class _DupCluster {
  final List<_DupMember> members;
  final double minDistance;
  const _DupCluster(this.members, this.minDistance);
}

/// Finds and cleans up near-duplicate memories — the thing that piles up when an
/// agent saves similar memories without a stable `key`. Clusters memories by
/// embedding proximity so you can keep one and retire the rest, and offers a
/// one-click run of the automatic maintenance dedup sweep.
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

    const sql = '''
      SELECT a.id AS a_id, a.title AS a_title, a.kind AS a_kind,
             a.importance AS a_imp, a.created_at AS a_created,
             b.id AS b_id, b.title AS b_title, b.kind AS b_kind,
             b.importance AS b_imp, b.created_at AS b_created,
             (a.embedding <=> b.embedding) AS distance
      FROM memories a
      JOIN memories b ON b.id > a.id
        AND a.is_latest AND b.is_latest
        AND a.retired_at IS NULL AND b.retired_at IS NULL
        AND a.embedding IS NOT NULL AND b.embedding IS NOT NULL
        AND a.kind = b.kind
        AND a.embedding_model = b.embedding_model
        AND a.project_id = :pid::uuid AND b.project_id = :pid::uuid
        AND (a.embedding <=> b.embedding) < :maxd
      ORDER BY distance
      LIMIT 300
    ''';
    final result = await db.select(
        SqlStatement(sql, {'pid': project.id.value, 'maxd': _maxDistance}));

    // Union-find: merge every near-duplicate pair into connected clusters.
    final parent = <String, String>{};
    final members = <String, _DupMember>{};
    final clusterMinDist = <String, double>{};

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

    for (final r in result.rows) {
      final aId = r['a_id']?.toText() ?? '';
      final bId = r['b_id']?.toText() ?? '';
      if (aId.isEmpty || bId.isEmpty) continue;
      parent.putIfAbsent(aId, () => aId);
      parent.putIfAbsent(bId, () => bId);
      members[aId] = _DupMember(aId, r['a_title']?.toText() ?? '', r['a_kind']?.toText() ?? '',
          r['a_imp']?.toDouble() ?? 0, r['a_created']?.toDateTime());
      members[bId] = _DupMember(bId, r['b_title']?.toText() ?? '', r['b_kind']?.toText() ?? '',
          r['b_imp']?.toDouble() ?? 0, r['b_created']?.toDateTime());
      union(aId, bId);
    }

    // Track the tightest pair distance per cluster for display.
    for (final r in result.rows) {
      final aId = r['a_id']?.toText() ?? '';
      if (aId.isEmpty) continue;
      final root = find(aId);
      final d = r['distance']?.toDouble() ?? 1.0;
      clusterMinDist[root] = clusterMinDist[root] == null ? d : (d < clusterMinDist[root]! ? d : clusterMinDist[root]!);
    }

    final grouped = <String, List<_DupMember>>{};
    for (final id in members.keys) {
      grouped.putIfAbsent(find(id), () => []).add(members[id]!);
    }

    final clusters = <_DupCluster>[];
    grouped.forEach((root, list) {
      if (list.length < 2) return;
      // Suggest keeping the strongest (highest importance, then newest).
      list.sort((a, b) {
        final byImp = b.importance.compareTo(a.importance);
        if (byImp != 0) return byImp;
        return (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
      });
      _keep.putIfAbsent(root, () => list.first.id);
      clusters.add(_DupCluster(list, clusterMinDist[root] ?? 0));
    });
    clusters.sort((a, b) => a.minDistance.compareTo(b.minDistance));
    return clusters;
  }

  String _clusterKey(_DupCluster c) => c.members.map((m) => m.id).reduce((a, b) => a.compareTo(b) < 0 ? a : b);

  Future<void> _runSweep() async {
    setState(() => _busy = true);
    // Dedup pass only (no decay) — retire the weaker of each near-duplicate pair.
    final result = await injector.get<RunMaintenanceUsecase>()(
        const DecayPolicy(runDecay: false, runDedup: true));
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
      await injector
          .get<ForgetMemoryUsecase>()(IdVO(m.id), reason: 'duplicate (via Oracle Studio)', hard: false);
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(children: [
            Expanded(
              child: Text(l10n.t('dup.intro'),
                  style: const TextStyle(fontSize: 12, color: OracleBrand.gray400)),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _reload,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.t('dup.rescan')),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _runSweep,
              icon: const Icon(Icons.cleaning_services_outlined, size: 18),
              label: Text(l10n.t('dup.runSweep')),
            ),
          ]),
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
                subtitle: Text(
                  '${m.kind} · ${l10n.t('mem.importance').toLowerCase()} '
                  '${m.importance.toStringAsFixed(2)} · ${fmtDateTime(m.createdAt)}',
                  style: const TextStyle(fontSize: 11),
                ),
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
