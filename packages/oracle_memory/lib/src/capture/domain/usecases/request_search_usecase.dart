import 'package:oracle_core/oracle_core.dart';

import '../entities/request_entity.dart';
import '../errors/capture_failure.dart';
import '../repositories/capture_repository.dart';

/// Embeds a query and returns the project's past user demands ranked by semantic
/// similarity — a searchable history of "what has the user asked for here".
/// Returns empty when embedding fails (never blocks).
abstract interface class RequestSearchUsecase {
  AsyncResultDart<List<RequestEntity>, CaptureFailure> call(
    IdVO projectId,
    String query, {
    int limit,
  });
}

class RequestSearchUsecaseImpl implements RequestSearchUsecase {
  final CaptureRepository _repository;
  final Embedder _embedder;
  const RequestSearchUsecaseImpl(this._repository, this._embedder);

  @override
  AsyncResultDart<List<RequestEntity>, CaptureFailure> call(
    IdVO projectId,
    String query, {
    int limit = 10,
  }) async {
    if (query.trim().isEmpty) return const Success([]);
    List<double> vector;
    try {
      vector = await _embedder.embed(query);
    } catch (_) {
      return const Success([]);
    }
    return _repository.searchRequests(projectId, vector, limit: limit, queryModel: _embedder.model);
  }
}
