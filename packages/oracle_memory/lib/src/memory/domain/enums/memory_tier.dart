/// Memory tier (matches the `memories.tier` CHECK constraint).
enum MemoryTier {
  episodic('episodic'),
  semantic('semantic'),
  procedural('procedural');

  /// Value persisted in the database.
  final String code;
  const MemoryTier(this.code);

  static MemoryTier parse(String code) =>
      values.firstWhere((e) => e.code == code, orElse: () => MemoryTier.semantic);
}
