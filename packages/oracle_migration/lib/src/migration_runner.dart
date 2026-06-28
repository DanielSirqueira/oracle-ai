import 'package:oracle_core/oracle_core.dart';

import 'applied_migration.dart';
import 'migration.dart';
import 'migration_file.dart';
import 'migration_run_report.dart';
import 'migration_status.dart';
import 'migration_verify_report.dart';
import 'sem_ver.dart';

/// Executes migrations — applies them, tracks status, lists pending/applied.
///
/// Operates on the `_migrations` table. Every operation is idempotent:
/// [ensureSchema] can be called repeatedly; [applied]/[pending] don't mutate
/// state.
class MigrationRunner {
  final Database database;
  const MigrationRunner({required this.database});

  /// Creates the `_migrations` table if it does not exist.
  Future<void> ensureSchema() async {
    await database.executeUpdate(const SqlStatement('''
      CREATE TABLE IF NOT EXISTS _migrations (
        id SERIAL PRIMARY KEY,
        version VARCHAR(20) NOT NULL,
        sequence VARCHAR(10) NOT NULL,
        name VARCHAR(255) NOT NULL,
        checksum VARCHAR(64) NOT NULL,
        file_count INTEGER NOT NULL,
        started_at TIMESTAMP NOT NULL,
        finished_at TIMESTAMP,
        status VARCHAR(20) NOT NULL,
        error_message TEXT,
        error_file VARCHAR(255),
        UNIQUE (version, sequence)
      )
    '''));
  }

  /// Lists migrations with status=applied, ordered by semver + sequence.
  ///
  /// Ordering happens in Dart (via [SemVer.compareTo]) — NEVER in SQL, where
  /// `'1.10.0'` would wrongly sort before `'1.2.0'`.
  Future<List<AppliedMigration>> applied() async {
    final result = await database.select(const SqlStatement('''
      SELECT id, version, sequence, name, checksum, file_count,
             started_at, finished_at, status, error_message, error_file
      FROM _migrations
      WHERE status = 'applied'
    '''));

    final list = result.rows.map(_rowToAppliedMigration).toList();
    _sortBySemverSequence(list);
    return list;
  }

  /// Lists everything in `_migrations` (including failed/running), ordered by
  /// `started_at` (chronological order of attempts).
  Future<List<AppliedMigration>> history() async {
    final result = await database.select(const SqlStatement('''
      SELECT id, version, sequence, name, checksum, file_count,
             started_at, finished_at, status, error_message, error_file
      FROM _migrations
      ORDER BY started_at
    '''));

    return result.rows.map(_rowToAppliedMigration).toList();
  }

  static void _sortBySemverSequence(List<AppliedMigration> list) {
    list.sort((a, b) {
      final c = SemVer.parse(a.version).compareTo(SemVer.parse(b.version));
      if (c != 0) return c;
      return a.sequence.compareTo(b.sequence);
    });
  }

  /// Returns the migrations of [all] not yet applied, in the same order.
  Future<List<Migration>> pending(List<Migration> all) async {
    final appliedSet = {
      for (final a in await applied()) '${a.version}/${a.sequence}',
    };
    return all.where((m) => !appliedSet.contains('${m.version}/${m.sequence}')).toList();
  }

  /// Compares the filesystem against the DB and reports drift, removals and
  /// pending migrations.
  Future<MigrationVerifyReport> verify(List<Migration> all) async {
    final appliedList = await applied();
    final fsById = {for (final m in all) '${m.version}/${m.sequence}': m};

    final verified = <AppliedMigration>[];
    final mismatches = <ChecksumMismatch>[];

    for (final a in appliedList) {
      final key = '${a.version}/${a.sequence}';
      final fs = fsById[key];
      if (fs == null) {
        mismatches.add(ChecksumMismatch(applied: a, filesystem: null));
      } else if (fs.checksum != a.checksum) {
        mismatches.add(ChecksumMismatch(applied: a, filesystem: fs));
      } else {
        verified.add(a);
      }
    }

    final appliedKeys = appliedList.map((a) => '${a.version}/${a.sequence}').toSet();
    final pendingList =
        all.where((m) => !appliedKeys.contains('${m.version}/${m.sequence}')).toList();

    return MigrationVerifyReport(
      mismatches: mismatches,
      pending: pendingList,
      verified: verified,
    );
  }

  /// Applies the migrations of [all] not yet run.
  ///
  /// Each migration runs in its own transaction containing ALL its files. The
  /// `_migrations` tracking is done in separate (auto-commit) statements so a
  /// failure record survives the DDL rollback.
  ///
  /// If [atomic] is true, ALL pending migrations run in ONE transaction — if
  /// any fails, none is applied.
  Future<MigrationRunReport> up(
    List<Migration> all, {
    bool dryRun = false,
    bool atomic = false,
  }) async {
    if (atomic) return _upAtomic(all, dryRun: dryRun);
    return _upSequential(all, dryRun: dryRun);
  }

