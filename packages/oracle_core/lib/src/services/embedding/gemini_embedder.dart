import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'embedder.dart';
import 'http_embedder.dart' show HttpEmbedderException;

/// Embedder backed by the native Google Gemini `embedContent` API.
///
/// Unlike the OpenAI-compatible endpoint, this sends `outputDimensionality` so
/// the vector matches the `vector(N)` schema (e.g. `gemini-embedding-001`
/// defaults to 3072 but can be truncated to 1024). Truncated MRL embeddings are
/// not pre-normalized, so the result is L2-normalized here.
class GeminiEmbedder implements Embedder {
  @override
  final String model;

  @override
  final int dim;

  final String apiKey;
  final String baseUrl;

  /// Gemini task type (`SEMANTIC_SIMILARITY` keeps documents and queries in the
  /// same symmetric space).
  final String taskType;

  final http.Client _client;

  GeminiEmbedder({
    required this.apiKey,
    this.model = 'gemini-embedding-001',
    this.dim = 1024,
    this.baseUrl = 'https://generativelanguage.googleapis.com/v1beta',
    this.taskType = 'SEMANTIC_SIMILARITY',
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  Future<List<double>> embed(String text) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/models/$model:embedContent'),
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      },
      body: jsonEncode({
        'content': {
          'parts': [
            {'text': text}
          ]
        },
        'outputDimensionality': dim,
        'taskType': taskType,
      }),
    );
    if (response.statusCode >= 400) {
      throw HttpEmbedderException('Gemini ${response.statusCode}: ${response.body}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final values = ((json['embedding'] as Map)['values'] as List)
        .map((e) => (e as num).toDouble())
        .toList();
    return _normalize(values);
  }

  List<double> _normalize(List<double> v) {
    var norm = 0.0;
    for (final x in v) {
      norm += x * x;
    }
    norm = norm == 0 ? 1.0 : sqrt(norm);
    return [for (final x in v) x / norm];
  }
}
