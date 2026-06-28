import 'value_object.dart';

/// Free-form text value object.
class TextVO extends ValueObject<String> {
  const TextVO(super.value);

  const TextVO.empty() : super('');

  /// True when the trimmed text is empty.
  bool get isBlank => value.trim().isEmpty;

  /// True when the trimmed text has content.
  bool get isNotBlank => value.trim().isNotEmpty;

  int get length => value.length;
}
