import 'package:flutter/material.dart';

import 'core/brand.dart';
import 'core/daemon_host.dart';
import 'core/l10n.dart';
import 'core/oracle_connection.dart';
import 'core/settings_store.dart';
import 'shell/home_shell.dart';

/// Root widget: brand theme + the connection gate that leads to the shell once
/// the database is reachable. Rebuilds on language change ([l10n]).
class OracleStudioApp extends StatefulWidget {
  const OracleStudioApp({super.key});

  @override
  State<OracleStudioApp> createState() => _OracleStudioAppState();
}

class _OracleStudioAppState extends State<OracleStudioApp> {
  final _connection = OracleConnection();
  late final DaemonHost _daemon;

  @override
  void initState() {
    super.initState();
    // The daemon side self-starts once the connection is up (per settings).
    final settings = SettingsStore.load();
    l10n.code = settings.language;
    _daemon = DaemonHost(connection: _connection, settings: settings);
    _connection.connect();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_connection, l10n]),
      builder: (context, _) => MaterialApp(
        title: 'Oracle Studio',
        debugShowCheckedModeBanner: false,
        theme: OracleBrand.theme(),
        home: switch (_connection.status) {
          OracleConnectionStatus.connected => HomeShell(
            connection: _connection,
            daemon: _daemon,
          ),
          OracleConnectionStatus.error => _ErrorScreen(connection: _connection),
          _ => const _ConnectingScreen(),
        },
      ),
    );
  }
}

class _ConnectingScreen extends StatelessWidget {
  const _ConnectingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const OracleLogo(size: 96),
            const SizedBox(height: 24),
            const SizedBox(
              width: 160,
              child: LinearProgressIndicator(minHeight: 3),
            ),
            const SizedBox(height: 16),
            Text(l10n.t('app.connecting')),
          ],
        ),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  final OracleConnection connection;
  const _ErrorScreen({required this.connection});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const OracleLogo(size: 64),
              const SizedBox(height: 16),
              GradientTitle(l10n.t('app.connectFailTitle')),
              const SizedBox(height: 8),
              Text(
                connection.error ?? '—',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                connection.envPath == null
                    ? l10n.t('app.noEnv')
                    : '${l10n.t('app.config')}: ${connection.envPath}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: connection.connect,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.t('app.retry')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
