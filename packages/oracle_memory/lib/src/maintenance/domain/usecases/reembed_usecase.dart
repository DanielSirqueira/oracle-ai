import 'package:oracle_core/oracle_core.dart';

import '../dtos/reembed_report.dart';
import '../errors/maintenance_failure.dart';
import '../repositories/maintenance_repository.dart';

/// Re-embeds rows whose vector is missing or was produced by a different model,
/// so they become visible to the current model's semantic recall again (the
/// remedy for the silent-empty-recall symptom after a provider/model switch).
///
/// Agent-driven and bounded: it embeds each target with the CURRENT embedder and
/// writes it back. A per-row embed failure is counted, not fatal — so a flaky
/// provider degrades to partial progress instead of aborting the whole pass.
abstract interface class ReembedUsecase {
  AsyncResultDart<ReembedReport, MaintenanceFailure> call({int limit});
}

class ReembedUsecaseImpl implements ReembedUsecase {
  final MaintenanceRepository _repository;
  final Embedder _embedder;
  const ReembedUsecaseImpl(this._repository, this._embedder);

  @override
  AsyncResultDart<ReembedReport, MaintenanceFailure> call({int limit = 200}) async {
    final model = _embedder.model;
    final targetsResult = await _repository.staleEmbeddingTargets(model, limit);
    if (targetsResult.isError()) {
      return Failure(targetsResult.exceptionOrNull()!);
    }
    final targets = targetsResult.getOrDefault(const []);

    var reembedded = 0;
    var failed = 0;
    for (final target in targets) {
      try {
        final vector = await _embedder.embed(target.text);
        final applied = await _repository.applyEmbedding(target, vector, model);
        applied.fold((_) => reembedded++, (_) => failed++);
      } catch (_) {
        // Embed threw (provider down/timeout) — count and keep going.
        failed++;
      }
    }

    return Success(ReembedReport(
      model: model,
      scanned: targets.length,
      reembedded: reembedded,
      failed: failed,
    ));
  }
}
