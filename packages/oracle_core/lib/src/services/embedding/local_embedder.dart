import 'dart:math';

import 'embedder.dart';

/// Offline, deterministic embedder using **signed feature hashing** over a
/// bag of word tokens.
///
/// Texts that share tokens get overlapping (and thus cosine-similar) vectors,
/// so it produces meaningful—if crude—semantic similarity without any API key.
/// Ideal for local development, tests, and the zero-cost default. For real
/// semantic quality use [HttpEmbedder] with a managed model.
class LocalEmbedder implements Embedder {
  @override
  final int dim;

  LocalEmbedder({this.dim = 1024});

  @override
  String get model => 'local-bow-$dim';

  static final _tokenSplit = RegExp(r'[^a-z0-9]+');

  @override
  Future<List<double>> embed(String text) async {
    final vec = List<double>.filled(dim, 0.0);
    final tokens = text.toLowerCase().split(_tokenSplit).where((t) => t.isNotEmpty);
    for (final token in tokens) {
      final index = _fnv1a(token) % dim;
      final sign = _fnv1a('sign:$token') % 2 == 0 ? 1.0 : -1.0;
      vec[index] += sign;
    }

    var norm = 0.0;
    for (final v in vec) {
      norm += v * v;
    }
    norm = norm == 0 ? 1.0 : sqrt(norm);
    for (var i = 0; i < dim; i++) {
      vec[i] /= norm;
    }
    return vec;
  }

  /// FNV-1a hash (32-bit), returned as a non-negative int.
  int _fnv1a(String s) {
    var hash = 2166136261;
    for (final c in s.codeUnits) {
      hash ^= c;
      hash = (hash * 16777619) & 0xFFFFFFFF;
    }
    return hash;
  }
}
