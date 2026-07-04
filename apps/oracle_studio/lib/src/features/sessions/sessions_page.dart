import 'package:flutter/material.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';

import '../../core/fmt.dart';
import '../../widgets/async_view.dart';

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
      _requests = injector
          .get<SessionRequestsUsecase>()(s.id, limit: 100)
          .then((r) => r.getOrThrow());
    });
  }

  void _openRequest(RequestEntity r) {
    setState(() {
      _request = r;
      _messages = injector
          .get<RequestMessagesUsecase>()(r.id, limit: 200)
          .then((r) => r.getOrThrow());
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_sessions == null) return const Center(child: Text('Selecione um projeto.'));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── sessions ──
        Expanded(
          flex: 2,
          child: AsyncView<List<SessionEntity>>(
            future: _sessions!,
            builder: (context, sessions) => ListView.builder(
              itemCount: sessions.length,
              itemBuilder: (context, i) {
                final s = sessions[i];
                return ListTile(
                  selected: _session?.id.value == s.id.value,
                  leading: const Icon(Icons.terminal, size: 20),
                  title: Text(s.agent),
                  subtitle: Text(fmtDateTime(s.createdAt),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => _openSession(s),
                );
              },
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        // ── requests ──
        Expanded(
          flex: 3,
          child: _requests == null
              ? const Center(child: Text('Selecione uma sessão.'))
              : AsyncView<List<RequestEntity>>(
                  future: _requests!,
                  builder: (context, requests) => ListView.builder(
                    itemCount: requests.length,
                    itemBuilder: (context, i) {
                      final r = requests[i];
                      return ListTile(
                        selected: _request?.id.value == r.id.value,
                        leading: const Icon(Icons.person_outline, size: 20),
                        title: Text(r.userText.value,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(fmtDateTime(r.createdAt)),
                        onTap: () => _openRequest(r),
                      );
                    },
                  ),
                ),
        ),
        const VerticalDivider(width: 1),
        // ── messages ──
        Expanded(
          flex: 4,
          child: _messages == null
              ? const Center(child: Text('Selecione uma demanda.'))
              : AsyncView<List<MessageEntity>>(
                  future: _messages!,
                  builder: (context, messages) => ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, i) {
                      final m = messages[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    switch (m.role.code) {
                                      'assistant' => Icons.smart_toy_outlined,
                                      'tool' => Icons.build_outlined,
                                      'user' => Icons.person_outline,
                                      _ => Icons.settings_outlined,
                                    },
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(m.role.code,
                                      style: Theme.of(context).textTheme.labelMedium),
                                  const Spacer(),
                                  Text(fmtDateTime(m.createdAt),
                                      style: Theme.of(context).textTheme.labelSmall),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                m.content.value,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
