import 'package:flutter/material.dart';

import 'core/daemon_host.dart';
import 'core/oracle_connection.dart';
import 'core/settings_store.dart';
import 'shell/home_shell.dart';

/// Root widget: dark "studio" theme + the connection gate that leads to the
/// shell once the database is reachable.
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
    _daemon = DaemonHost(connection: _connection, settings: SettingsStore.load());
    _connection.connect();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Oracle Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C6CF0),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        visualDensity: VisualDensity.comfortable,
      ),
      home: AnimatedBuilder(
        animation: _connection,
        builder: (context, _) => switch (_connection.status) {
          OracleConnectionStatus.connected =>
            HomeShell(connection: _connection, daemon: _daemon),
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
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Conectando ao banco de memória…'),
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
              const Icon(Icons.cloud_off, size: 48),
              const SizedBox(height: 16),
              Text('Não foi possível conectar',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                connection.error ?? 'Erro desconhecido',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                connection.envPath == null
                    ? 'Nenhum .env encontrado — usando defaults (localhost:5432). '
                        'Defina ORACLE_ENV_PATH ou coloque um .env na raiz do projeto.'
                    : 'Configuração: ${connection.envPath}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: connection.connect,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
