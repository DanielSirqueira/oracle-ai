import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

/// Lists the tools published by an installed Oracle MCP server and validates
/// the protocol-critical surface without involving an LLM.
Future<void> main(List<String> args) async {
  final command = args.isNotEmpty
      ? args.first
      : r'C:\Users\bierb\AppData\Local\Programs\Oracle AI\oracle_ai.exe';
  if (!File(command).existsSync()) {
    stderr.writeln('Oracle executable not found: $command');
    exitCode = 2;
    return;
  }

  final client = Client(
    const Implementation(name: 'oracle-inventory-check', version: '1.0.0'),
  );
  final transport = StdioClientTransport(
    StdioServerParameters(
      command: command,
      stderrMode: ProcessStartMode.normal,
    ),
  );
  try {
    await client.connect(transport);
    final result = await client.listTools();
    final byName = {for (final tool in result.tools) tool.name: tool};
    const required = <String>{
      'oracle_status',
      'oracle_session_brief',
      'oracle_flow_step_context',
      'oracle_flow_context_put',
      'oracle_flow_artifact_add',
      'oracle_flow_step_report',
      'oracle_rfc_get',
      'oracle_rfc_comment',
      'oracle_rfc_evidence_add',
      'oracle_rfc_status',
    };
    final missing = required.difference(byName.keys.toSet()).toList()..sort();
    final unannotated =
        result.tools
            .where((tool) => tool.annotations == null)
            .map((tool) => tool.name)
            .toList()
          ..sort();

    final status = await client.callTool(
      const CallToolRequestParams(name: 'oracle_status', arguments: {}),
    );
    final statusOk = status.isError != true;
    var stepContextOk = true;
    if (args.length > 1) {
      final context = await client.callTool(
        CallToolRequestParams(
          name: 'oracle_flow_step_context',
          arguments: {'runStepId': args[1]},
        ),
      );
      stepContextOk = context.isError != true;
    }
    stdout.writeln('tools=${result.tools.length}');
    stdout.writeln('requiredMissing=${missing.join(',')}');
    stdout.writeln('unannotated=${unannotated.join(',')}');
    stdout.writeln('oracleStatus=${statusOk ? 'ok' : 'error'}');
    if (args.length > 1) {
      stdout.writeln('flowStepContext=${stepContextOk ? 'ok' : 'error'}');
    }
    if (missing.isNotEmpty ||
        unannotated.isNotEmpty ||
        !statusOk ||
        !stepContextOk) {
      exitCode = 1;
    }
  } finally {
    await transport.close();
  }
}