  Future<MigrationRunReport> _upSequential(
    List<Migration> all, {
    required bool dryRun,
  }) async {
    final pendingList = await pending(all);
    final appliedMap = {
      for (final a in await applied()) '${a.version}/${a.sequence}': a,
    };
    final skipped =
        all.where((m) => appliedMap.containsKey('${m.version}/${m.sequence}')).toList();

    final appliedResults = <AppliedMigration>[];
    AppliedMigration? failed;
    final notRun = <Migration>[];

    for (var i = 0; i < pendingList.length; i++) {
      final migration = pendingList[i];

      if (dryRun) {
        appliedResults.add(_fakeAppliedForDryRun(migration));
        continue;
      }

      final trackingResult = await _runMigrationWithTracking(migration);
      if (trackingResult.status == MigrationStatus.applied) {
        appliedResults.add(trackingResult);
      } else {
        failed = trackingResult;
        notRun.addAll(pendingList.sublist(i + 1));
        break;
      }
    }

    return MigrationRunReport(
      applied: appliedResults,
      skipped: skipped,
      failed: failed,
      notRun: notRun,
    );
  }

  Future<MigrationRunReport> _upAtomic(
    List<Migration> all, {
    required bool dryRun,
  }) async {
    final pendingList = await pending(all);
    final appliedMap = {
      for (final a in await applied()) '${a.version}/${a.sequence}': a,
    };
    final skipped =
        all.where((m) => appliedMap.containsKey('${m.version}/${m.sequence}')).toList();

    if (pendingList.isEmpty) {
      return MigrationRunReport(applied: const [], skipped: skipped, failed: null, notRun: const []);
    }

    if (dryRun) {
      return MigrationRunReport(
        applied: pendingList.map(_fakeAppliedForDryRun).toList(),
        skipped: skipped,
        failed: null,
        notRun: const [],
      );
    }

    final appliedIds = <int>[];
    Migration? failedMigration;
    MigrationFile? failedFile;
    Object? failedError;

    await database.executeUpdate(const SqlStatement('BEGIN'));
    try {
      for (final migration in pendingList) {
        final startResult = await database.executeUpdate(SqlStatement(
          '''
INSERT INTO _migrations
             (version, sequence, name, checksum, file_count, started_at, status)
             VALUES (:v, :s, :n, :cs, :fc, NOW(), 'running')
             RETURNING id''',
          {
            'v': migration.version,
            's': migration.sequence,
            'n': migration.name,
            'cs': migration.checksum,
            'fc': migration.files.length,
          },
        ));
        final id = startResult.rows.first['id']!.toInt()!;

        try {
          for (final file in migration.files) {
            failedFile = file;
            await database.executeScript(file.content);
          }
          failedFile = null;

          await database.executeUpdate(SqlStatement(
            "UPDATE _migrations SET status='applied', finished_at=NOW() WHERE id = :id",
            {'id': id},
          ));
          appliedIds.add(id);
        } catch (e) {
          failedMigration = migration;
          failedError = e;
          break;
        }
      }

      if (failedMigration != null) {
        await database.executeUpdate(const SqlStatement('ROLLBACK'));
      } else {
        await database.executeUpdate(const SqlStatement('COMMIT'));
      }
    } catch (_) {
      try {
        await database.executeUpdate(const SqlStatement('ROLLBACK'));
      } catch (_) {/* ignore */}
      rethrow;
    }

    if (failedMigration != null) {
      final failureRecord =
          await _recordFailureSeparately(failedMigration, failedFile, failedError!);
      final failedIndex = pendingList.indexOf(failedMigration);
      return MigrationRunReport(
        applied: const [],
        skipped: skipped,
        failed: failureRecord,
        notRun: pendingList.sublist(failedIndex + 1),
      );
    }

    final appliedResults = await _fetchAppliedByIds(appliedIds);
    return MigrationRunReport(
      applied: appliedResults,
      skipped: skipped,
      failed: null,
      notRun: const [],
    );
  }

  Future<AppliedMigration> _recordFailureSeparately(
    Migration migration,
    MigrationFile? failedFile,
    Object error,
  ) async {
    final result = await database.executeUpdate(SqlStatement(
      '''
INSERT INTO _migrations
         (version, sequence, name, checksum, file_count, started_at, finished_at,
          status, error_message, error_file)
         VALUES (:v, :s, :n, :cs, :fc, NOW(), NOW(), 'failed', :msg, :file)
         RETURNING id, started_at, finished_at''',
      {
        'v': migration.version,
        's': migration.sequence,
        'n': migration.name,
        'cs': migration.checksum,
        'fc': migration.files.length,
        'msg': _extractMessage(error),
        'file': failedFile?.name,
      },
    ));
    final row = result.rows.first;
    return AppliedMigration(
      id: row['id']!.toInt()!,
      version: migration.version,
      sequence: migration.sequence,
      name: migration.name,
      checksum: migration.checksum,
      fileCount: migration.files.length,
      startedAt: row['started_at']!.toDateTime()!,
      finishedAt: row['finished_at']?.toDateTime(),
      status: MigrationStatus.failed,
      errorMessage: _extractMessage(error),
      errorFile: failedFile?.name,
    );
  }

