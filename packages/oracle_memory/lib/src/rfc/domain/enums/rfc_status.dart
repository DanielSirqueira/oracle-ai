/// RFC lifecycle status (matches the `rfcs.status` CHECK constraint).
enum RfcStatus {
  draft('draft'),
  openForComments('open_for_comments'),
  inReview('in_review'),
  inConsolidation('in_consolidation'),
  awaitingHuman('awaiting_human'),
  stalled('stalled'),
  approved('approved'),
  rejected('rejected'),
  superseded('superseded'),
  obsolete('obsolete');

  /// Value persisted in the database.
  final String code;
  const RfcStatus(this.code);

  static RfcStatus parse(String code) =>
      values.firstWhere((e) => e.code == code, orElse: () => RfcStatus.draft);
}
