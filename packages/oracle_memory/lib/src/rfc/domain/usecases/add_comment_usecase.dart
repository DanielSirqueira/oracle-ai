import 'package:collection/collection.dart';
import 'package:oracle_core/oracle_core.dart';

import '../entities/rfc_comment_entity.dart';
import '../enums/rfc_comment_type.dart';
import '../errors/rfc_failure.dart';
import '../repositories/rfc_repository.dart';

/// Appends a structured finding to an RFC after validation.
///
/// Guardrails: a non-blank problem is required; a proposed solution is required
/// for actionable finding types (gap/inconsistency/bug/blocker). The finding is
/// embedded best-effort and deduped against existing near-twins — a near-twin
/// demotes the new comment to `duplicate` and links it to the twin.
abstract interface class AddCommentUsecase {
  AsyncResultDart<RfcCommentEntity, RfcFailure> call(RfcCommentEntity comment);
}

class AddCommentUsecaseImpl implements AddCommentUsecase {
  final RfcRepository _repository;
  final Embedder _embedder;
  const AddCommentUsecaseImpl(this._repository, this._embedder);

  /// Finding types that must carry a fix — a finding without a way forward is
  /// noise for these.
  static const _solutionRequired = {
    RfcCommentType.gap,
    RfcCommentType.inconsistency,
    RfcCommentType.bug,
    RfcCommentType.blocker,
  };

  /// Near-duplicate guard: a comment landing within this cosine distance of an
  /// existing finding on the same RFC is flagged a duplicate of it.
  static const _dedupDistance = 0.12;

  @override
  AsyncResultDart<RfcCommentEntity, RfcFailure> call(RfcCommentEntity comment) async {
    final fields = <FieldSystemFailure>[];
    if (comment.problem.isBlank) {
      fields.add(const FieldSystemFailure(field: 'problem', message: 'Required'));
    }
    if (_solutionRequired.contains(comment.type) && comment.proposedSolution.isBlank) {
      fields.add(const FieldSystemFailure(
          field: 'proposedSolution', message: 'Required for this finding type'));
    }
    if (fields.isNotEmpty) {
      return Failure(ValidatedFieldRfcFailure(
        errorMessage: 'Invalid comment',
        stackTrace: StackTrace.current,
        fields: fields,
      ));
    }

    // Embed the finding (problem + rationale + proposed solution) when not
    // provided (best-effort: a failing embedder degrades to no dedup signal).
    if (comment.embedding == null) {
      try {
        final substrate = '${comment.problem.value}\n'
            '${comment.rationale.value}\n'
            '${comment.proposedSolution.value}';
        final vector = await _embedder.embed(substrate);
        comment = comment.copyWith(embedding: vector, embeddingModel: _embedder.model);
      } catch (_) {/* add without embedding */}
    }

    // Near-duplicate guard: when a near-twin already exists on this RFC, mark the
    // incoming finding a duplicate and link it to the twin instead of piling up.
    if (comment.embedding != null && comment.embeddingModel != null) {
      try {
        final near = await _repository.nearestComments(
          rfcId: comment.rfcId,
          embedding: comment.embedding!,
          embeddingModel: comment.embeddingModel!,
          maxDistance: _dedupDistance,
          limit: 1,
        );
        final twin = near.firstOrNull;
        if (twin != null) {
          comment = comment.copyWith(status: 'duplicate', parentCommentId: twin.comment.id);
        }
      } catch (_) {/* fall back to a plain insert */}
    }

    return _repository.addComment(comment);
  }
}
