import 'package:flutter_test/flutter_test.dart';
import 'package:oracle_studio/src/core/fmt.dart';

void main() {
  test('fmtCompact formats thousands and millions', () {
    expect(fmtCompact(999), '999');
    expect(fmtCompact(12300), '12,3k');
    expect(fmtCompact(4500000), '4,5M');
  });

  test('fmtBytes formats sizes', () {
    expect(fmtBytes(512), '512 B');
    expect(fmtBytes(2048), '2,0 kB');
    expect(fmtBytes(3 * 1024 * 1024), '3,0 MB');
  });

  test('fmtDateTime handles null', () {
    expect(fmtDateTime(null), '—');
  });
}
