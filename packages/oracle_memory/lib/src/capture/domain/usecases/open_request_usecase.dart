import 'package:oracle_core/oracle_core.dart';

import '../entities/request_entity.dart';
import '../errors/capture_failure.dart';
import '../repositories/capture_repository.dart';

/// Opens a request (one user demand) and embeds its text so past demands are
/// semantically searchable. Embedding is best-effort: a failing embedder still
/// persists the request (keyword/FTS search only), never blocks capture.
abstract interface class OpenRequestUsecase {
  AsyncResultDart<RequestEntity, CaptureFailure> call(RequestEntity request);
}

class OpenRequestUsecaseImpl implements OpenRequestUsecase {
  final CaptureRepository _repository;
  final Embedder _embedder;
  const OpenRequestUsecaseImpl(this._repository, this._embedder);

  @override
  AsyncResultDart<RequestEntity, CaptureFailure> call(RequestEntity request) async {
    if (request.embedding == null && request.userText.value.trim().isNotEmpty) {
      try {
        final vector = await _embedder.embed(request.userText.value);
        request = request.copyWith(embedding: vector, embeddingModel: _embedder.model);
      } catch (_) {/* persist without embedding */}
    }
    return _repository.openRequest(request);
  }
}
