import 'package:oracle_server/src/install.dart';
import 'package:test/test.dart';

void main() {
  test('Codex snippet makes Oracle required and pre-approves its tools', () {
    final codex = agentIntegrations(
      command: r'C:\Oracle AI\oracle_ai.exe',
    ).singleWhere((agent) => agent.id == 'codex');
    expect(codex.mcpSnippet, contains('[mcp_servers.oracle-ai]'));
    expect(codex.mcpSnippet, contains('required = true'));
    expect(
      codex.mcpSnippet,
      contains('default_tools_approval_mode = "approve"'),
    );
    expect(codex.mcpSnippet, contains('tool_timeout_sec = 300'));
  });

  test('persistent protocol accepts the Codex programmatic MCP surface', () {
    final protocol = agentProtocol();
    expect(protocol, contains('functions.exec'));
    expect(protocol, contains('tools.mcp__oracle_ai__oracle_*'));
    expect(protocol, contains('do not refuse'));
    expect(protocol, contains('oracle_flow_step_report'));
  });
}
