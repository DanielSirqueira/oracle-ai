/// Handoff state (matches the `handoffs.status` CHECK constraint).
enum HandoffStatus {
  open('open'),
  accepted('accepted'),
  expired('expired');

  final String code;
  const HandoffStatus(this.code);

  static HandoffStatus parse(String code) =>
      values.firstWhere((e) => e.code == code, orElse: () => HandoffStatus.open);
}
