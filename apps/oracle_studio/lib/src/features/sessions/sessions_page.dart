import 'package:flutter/material.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';

import '../../core/fmt.dart';
import '../../core/l10n.dart';
import '../../widgets/async_view.dart';
import '../../widgets/markdown_view.dart';
import '../../widgets/records_toolbar.dart';

/// Capture browser: sessions → user demands (requests) → agent work (messages).
class SessionsPage extends StatefulWidget {
  final ValueNotifier<ProjectEntity?> project;
  const SessionsPage({super.key, required this.project});

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  Future<List<SessionEntity>>? _sessions;
  SessionEntity? _session;
  Future<List<RequestEntity>>? _requests;
  RequestEntity? _request;
  Future<List<MessageEntity>>? _messages;
  final _query = TextEditingController();
  String _agent = 'all';

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
      _session = null;
      _request = null;
      _requests = null;
      _messages = null;
      _sessions = injector
          .get<RecentSessionsUsecase>()(project.id, limit: 50)
          .then((r) => r.getOrThrow());
    });
  }

  void _openSession(SessionEntity s) {
    setState(() {
      _session = s;
      _request = null;
      _messages = null;
      _requests = injector.get<SessionRequestsUsecase>()(s.id, limit: 100).then(
        (r) => r.getOrThrow(),
      );
    });
  }

  void _openRequest(RequestEntity r) {
    setState(() {
      _request = r;
      _messages = injector.get<RequestMessagesUsecase>()(r.id, limit: 200).then(
        (r) => r.getOrThrow(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_sessions == null) {
      return Center(child: Text(l10n.t('common.selectProject')));
    }
    return AsyncView<List<SessionEntity>>(
      future: _sessions!,
      onRetry: _reload,
      builder: (context, sessions) {
        final q = _query.text.trim().toLowerCase();
        final agents = sessions.map((s) => s.agent).toSet().toList()..sort();
        final filtered = sessions
            .where(
              (s) =>
                  (_agent == 'all' || s.agent == _agent) &&
                  (q.isEmpty ||
                      s.agent.toLowerCase().contains(q) ||
                      (s.externalId ?? '').toLowerCase().contains(q) ||
                      (s.cwd ?? '').toLowerCase().contains(q)),
            )
            .toList();
        return Column(
          children: [
            RecordsToolbar(
              title: l10n.t('nav.sessions'),
              description: l10n.t('nav.sessionsHint'),
              searchController: _query,
              onSearchChanged: (_) => setState(() {}),
              onRefresh: _reload,
              resultCount: filtered.length,
              filters: [
                ChoiceChip(
                  label: Text(l10n.t('records.all')),
                  selected: _agent == 'all',
                  onSelected: (_) => setState(() => _agent = 'all'),
                ),
                for (final agent in agents)
                  ChoiceChip(
                    label: Text(agent),
                    selected: _agent == agent,
                    onSelected: (_) => setState(() => _agent = agent),
                  ),
              ],
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      children: [
                        _PaneHeader(l10n.t('nav.sessions'), filtered.length),
                        Expanded(
                          child: filtered.isEmpty
                              ? RecordsEmptyState(
                                  title: l10n.t('records.noMatch'),
                                )
                              : ListView.builder(
                                  itemCount: filtered.length,
                                  itemBuilder: (context, i) {
                                    final s = filtered[i];
                                    return ListTile(
                                      selected:
                                          _session?.id.value == s.id.value,
                                      leading: const Icon(
                                        Icons.terminal,
                                        size: 20,
                                      ),
                                      title: Text(s.agent),
                                      subtitle: Text(
                                        fmtDateTime(s.createdAt),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: s.totalTokens > 0
                                          ? Text(
                                              '${fmtCompact(s.totalTokens)} tok',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            )
                                          : null,
                                      onTap: () => _openSession(s),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    flex: 3,
                    child: _requests == null
                        ? Center(child: Text(l10n.t('sess.selectSession')))
                        : AsyncView<List<RequestEntity>>(
                            future: _requests!,
                            builder: (context, requests) => Column(
                              children: [
                                _PaneHeader(
                                  l10n.t('sess.requests'),
                                  requests.length,
                                ),
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: requests.length,
                                    itemBuilder: (context, i) {
                                      final r = requests[i];
                                      return ListTile(
                                        selected:
                                            _request?.id.value == r.id.value,
                                        leading: const Icon(
                                          Icons.person_outline,
                                          size: 20,
                                        ),
                                        title: Text(
                                          r.userText.value,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: Text(
                                          fmtDateTime(r.createdAt),
                                        ),
                                        onTap: () => _openRequest(r),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    flex: 4,
                    child: _messages == null
                        ? Center(child: Text(l10n.t('sess.selectRequest')))
                        : AsyncView<List<MessageEntity>>(
                            future: _messages!,
                            builder: (context, messages) => Column(
                              children: [
                                _PaneHeader(
                                  l10n.t('sess.messages'),
                                  messages.length,
                                ),
                                Expanded(
                                  child: ListView.builder(
                                    padding: const EdgeInsets.all(12),
                                    itemCount: messages.length,
                                    itemBuilder: (context, i) {
                                      final m = messages[i];
                                      return Card(
                                        margin: const EdgeInsets.symmetric(
                                          vertical: 4,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(switch (m.role.code) {
                                                    'assistant' =>
                                                      Icons.smart_toy_outlined,
                                                    'tool' =>
                                                      Icons.build_outlined,
                                                    'user' =>
                                                      Icons.person_outline,
                                                    _ =>
                                                      Icons.settings_outlined,
                                                  }, size: 16),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    m.role.code,
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.labelMedium,
                                                  ),
                                                  const Spacer(),
                                                  Text(
                                                    fmtDateTime(m.createdAt),
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.labelSmall,
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              MarkdownView(
                                                m.content.value,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PaneHeader extends StatelessWidget {
  final String label;
  final int count;
  const _PaneHeader(this.label, this.count);

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Text(
      '$label · $count',
      style: Theme.of(context).textTheme.labelLarge,
    ),
  );
}
