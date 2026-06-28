import 'dart:io';

import 'package:path/path.dart' as p;

import 'errors/invalid_migration_layout_failure.dart';
import 'migration.dart';
import 'migration_file.dart';
import 'sem_ver.dart';

/// Version folder — `v1.0.0`, `v2.10.3`, `v0.0.1`.
final _versionDirRegex = RegExp(r'^v(\d+\.\d+\.\d+)$');

/// Migration folder — `001_baseline`, `010-add-fields`.
final _migrationDirRegex = RegExp(r'^(\d+)[-_](.+)$');

/// SQL file — `001_create_tables.sql`, `010-seed-data.sql`.
final _sqlFileRegex = RegExp(r'^(\d+)[-_](.+)\.sql$');

/// Reads the filesystem and produces the deterministic list of [Migration].
///
/// Output order:
/// 1. Versions ascending (semver).
/// 2. Within a version, migrations ascending (sequence).
/// 3. Within a migration, files ascending (sequence).
///
/// Expected layout:
/// ```
/// {migrationsDirectory}/
///   v1.0.0/
///     001_baseline/
///       001_create_tables.sql
///       002_create_indexes.sql
///     002_add_fields/
///       001_alter.sql
///   v1.1.0/
///     001_hotfix/
///       001_patch.sql
/// ```
class MigrationSource {
  /// Path (absolute or relative to the cwd) of the migrations root folder.
  final String migrationsDirectory;

  const MigrationSource({required this.migrationsDirectory});

  /// Scans the filesystem and returns the ordered list of migrations.
  ///
  /// Throws [InvalidMigrationLayoutFailure] on invalid layout.
  Future<List<Migration>> discover() async {
    final dir = Directory(migrationsDirectory);
    if (!dir.existsSync()) {
      throw InvalidMigrationLayoutFailure(
        errorMessage: 'Migrations directory does not exist',
        path: migrationsDirectory,
        stackTrace: StackTrace.current,
      );
    }

    final versionDirs = <(SemVer, Directory)>[];
    for (final entity in dir.listSync()) {
      if (entity is! Directory) continue;
      final dirName = p.basename(entity.path);
      final match = _versionDirRegex.firstMatch(dirName);
      if (match == null) {
        throw InvalidMigrationLayoutFailure(
          errorMessage:
              'Folder "$dirName" does not match vX.Y.Z (e.g. v1.0.0). Use semver.',
          path: entity.path,
          stackTrace: StackTrace.current,
        );
      }
      versionDirs.add((SemVer.parse(match.group(1)!), entity));
    }

    versionDirs.sort((a, b) => a.$1.compareTo(b.$1));

    final result = <Migration>[];
    for (final (version, versionDir) in versionDirs) {
      result.addAll(_scanVersion(version.toString(), versionDir));
    }
    return result;
  }

  List<Migration> _scanVersion(String version, Directory versionDir) {
    final migrationDirs = <(int, String, String, Directory)>[];
    final seenSequences = <String>{};

    for (final entity in versionDir.listSync()) {
      if (entity is! Directory) continue;
      final dirName = p.basename(entity.path);
      final match = _migrationDirRegex.firstMatch(dirName);
      if (match == null) {
        throw InvalidMigrationLayoutFailure(
          errorMessage:
              'Migration folder "$dirName" does not match <sequence>_<name> (e.g. 001_baseline)',
          path: entity.path,
          stackTrace: StackTrace.current,
        );
      }
      final seqStr = match.group(1)!;
      final name = match.group(2)!;
      if (!seenSequences.add(seqStr)) {
        throw InvalidMigrationLayoutFailure(
          errorMessage: 'Sequence "$seqStr" appears in more than one migration folder in v$version',
          path: entity.path,
          stackTrace: StackTrace.current,
        );
      }
      migrationDirs.add((int.parse(seqStr), seqStr, name, entity));
    }

    migrationDirs.sort((a, b) => a.$1.compareTo(b.$1));

    return migrationDirs
        .map((tuple) => _scanMigration(version, tuple.$2, tuple.$3, tuple.$4))
        .toList();
  }

  Migration _scanMigration(
    String version,
    String sequence,
    String name,
    Directory migrationDir,
  ) {
    final files = <(int, MigrationFile)>[];
    final seenSequences = <String>{};

    for (final entity in migrationDir.listSync()) {
      if (entity is! File) continue;
      final fileName = p.basename(entity.path);
      if (!fileName.endsWith('.sql')) continue;

      final match = _sqlFileRegex.firstMatch(fileName);
      if (match == null) {
        throw InvalidMigrationLayoutFailure(
          errorMessage: 'File "$fileName" does not match <sequence>_<description>.sql',
          path: entity.path,
          stackTrace: StackTrace.current,
        );
      }
      final fileSeq = match.group(1)!;
      if (!seenSequences.add(fileSeq)) {
        throw InvalidMigrationLayoutFailure(
          errorMessage: 'Sequence "$fileSeq" appears in more than one file in '
              'v$version/${sequence}_$name',
          path: entity.path,
          stackTrace: StackTrace.current,
        );
      }

      files.add((
        int.parse(fileSeq),
        MigrationFile(
          sequence: fileSeq,
          name: fileName,
          path: entity.path,
          content: entity.readAsStringSync(),
        ),
      ));
    }

    if (files.isEmpty) {
      throw InvalidMigrationLayoutFailure(
        errorMessage: 'Migration v$version/${sequence}_$name has no SQL files',
        path: migrationDir.path,
        stackTrace: StackTrace.current,
      );
    }

    files.sort((a, b) => a.$1.compareTo(b.$1));
    final orderedFiles = files.map((f) => f.$2).toList();

    return Migration(
      version: version,
      sequence: sequence,
      name: name,
      directoryPath: migrationDir.path,
      files: orderedFiles,
      checksum: Migration.checksumOf(orderedFiles),
    );
  }
}