  Future<List<AppliedMigration>> _fetchAppliedByIds(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final placeholders = List.generate(ids.length, (i) => ':id$i').join(', ');
    final params = {for (var i = 0; i < ids.length; i++) 'id$i': ids[i]};
    final result = await database.select(SqlStatement(
      '''SELECT id, version, sequence, name, checksum, file_count,
                started_at, finished_at, status, error_message, error_file
         FROM _migrations
         WHERE id IN ($placeholders)
         ORDER BY id''',
      params,
    ));
    return result.rows.map(_rowToAppliedMigration).toList();
  }

  /// Runs one migration with full `_migrations` tracking.
  Future<AppliedMigration> _runMigrationWithTracking(Migration migration) async {
    final startResult = await database.executeUpdate(SqlStatement(
      '''
INSERT INTO _migrations
         (version, sequence, name, checksum, file_count, started_at, status)
         VALUES (:v, :s, :n, :cs, :fc, NOW(), 'running')
         RETURNING id, started_at''',
      {
        'v': migration.version,
        's': migration.sequence,
        'n': migration.name,
        'cs': migration.checksum,
        'fc': migration.files.length,
      },
    ));

    final id = startResult.rows.first['id']!.toInt()!;
    final startedAt = startResult.rows.first['started_at']!.toDateTime()!;

    MigrationFile? currentFile;
    try {
      await _executeFilesSequentially(migration.files, (f) => currentFile = f);

      await database.executeUpdate(SqlStatement(
        "UPDATE _migrations SET status='applied', finished_at=NOW() WHERE id = :id",
        {'id': id},
      ));

      return AppliedMigration(
        id: id,
        version: migration.version,
        sequence: migration.sequence,
        name: migration.name,
        checksum: migration.checksum,
        fileCount: migration.files.length,
        startedAt: startedAt,
        finishedAt: DateTime.now(),
        status: MigrationStatus.applied,
        errorMessage: null,
        errorFile: null,
      );
    } catch (e) {
      await database.executeUpdate(SqlStatement(
        '''
UPDATE _migrations SET status='failed', finished_at=NOW(),
           error_message=:msg, error_file=:file WHERE id = :id''',
        {
          'id': id,
          'msg': _extractMessage(e),
          'file': currentFile?.name,
        },
      ));

      return AppliedMigration(
        id: id,
        version: migration.version,
        sequence: migration.sequence,
        name: migration.name,
        checksum: migration.checksum,
        fileCount: migration.files.length,
        startedAt: startedAt,
        finishedAt: DateTime.now(),
        status: MigrationStatus.failed,
        errorMessage: _extractMessage(e),
        errorFile: currentFile?.name,
      );
    }
  }

  /// Runs all files of a migration in ONE atomic transaction.
  Future<void> _executeFilesSequentially(
    List<MigrationFile> files,
    void Function(MigrationFile) onBeforeFile,
  ) async {
    await database.executeScript('BEGIN');
    try {
      for (final file in files) {
        onBeforeFile(file);
        await database.executeScript(file.content);
      }
      await database.executeScript('COMMIT');
    } catch (_) {
      try {
        await database.executeScript('ROLLBACK');
      } catch (_) {/* ignore */}
      rethrow;
    }
  }

  AppliedMigration _fakeAppliedForDryRun(Migration m) {
    final now = DateTime.now();
    return AppliedMigration(
      id: -1,
      version: m.version,
      sequence: m.sequence,
      name: m.name,
      checksum: m.checksum,
      fileCount: m.files.length,
      startedAt: now,
      finishedAt: now,
      status: MigrationStatus.applied,
      errorMessage: null,
      errorFile: null,
    );
  }

  String _truncateMessage(String msg) {
    const maxLen = 4000;
    return msg.length <= maxLen ? msg : '${msg.substring(0, maxLen)}... [truncated]';
  }

  /// Extracts a readable message from any error (tries `.errorMessage` first).
  String _extractMessage(Object error) {
    try {
      final dyn = error as dynamic;
      final msg = dyn.errorMessage as String?;
      if (msg != null && msg.isNotEmpty) return _truncateMessage(msg);
    } catch (_) {/* fallback */}
    return _truncateMessage(error.toString());
  }

  AppliedMigration _rowToAppliedMigration(Map<String, DataRowType> row) {
    return AppliedMigration(
      id: row['id']!.toInt()!,
      version: row['version']!.toText()!,
      sequence: row['sequence']!.toText()!,
      name: row['name']!.toText()!,
      checksum: row['checksum']!.toText()!,
      fileCount: row['file_count']!.toInt()!,
      startedAt: row['started_at']!.toDateTime()!,
      finishedAt: row['finished_at']?.toDateTime(),
      status: MigrationStatus.parse(row['status']!.toText()!),
      errorMessage: row['error_message']?.toText(),
      errorFile: row['error_file']?.toText(),
    );
  }
}
