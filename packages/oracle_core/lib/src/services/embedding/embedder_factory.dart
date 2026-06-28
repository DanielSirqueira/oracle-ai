import 'dart:io';

import '../../config/embedding_config.dart';
import 'embedder.dart';
import 'gemini_embedder.dart';
import 'http_embedder.dart';
import 'local_embedder.dart';

/// Builds an [Embedder] from [config].
///
/// Falls back to [LocalEmbedder] when a remote provider is selected but no API
/// key is configured (so the system always works out of the box).
Embedder createEmbedder(EmbeddingConfig config) {
  final key = config.apiKey;
  final base = config.baseUrl;

  switch (config.provider) {
    case 'gemini':
      if (key == null || key.isEmpty) {
        return _fallback(config);
      }
      return GeminiEmbedder(
        apiKey: key,
        model: config.model,
        dim: config.dim,
        baseUrl: base ?? 'https://generativelanguage.googleapis.com/v1beta',
      );
    case 'openai':
    case 'voyage':
      if (key == null || key.isEmpty || base == null) {
        return _fallback(config);
      }
      return HttpEmbedder(baseUrl: base, apiKey: key, model: config.model, dim: config.dim);
    default:
      return LocalEmbedder(dim: config.dim);
  }
}

Embedder _fallback(EmbeddingConfig config) {
  stderr.writeln(
    '[oracle] embedding provider "${config.provider}" has no API key — falling back to local.',
  );
  return LocalEmbedder(dim: config.dim);
}
