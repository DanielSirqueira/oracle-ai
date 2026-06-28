import 'data_row_type.dart';

/// Result of a database operation.
class ResultDatabase {
  /// Returned rows; each row maps a column name to a [DataRowType].
  final List<Map<String, DataRowType>> rows;

  /// Number of columns returned.
  final int numberOfColumns;

  /// Number of rows returned.
  final int numberOfRows;

  /// Number of rows affected by the operation.
  final BigInt affectedRows;

  /// Last inserted id (from `INSERT ... RETURNING`).
  final BigInt lastInsertId;

  const ResultDatabase({
    required this.rows,
    required this.numberOfColumns,
    required this.numberOfRows,
    required this.affectedRows,
    required this.lastInsertId,
  });

  /// An empty result.
  factory ResultDatabase.empty() {
    return ResultDatabase(
      rows: const [],
      numberOfColumns: 0,
      numberOfRows: 0,
      affectedRows: BigInt.zero,
      lastInsertId: BigInt.zero,
    );
  }

  ResultDatabase copyWith({
    List<Map<String, DataRowType>>? rows,
    int? numberOfColumns,
    int? numberOfRows,
    BigInt? affectedRows,
    BigInt? lastInsertId,
  }) {
    return ResultDatabase(
      rows: rows ?? this.rows,
      numberOfColumns: numberOfColumns ?? this.numberOfColumns,
      numberOfRows: numberOfRows ?? this.numberOfRows,
      affectedRows: affectedRows ?? this.affectedRows,
      lastInsertId: lastInsertId ?? this.lastInsertId,
    );
  }
}
