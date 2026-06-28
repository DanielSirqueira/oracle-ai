import 'dart:convert';

/// Wraps a single database cell value (stored as a [String]) and exposes
/// type-safe conversions.
///
/// The PostgreSQL implementation stringifies every column value before it
/// reaches this type; the conversions below parse it back on demand.
class DataRowType {
  /// Internal value. `null`, `'null'` and `'NULL'` are all normalized to null.
  final String? _value;

  const DataRowType(String? value)
      : _value = value == null || value == 'null' || value == 'NULL' ? null : value;

  /// Parses the value as [double], or null when absent.
  double? toDouble() => _value != null ? double.parse(_value) : null;

  /// Parses the value as [int], or null when absent.
  int? toInt() => _value != null ? int.parse(_value) : null;

  /// Parses the value as [BigInt], or null when absent.
  BigInt? toBigInt() => _value != null ? BigInt.parse(_value) : null;

  /// Parses the value as [DateTime], or null when absent.
  DateTime? toDateTime() => _value != null ? DateTime.parse(_value) : null;

  /// Parses the value as [bool]. Treats `'true'`, `'1'` or byte `1` as true.
  bool? toBool() => _value != null
      ? _value.toLowerCase() == 'true' || _value == '1' || _value.codeUnits.first == 1
      : null;

  /// Returns the raw text, or null when absent.
  String? toText() => _value;

  /// Parses a vector column into `List<double>`.
  ///
  /// Supports both a JSON array and the native pgvector text format
  /// (`[0.1,0.2,0.3]`). Returns null when absent or unparseable.
  List<double>? toVector() {
    if (_value == null || _value.isEmpty) return null;
    try {
      // JSON array form.
      return List<double>.from(
        (jsonDecode(_value) as List).map((e) => (e as num).toDouble()),
      );
    } catch (_) {
      // Fallback: manual pgvector parsing `[0.1,0.2,0.3]`.
      try {
        final cleaned = _value.replaceAll('[', '').replaceAll(']', '');
        if (cleaned.isEmpty) return null;
        return cleaned.split(',').map((e) => double.tryParse(e.trim()) ?? 0.0).toList();
      } catch (_) {
        return null;
      }
    }
  }

  /// Parses a text/JSON array column into a `List<String>`.
  ///
  /// PostgreSQL `text[]` is delivered to the row builder as a JSON-encoded
  /// array (`["a","b"]`); this decodes it back.
  List<String>? toStringList() {
    if (_value == null || _value.isEmpty) return null;
    try {
      return List<String>.from((jsonDecode(_value) as List).map((e) => e.toString()));
    } catch (_) {
      return null;
    }
  }

  /// Parses a JSON object column into a `Map<String, dynamic>`.
  Map<String, dynamic>? toMap() {
    if (_value == null || _value.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(_value) as Map);
    } catch (_) {
      return null;
    }
  }

  /// Returns a `bytea` column as a Base64 string (the driver delivers raw bytes,
  /// which the PostgreSQL implementation encodes to Base64).
  String? toBytea() {
    if (_value == null || _value.isEmpty) return null;
    return _value;
  }

  /// Decodes a `bytea` column (Base64) back to its UTF-8 text.
  String? toByteaText() {
    if (_value == null || _value.isEmpty) return null;
    try {
      return utf8.decode(base64Decode(_value));
    } catch (_) {
      return _value;
    }
  }

  @override
  String toString() => _value ?? '';
}
