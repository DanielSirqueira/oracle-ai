import 'package:oracle_server/src/flow_runner/agent_doctor.dart';
import 'package:test/test.dart';

void main() {
  test('Codex Oracle MCP requires headless approval defaults', () {
    expect(
      AgentDoctor.codexMcpConfigReady('''
[mcp_servers.oracle-ai]
command = 'oracle_ai.exe'
'''),
      isFalse,
    );
    expect(
      AgentDoctor.codexMcpConfigReady('''
[mcp_servers.oracle-ai]
command = 'oracle_ai.exe'
args = []
required = true
default_tools_approval_mode = "approve"

[mcp_servers.other]
command = 'other.exe'
'''),
      isTrue,
    );
  });

  test('approval on a different server does not satisfy Oracle', () {
    expect(
      AgentDoctor.codexMcpConfigReady('''
[mcp_servers.oracle-ai]
command = 'oracle_ai.exe'
required = true

[mcp_servers.other]
default_tools_approval_mode = "approve"
'''),
      isFalse,
    );
  });

  test('Store-only pwsh is flagged as a Codex sandbox trap', () {
    // Store alias without an MSI install → every sandboxed shell call dies.
    expect(
      AgentDoctor.windowsStorePwshIssue(
        storeAliasExists: true,
        nonStorePwshExists: false,
      ),
      isNotNull,
    );
    // MSI pwsh present (system PATH wins) → healthy.
    expect(
      AgentDoctor.windowsStorePwshIssue(
        storeAliasExists: true,
        nonStorePwshExists: true,
      ),
      isNull,
    );
    // No alias at all → nothing to flag.
    expect(
      AgentDoctor.windowsStorePwshIssue(
        storeAliasExists: false,
        nonStorePwshExists: false,
      ),
      isNull,
    );
  });
}
