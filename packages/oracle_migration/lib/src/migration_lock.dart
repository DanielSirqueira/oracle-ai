import 'package:oracle_core/oracle_core.dart';

import 'errors/migration_lock_held_failure.dart';

/// Opaque handle returned by [MigrationLock.acquire].
///
/// Carries the owner that acquired the lock so [MigrationLock.release] only
/// releases it for the same owner (a stale handle from another process can't
/// release the current lock).
class LockHandle {
  /// Process identifier that acquired the lock.
  final String owner;
  const LockHandle(this.owner);
}

/// Exclusive lock to prevent concurrent migrations.
///
/// Backed by the `_migrations_lock` table with a single row (id=1) and a
/// `locked_by` column. Acquire uses `UPDATE ... WHERE locked_by IS NULL`
/// (atomic); if it affects 0 rows another process holds the lock.
class MigrationLock {
  final Database database;
  const MigrationLock({required this.database});

  /// Creates `_migrations_lock` and inserts the single row (id=1) if absent.
  Future<void> ensureTable() async {
    await database.executeUpdate(const SqlStatement('''
      CREATE TABLE IF NOT EXISTS _migrations_lock (
        id INTEGER PRIMARY KEY DEFAULT 1,
        locked_by VARCHAR(100),
        locked_at TIMESTAMP,
        CHECK (id = 1)
      )
    '''));
    await database.executeUpdate(const SqlStatement(
      'INSERT INTO _migrations_lock (id) VALUES (1) ON CONFLICT (id) DO NOTHING',
    ));
  }

  /// How long a held lock may sit before it is considered abandoned (the holder
  /// crashed before releasing). Migrations here run in well under a second, so a
  /// lock older than this is definitively stale and safe to reclaim.
  static const staleAfter = Duration(minutes: 2);

  /// Acquires the lock for [owner]. Throws [MigrationLockHeldFailure] if held by
  /// a live process. A lock older than [staleAfter] is reclaimed (the previous
  /// holder is assumed to have crashed) so a stale lock can never brick startup.
  Future<LockHandle> acquire({required String owner}) async {
    final result = await database.executeUpdate(SqlStatement(
      '''
UPDATE _migrations_lock
         SET locked_by = :owner, locked_at = NOW()
         WHERE id = 1 AND locked_by IS NULL
         RETURNING locked_by''',
      {'owner': owner},
    ));

    if (result.rows.isEmpty) {
      // Try to reclaim a stale lock (crashed holder) atomically.
      final stolen = await database.executeUpdate(SqlStatement(
        '''
UPDATE _migrations_lock
           SET locked_by = :owner, locked_at = NOW()
           WHERE id = 1 AND locked_at < NOW() - INTERVAL '${staleAfter.inSeconds} seconds'
           RETURNING locked_by''',
        {'owner': owner},
      ));
      if (stolen.rows.isNotEmpty) return LockHandle(owner);

      final info = await database.select(const SqlStatement(
        'SELECT locked_by, locked_at FROM _migrations_lock WHERE id = 1',
      ));
      final row = info.rows.isNotEmpty ? info.rows.first : null;
      throw MigrationLockHeldFailure(
        lockedBy: row?['locked_by']?.toText(),
        lockedAt: row?['locked_at']?.toDateTime(),
        stackTrace: StackTrace.current,
      );
    }

    return LockHandle(owner);
  }

  /// Releases the lock if it still belongs to [handle]'s owner (no-op otherwise).
  Future<void> release(LockHandle handle) async {
    await database.executeUpdate(SqlStatement(
      '''
UPDATE _migrations_lock
         SET locked_by = NULL, locked_at = NULL
         WHERE id = 1 AND locked_by = :owner''',
      {'owner': handle.owner},
    ));
  }

  /// Runs [action] holding the lock, releasing it even on exception.
  Future<T> withLock<T>({
    required String owner,
    required Future<T> Function() action,
  }) async {
    final handle = await acquire(owner: owner);
    try {
      return await action();
    } finally {
      await release(handle);
    }
  }
}
