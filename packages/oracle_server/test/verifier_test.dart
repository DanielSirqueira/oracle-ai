import 'package:oracle_server/src/flow_runner/verifier.dart';
import 'package:test/test.dart';

void main() {
  test('invalid exit criteria fails closed', () async {
    final result = await Verifier().run(
      exitCriteriaJson: '{invalid',
      workdir: '.',
    );
    expect(result.passed, isFalse);
    expect(result.details, contains('invalid exit criteria JSON'));
  });

  test('empty valid criteria passes without starting a process', () async {
    final result = await Verifier().run(
      exitCriteriaJson: '{}',
      workdir: '.',
    );
    expect(result.passed, isTrue);
    expect(result.details, contains('no verifier commands'));
  });
}
