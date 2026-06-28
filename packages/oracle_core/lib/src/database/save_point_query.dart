import 'dart:async';

import 'result_database.dart';
import 'sql_statement.dart';

/// Callback for chained queries inside a save point.
///
/// Receives the [ResultDatabase] of the parent query and returns the dependent
/// [SavePointQuery]s to run next (e.g. children that need a generated id).
typedef SavePointCallback = FutureOr<List<SavePointQuery>> Function(ResultDatabase result);

/// A parameterized query to run within a transactional save point.
class SavePointQuery {
  /// Parameterized statement to execute.
  final SqlStatement statement;

  /// Optional callback to run dependent queries after this one's result.
  final SavePointCallback? savePointCallback;

  SavePointQuery({required this.statement, this.savePointCallback});

  /// Shortcut for [statement] SQL text.
  String get sql => statement.sql;

  /// Shortcut for [statement] params.
  Map<String, Object?> get params => statement.params;

  /// Last inserted id after this query executes.
  BigInt lastInsertId = BigInt.zero;
}
