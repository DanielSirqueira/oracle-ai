import 'dart:convert';
import 'dart:io';

/// Generators for the client wiring (so an agent host like Claude Code can use
/// Oracle with no hand-written config). Printed to stdout for the user to merge.

String mcpJson({String? command}) {
  final entry = {
    'mcpServers': {
      'oracle-ai': {
        'type': 'stdio',
        'command': command ?? Platform.resolvedExecutable,
        'args': <String>[],
        // DB + embedding settings are read from the project's .env (loadEnv).
      },
    },
  };
  return const JsonEncoder.withIndent('  ').convert(entry);
}

String hooksJson({String host = '127.0.0.1', int port = 49500}) {
  final url = 'http://$host:$port/hook';
  Map<String, Object> http({bool async = false, String? matcher}) => {
        if (matcher != null) 'matcher': matcher,
        'hooks': [
          {'type': 'http', 'url': url, if (async) 'async': true},
        ],
      };
  final entry = {
    'hooks': {
      'SessionStart': [http()], // sync — injects the session brief
      'UserPromptSubmit': [http()], // sync — injects per-prompt recall
      'Stop': [http(async: true)], // async capture
      'PostToolUse': [http(async: true, matcher: '*')],
      'PostCompact': [http(async: true)],
      'SessionEnd': [http(async: true)],
    },
  };
  return const JsonEncoder.withIndent('  ').convert(entry);
}

void printInstallMcp({String? command}) {
  stdout.writeln('# Merge into .mcp.json (project root) — the Oracle AI MCP server.');
  if (command == null) {
    stdout.writeln('# Tip: pass the compiled binary path: install-mcp <path-to-oracle_ai>');
  }
  stdout.writeln(mcpJson(command: command));
}

void printInstallHooks({String host = '127.0.0.1', int port = 49500}) {
  stdout
    ..writeln('# Merge the "hooks" block into your Claude Code settings.json.')
    ..writeln('# SessionStart + UserPromptSubmit are SYNCHRONOUS (they inject recalled')
    ..writeln('# context); the capture hooks are async so they never block the agent.')
    ..writeln('# The Oracle server must be running its hook receiver on this port.')
    ..writeln(hooksJson(host: host, port: port));
}
