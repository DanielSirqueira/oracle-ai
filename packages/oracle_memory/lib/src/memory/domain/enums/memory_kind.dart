/// Memory kind (matches the `memories.kind` CHECK constraint).
enum MemoryKind {
  decision('decision'),
  gotcha('gotcha'),
  rule('rule'),
  fact('fact');

  /// Value persisted in the database.
  final String code;
  const MemoryKind(this.code);

  static MemoryKind parse(String code) =>
      values.firstWhere((e) => e.code == code, orElse: () => MemoryKind.fact);
}
