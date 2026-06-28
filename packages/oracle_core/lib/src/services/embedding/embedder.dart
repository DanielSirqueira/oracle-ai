/// Generates embedding vectors for text (for pgvector semantic search).
///
/// Implementations: [LocalEmbedder] (offline, deterministic bag-of-words) and
/// [HttpEmbedder] (OpenAI-compatible / Voyage). All vectors are L2-normalized,
/// so cosine distance (`<=>`) and inner product rank identically.
abstract interface class Embedder {
  /// Model identifier stored alongside each vector (invariant: one model per
  /// index — see `embedding_model` columns).
  String get model;

  /// Vector dimension (must match the `vector(N)` columns).
  int get dim;

  /// Embeds [text] into a [dim]-length unit vector.
  Future<List<double>> embed(String text);
}
