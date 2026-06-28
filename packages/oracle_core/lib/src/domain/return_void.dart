import 'package:result_dart/result_dart.dart';

/// Success type for operations that return no value.
///
/// Use with the result pattern: `ResultDart<ReturnVoid, SomeFailure>`, and
/// return `Success(returnVoid)` on success.
typedef ReturnVoid = Unit;

/// The single [ReturnVoid] instance.
const ReturnVoid returnVoid = unit;
