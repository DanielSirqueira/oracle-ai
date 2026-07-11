// Regenerates lib/src/migrations/embedded_migrations.dart from the on-disk
// migrations/ tree, so the binary carries the schema with no filesystem at
// runtime. Run from the repo root:
//
//   dart run packages/oracle_server/tool/gen_embedded_migrations.dart
//
// It reuses MigrationSource.discover() — the exact same ordering and checksum
// logic the runtime uses — so the embedded set can never drift from disk.
// SQL content is normalized to LF before encoding so the embedded bytes are
// stable regardless of the checkout's line-ending policy.
import 'dart:convert';
import 'dart:io';

import 'package:oracle_migration/oracle_migration.dart';

Future<void> main(List<String> args) async {
  final migrationsDir = args.isNotEmpty ? args.first : 'migrations';
  const outPath = 'packages/oracle_server/lib/src/migrations/embedded_migrations.dart';

  final migrations =
      await MigrationSource(migrationsDirectory: migrationsDir).discover();

  final b = StringBuffer()
    ..writeln('// GENERATED — do not edit by hand. Regenerate after changing migrations/:')
    ..writeln('//   dart run packages/oracle_server/tool/gen_embedded_migrations.dart')
    ..writeln("import 'dart:convert';")
    ..writeln()
    ..writeln("import 'package:oracle_migration/oracle_migration.dart';")
    ..writeln()
    ..writeln('/// The migration set embedded in the binary — no filesystem needed at runtime.')
    ..writeln('/// Oracle runs these on startup and applies only what the DB ledger is missing.')
    ..writeln('List<Migration> embeddedMigrations() => <Migration>[');

  for (final m in migrations) {
    b
      ..writeln('      Migration.fromFiles(')
      ..writeln("        version: '${m.version}', sequence: '${m.sequence}', name: '${m.name}',")
      ..writeln('        files: <MigrationFile>[');
    for (final f in m.files) {
      final normalized = f.content.replaceAll('\r\n', '\n');
      final enc = base64.encode(utf8.encode(normalized));
      b
        ..writeln('          MigrationFile(')
        ..writeln("            sequence: '${f.sequence}', name: '${f.name}', path: 'embedded:${f.name}',")
        ..writeln("            content: utf8.decode(base64.decode('$enc')),")
        ..writeln('          ),');
    }
    b
      ..writeln('        ],')
      ..writeln('      ),');
  }
  b.writeln('    ];');

  File(outPath).writeAsStringSync(b.toString());
  stdout.writeln('Wrote $outPath — ${migrations.length} migrations '
      '(${migrations.map((m) => 'v${m.version}/${m.sequence}').join(', ')}).');
}
