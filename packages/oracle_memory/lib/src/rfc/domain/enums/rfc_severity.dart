/// RFC comment severity (matches the `rfc_comments.severity` CHECK constraint).
enum RfcSeverity {
  critical('critical'),
  major('major'),
  minor('minor'),
  info('info');

  /// Value persisted in the database.
  final String code;
  const RfcSeverity(this.code);

  static RfcSeverity parse(String code) =>
      values.firstWhere((e) => e.code == code, orElse: () => RfcSeverity.info);
}
