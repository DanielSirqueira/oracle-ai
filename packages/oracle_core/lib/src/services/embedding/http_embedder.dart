import 'dart:convert';

import 'package:http/http.dart' as http;

import 'embedder.dart';

/// Embedder backed by an OpenAI-compatible `/embeddings` endpoint.
///
/// Works for OpenAI (`https://api.openai.com/v1`) and Voyage AI
/// (`https://api.voyageai.com/v1`) — both accept `{"model", "input": [text]}`
/// and return `{"data": [{"embedding": [...]}]}`.
class HttpEmbedder implements Embedder {
  @override
  final String model;

  @override
  final int dim;

  final String baseUrl;
  final String apiKey;
  final http.Client _client;

  HttpEmbedder({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.dim,
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  Future<List<double>> embed(String text) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/embeddings'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'input': [text],
      }),
    );
    if (response.statusCode >= 400) {
      throw HttpEmbedderException('Embedding API ${response.statusCode}: ${response.body}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final data = (json['data'] as List).first as Map<String, dynamic>;
    return (data['embedding'] as List).map((e) => (e as num).toDouble()).toList();
  }
}

/// Raised when the embedding API returns an error.
class HttpEmbedderException implements Exception {
  final String message;
  HttpEmbedderException(this.message);
  @override
  String toString() => 'HttpEmbedderException: $message';
}
