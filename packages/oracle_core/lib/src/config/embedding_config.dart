import 'dart:io';

/// Embedding provider configuration.
class EmbeddingConfig {
  /// `local` | `openai` | `voyage`.
  final String provider;
  final String model;
  final int dim;
  final String? apiKey;
  final String? baseUrl;

  const EmbeddingConfig({
    required this.provider,
    required this.model,
    required this.dim,
    this.apiKey,
    this.baseUrl,
  });

  /// Reads embedding settings from environment variables.
  ///
  /// | Variable                    | Default        |
  /// |-----------------------------|----------------|
  /// | `ORACLE_EMBEDDING_PROVIDER` | `local`        |
  /// | `ORACLE_EMBEDDING_MODEL`    | `local-bow`    |
  /// | `ORACLE_EMBEDDING_DIM`      | `1024`         |
  ///
  /// API keys come from `OPENAI_API_KEY` / `VOYAGE_API_KEY`; base URL defaults
  /// to the provider's standard endpoint.
  factory EmbeddingConfig.fromEnv([Map<String, String>? env]) {
    final e = env ?? Platform.environment;
    final provider = (e['ORACLE_EMBEDDING_PROVIDER'] ?? 'local').toLowerCase();
    final dim = int.tryParse(e['ORACLE_EMBEDDING_DIM'] ?? '') ?? 1024;

    final (defaultModel, defaultBase, key) = switch (provider) {
      'openai' => ('text-embedding-3-small', 'https://api.openai.com/v1', e['OPENAI_API_KEY']),
      'voyage' => ('voyage-3.5', 'https://api.voyageai.com/v1', e['VOYAGE_API_KEY']),
      'gemini' => (
          'gemini-embedding-001',
          'https://generativelanguage.googleapis.com/v1beta',
          e['GEMINI_API_KEY'],
        ),
      _ => ('local-bow', null, null),
    };

    // An empty ORACLE_EMBEDDING_MODEL falls back to the provider's default, so
    // switching provider doesn't require also switching model.
    final envModel = e['ORACLE_EMBEDDING_MODEL'];
    return EmbeddingConfig(
      provider: provider,
      model: (envModel != null && envModel.isNotEmpty) ? envModel : defaultModel,
      dim: dim,
      apiKey: key,
      baseUrl: e['ORACLE_EMBEDDING_BASE_URL'] ?? defaultBase,
    );
  }
}
