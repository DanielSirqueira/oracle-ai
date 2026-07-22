import 'package:flutter/material.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';

import '../../core/brand.dart';
import '../../core/fmt.dart';
import '../../core/l10n.dart';
import '../../widgets/async_view.dart';
import '../../widgets/markdown_view.dart';
import '../../widgets/records_toolbar.dart';

/// Handoffs: the context an agent passes from one session to the next (what
/// happened, open questions, next steps, files touched). This view lists the
/// project's full handoff history — pending (open), accepted and expired — so
/// you can see the thread of work between sessions, which had no UI before.
class HandoffsPage extends StatefulWidget {
  final ValueNotifier<ProjectEntity?> project;
  const HandoffsPage({super.key, required this.project});

  @override
  State<HandoffsPage> createState() => _HandoffsPageState();
}

class _HandoffsPageState extends State<HandoffsPage> {
  HandoffEntity? _selected;
  Future<List<HandoffEntity>>? _future;
  final _query = TextEditingController();
  String _status = 'all';

  @override
  void initState() {
    super.initState();
    widget.project.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.project.removeListener(_reload);
    _query.dispose();
    super.dispose();
  }

  void _reload() {
    final project = widget.project.value;
    if (project == null) return;
    setState(() {
      _selected = null;
      _future = injector
          .get<RecentHandoffsUsecase>()(project.id, limit: 100)
          .then((r) => r.getOrThrow());
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_future == null) {
      return Center(child: Text(l10n.t('common.selectProject')));
    }
    return AsyncView<List<HandoffEntity>>(
      future: _future!,
      onRetry: _reload,
      builder: (context, handoffs) {
        final q = _query.text.trim().toLowerCase();
        final filtered = handoffs
            .where(
              (h) =>
                  (_status == 'all' || h.status.code == _status) &&
                  (q.isEmpty ||
                      h.summary.value.toLowerCase().contains(q) ||
                      (h.fromAgent ?? '').toLowerCase().contains(q) ||
                      (h.toAgent ?? '').toLowerCase().contains(q) ||
                      (h.cwd ?? '').toLowerCase().contains(q)),
            )
            .toList();
        return Column(
          children: [
            RecordsToolbar(
              title: l10n.t('nav.handoffs'),
              description: l10n.t('nav.handoffsHint'),
              searchController: _query,
              onSearchChanged: (_) => setState(() {}),
              onRefresh: _reload,
              resultCount: filtered.length,
              filters: [
                ChoiceChip(
                  label: Text(l10n.t('records.all')),
                  selected: _status == 'all',
                  onSelected: (_) => setState(() => _status = 'all'),
                ),
                for (final status in HandoffStatus.values)
                  ChoiceChip(
                    label: Text(_statusLabel(status)),
                    selected: _status == status.code,
                    onSelected: (_) => setState(() => _status = status.code),
                  ),
              ],
            ),
            Expanded(
              child: filtered.isEmpty
                  ? RecordsEmptyState(
                      title: handoffs.isEmpty
                          ? l10n.t('handoff.empty')
                          : l10n.t('records.noMatch'),
                      description: handoffs.isEmpty
                          ? null
                          : l10n.t('records.noMatchHint'),
                      icon: Icons.swap_horiz,
                    )
                  : MasterDetail(
                      master: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final h = filtered[i];
                          return ListTile(
                            selected: _selected?.id.value == h.id.value,
                            leading: _StatusBadge(h.status),
                            title: Text(
                              _firstLine(h.summary.value),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${_statusLabel(h.status)} · ${fmtDateTime(h.createdAt)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => setState(() => _selected = h),
                          );
                        },
                      ),
                      detail: _selected == null
                          ? Center(child: Text(l10n.t('handoff.selectOne')))
                          : _HandoffDetail(handoff: _selected!),
                    ),
            ),
          ],
        );
      },
    );
  }
}

String _firstLine(String s) {
  final line = s.trimLeft().split('\n').first.trim();
  return line.isEmpty ? s.trim() : line;
}

String _statusLabel(HandoffStatus status) => switch (status) {
  HandoffStatus.open => l10n.t('handoff.open'),
  HandoffStatus.accepted => l10n.t('handoff.accepted'),
  HandoffStatus.expired => l10n.t('handoff.expired'),
};

Color _statusColor(HandoffStatus status) => switch (status) {
  HandoffStatus.open => OracleBrand.violetSoft,
  HandoffStatus.accepted => OracleBrand.success,
  HandoffStatus.expired => OracleBrand.gray500,
};

class _StatusBadge extends StatelessWidget {
  final HandoffStatus status;
  const _StatusBadge(this.status);

  @override
  Widget build(BuildContext context) {
    final icon = switch (status) {
      HandoffStatus.open => Icons.pending_actions_outlined,
      HandoffStatus.accepted => Icons.check_circle_outline,
      HandoffStatus.expired => Icons.history_toggle_off,
    };
    return CircleAvatar(
      radius: 16,
      backgroundColor: _statusColor(status).withValues(alpha: 0.18),
      child: Icon(icon, size: 16, color: _statusColor(status)),
    );
  }
}

class _HandoffDetail extends StatelessWidget {
  final HandoffEntity handoff;
  const _HandoffDetail({required this.handoff});

  @override
  Widget build(BuildContext context) {
    final agents = [
      handoff.fromAgent,
      handoff.toAgent,
    ].whereType<String>().toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          l10n.t('handoff.contextTitle'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            MetaChip(_statusLabel(handoff.status), icon: Icons.flag_outlined),
            if (agents.isNotEmpty)
              MetaChip(agents.join(' → '), icon: Icons.swap_horiz),
            MetaChip(fmtDateTime(handoff.createdAt), icon: Icons.schedule),
            if (handoff.acceptedAt != null)
              MetaChip(
                '${l10n.t('handoff.accepted')}: ${fmtDateTime(handoff.acceptedAt)}',
                icon: Icons.done_all,
              ),
            if (handoff.cwd != null && handoff.cwd!.isNotEmpty)
              MetaChip(handoff.cwd!, icon: Icons.folder_outlined),
          ],
        ),
        const Divider(height: 32),
        MarkdownView(handoff.summary.value),
        _BulletSection(
          l10n.t('handoff.nextSteps'),
          handoff.nextSteps,
          Icons.checklist,
        ),
        _BulletSection(
          l10n.t('handoff.openQuestions'),
          handoff.openQuestions,
          Icons.help_outline,
        ),
        _BulletSection(
          l10n.t('handoff.filesTouched'),
          handoff.filesTouched,
          Icons.description_outlined,
        ),
      ],
    );
  }
}

class _BulletSection extends StatelessWidget {
  final String label;
  final List<String> items;
  final IconData icon;
  const _BulletSection(this.label, this.items, this.icon);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          children: [
            Icon(icon, size: 16, color: OracleBrand.gray400),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: OracleBrand.gray100,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  ', style: TextStyle(color: OracleBrand.gray400)),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
