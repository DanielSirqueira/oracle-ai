import 'dart:convert';
import 'dart:developer';

/// Severity of a [SystemFailure] / [FieldSystemFailure].
enum FailureType { error, info, alert }

/// Base failure type for the whole system.
///
/// Implements [Exception] and carries a descriptive message, a stack trace,
/// a human label, a [FailureType] and an optional list of field-level errors.
///
/// Constructing a [SystemFailure] logs the error via `dart:developer`'s [log].
class SystemFailure implements Exception {
  /// Descriptive error message.
  final String errorMessage;

  /// Stack trace associated with the error.
  final StackTrace stackTrace;

  /// Human-readable label (default: `'System Error'`).
  final String label;

  /// Severity of the failure.
  final FailureType failureType;

  /// Field-level errors related to this failure.
  final List<FieldSystemFailure> fields;

  SystemFailure({
    this.label = 'System Error',
    required this.errorMessage,
    required this.stackTrace,
    this.failureType = FailureType.error,
    this.fields = const [],
    Object? exception,
  }) {
    log(label, stackTrace: stackTrace, error: exception);
  }

  @override
  String toString() => '$label: $errorMessage';
}

/// A field-level error attached to a [SystemFailure].
class FieldSystemFailure {
  /// Optional key (e.g. the JSON/field identifier).
  final String? key;

  /// Field name (typically a translated/display label).
  final String field;

  /// Error message for this field.
  final String message;

  /// Severity of this field error.
  final FailureType failureType;

  const FieldSystemFailure({
    this.key,
    required this.field,
    required this.message,
    this.failureType = FailureType.error,
  });

  FieldSystemFailure copyWith({
    String? key,
    String? field,
    String? message,
    FailureType? failureType,
  }) {
    return FieldSystemFailure(
      key: key ?? this.key,
      field: field ?? this.field,
      message: message ?? this.message,
      failureType: failureType ?? this.failureType,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'key': key,
        'field': field,
        'message': message,
        'failureType': failureType.name,
      };

  factory FieldSystemFailure.fromMap(Map<String, dynamic> map) {
    return FieldSystemFailure(
      key: map['key'] as String?,
      field: map['field'] as String,
      message: map['message'] as String,
      failureType: FailureType.values.byName(map['failureType'] as String),
    );
  }

  String toJson() => json.encode(toMap());

  factory FieldSystemFailure.fromJson(String source) =>
      FieldSystemFailure.fromMap(json.decode(source) as Map<String, dynamic>);
}
