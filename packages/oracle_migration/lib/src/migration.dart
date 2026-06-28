import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'migration_file.dart';

/// A migration identified by (version, sequence, name).
///
/// Each migration is a folder with 1+ [MigrationFile]s. All files run in a
/// **single transaction** — if any fails, the whole migration rolls back.
class Migration {
  /// Semver version, e.g. `'1.0.0'` (without the `v` prefix).
  final String version;

  /// Sequence number within the version, e.g. `'001'`.
  final String sequence;

  /// Descriptive name, e.g. `'baseline'`, `'add_audit_fields'`.
  final String name;

  /// Absolute path of the migration folder.
  final String directoryPath;

  /// SQL files ordered by [MigrationFile.sequence].
  final List<MigrationFile> files;

  /// Combined SHA-256 of file names + contents (hex, 64 chars).
  final String checksum;

  const Migration({
    required this.version,
    required this.sequence,
    required this.name,
    required this.directoryPath,
    required this.files,
    required this.checksum,
  });

  /// Builds a migration from in-memory [files] (e.g. embedded in the binary),
  /// computing the [checksum] the same way the filesystem source does — so an
  /// embedded migration and its on-disk twin share one checksum.
  factory Migration.fromFiles({
    required String version,
    required String sequence,
    required String name,
    required List<MigrationFile> files,
    String? directoryPath,
  }) =>
      Migration(
        version: version,
        sequence: sequence,
        name: name,
        directoryPath: directoryPath ?? 'embedded:v$version/${sequence}_$name',
        files: files,
        checksum: checksumOf(files),
      );

  /// Combined SHA-256 of file names + contents. Order-, name- and
  /// content-sensitive (`name1\n<content1>\nname2\n<content2>...`).
  static String checksumOf(List<MigrationFile> files) {
    final buffer = StringBuffer();
    for (final f in files) {
      buffer
        ..write(f.name)
        ..write('\n')
        ..write(f.content)
        ..write('\n');
    }
    return sha256.convert(utf8.encode(buffer.toString())).toString();
  }

  /// Unique id — `v1.0.0/001_baseline`.
  String get id => 'v$version/${sequence}_$name';

  @override
  String toString() => 'Migration($id, ${files.length} files, $checksum)';
}
