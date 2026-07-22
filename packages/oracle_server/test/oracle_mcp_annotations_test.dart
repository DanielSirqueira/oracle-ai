import 'package:oracle_server/src/mcp/oracle_mcp_server.dart';
import 'package:test/test.dart';

void main() {
  test('flow context is advertised as a closed-world read', () {
    final hints = OracleMcpServer.toolAnnotationsFor(
      'oracle_flow_step_context',
    );
    expect(hints.readOnlyHint, isTrue);
    expect(hints.destructiveHint, isFalse);
    expect(hints.openWorldHint, isFalse);
  });

  test('step report is safe, closed-world and idempotent', () {
    final hints = OracleMcpServer.toolAnnotationsFor('oracle_flow_step_report');
    expect(hints.readOnlyHint, isFalse);
    expect(hints.destructiveHint, isFalse);
    expect(hints.idempotentHint, isTrue);
    expect(hints.openWorldHint, isFalse);
  });

  test('explicit removal remains destructive', () {
    final hints = OracleMcpServer.toolAnnotationsFor('oracle_memory_forget');
    expect(hints.readOnlyHint, isFalse);
    expect(hints.destructiveHint, isTrue);
    expect(hints.openWorldHint, isFalse);
  });

  test(
    'new Oracle writes default to non-destructive closed-world operations',
    () {
      final hints = OracleMcpServer.toolAnnotationsFor('oracle_future_write');
      expect(hints.readOnlyHint, isFalse);
      expect(hints.destructiveHint, isFalse);
      expect(hints.openWorldHint, isFalse);
    },
  );
}
