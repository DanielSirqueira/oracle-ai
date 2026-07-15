/// RFC comment type (matches the `rfc_comments.type` CHECK constraint).
enum RfcCommentType {
  gap('gap'),
  inconsistency('inconsistency'),
  risk('risk'),
  bug('bug'),
  question('question'),
  improvement('improvement'),
  blocker('blocker'),
  nit('nit');

  /// Value persisted in the database.
  final String code;
  const RfcCommentType(this.code);

  static RfcCommentType parse(String code) => values.firstWhere(
        (e) => e.code == code,
        orElse: () => RfcCommentType.improvement,
      );
}
