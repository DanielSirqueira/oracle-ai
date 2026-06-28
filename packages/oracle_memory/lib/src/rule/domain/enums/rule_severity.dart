/// Rule severity (matches the `rules.severity` CHECK constraint).
///
/// The constant is named `mandatory` (not `required`, a Dart built-in keyword);
/// its persisted [code] is `'required'`.
enum RuleSeverity {
  mandatory('required'),
  recommended('recommended');

  /// Value persisted in the database.
  final String code;
  const RuleSeverity(this.code);

  static RuleSeverity parse(String code) =>
      values.firstWhere((e) => e.code == code, orElse: () => RuleSeverity.recommended);
}
