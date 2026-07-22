import 'dart:io';

import 'package:oracle_server/src/migrations/embedded_migrations.dart';

void main() {
  final m = embeddedMigrations().firstWhere((x) => x.version == '2.1.0');
  stdout.writeln(
    'version=${m.version}|sequence=${m.sequence}|name=${m.name}|files=${m.files.length}|checksum=${m.checksum}',
  );
}
