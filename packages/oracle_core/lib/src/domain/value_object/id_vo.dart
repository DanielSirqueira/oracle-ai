import 'package:uuid/uuid.dart';

import 'value_object.dart';

const _uuid = Uuid();

/// A UUID identity. Empty (`''`) represents a not-yet-persisted entity (the
/// database assigns the id on insert via `gen_random_uuid()`).
class IdVO extends ValueObject<String> {
  const IdVO(super.value);

  /// Empty id — for new entities before they are persisted.
  const IdVO.empty() : super('');

  /// Generates a time-ordered UUID (v7) on the client when needed.
  factory IdVO.generate() => IdVO(_uuid.v7());

  bool get isEmpty => value.isEmpty;
  bool get isNotEmpty => value.isNotEmpty;
}
