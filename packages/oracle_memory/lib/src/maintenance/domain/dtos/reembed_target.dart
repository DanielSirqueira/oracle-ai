/// A single row that needs (re-)embedding: its owning table, id, and the exact
/// text the save path embeds. Produced by the datasource (trusted source) and
/// consumed by the re-embed usecase, which embeds [text] and writes it back.
class ReembedTarget {
  /// One of: memories | rules | architectures | requests. Always a fixed
  /// datasource-produced constant — never caller input — so it is safe to map to
  /// a table name.
  final String table;
  final String id;

  /// The text to embed (matches what the save use case concatenates, e.g.
  /// `title\nbody` for a memory).
  final String text;

  const ReembedTarget({required this.table, required this.id, required this.text});
}
