import 'package:oracle_core/oracle_core.dart';

import '../../../memory/domain/entities/memory_entity.dart';
import '../../../memory/domain/enums/memory_kind.dart';
import '../../../memory/domain/enums/memory_tier.dart';
import '../../../memory/domain/usecases/save_memory_usecase.dart';
import '../entities/rfc_decision_entity.dart';
import '../entities/rfc_entity.dart';
import '../enums/rfc_status.dart';
import '../errors/rfc_failure.dart';
import '../repositories/rfc_repository.dart';

/// Finalizes an RFC: enforces the termination gate, routes unresolved product
/// decisions to human review, and — on approval — writes the RFC's decisions
/// back into long-term memory (kind=decision), closing the learning loop.
///
/// Gate (all required to approve):
///   * no VERIFIED critical finding still open (unverified criticals never gate);
///   * every required section of the current version is covered.
/// If the gate holds but some decision is not [humanApproved], the RFC moves to
/// `awaiting_human` instead of `approved` — an agent never self-approves a
/// product decision. Write-back is best-effort and never fails the finalize.
abstract interface class FinalizeRfcUsecase {
  AsyncResultDart<RfcEntity, RfcFailure> call(IdVO rfcId);
}

class FinalizeRfcUsecaseImpl implements FinalizeRfcUsecase {
  final RfcRepository _repository;
  final SaveMemoryUsecase _saveMemory;
  const FinalizeRfcUsecaseImpl(this._repository, this._saveMemory);

  @override
  AsyncResultDart<RfcEntity, RfcFailure> call(IdVO rfcId) async {
    final statusResult = await _repository.rfcStatus(rfcId);
    if (statusResult.isError()) return Failure(statusResult.exceptionOrNull()!);
    final status = statusResult.getOrThrow();

    final bundleResult = await _repository.getRfc(rfcId);
    if (bundleResult.isError()) return Failure(bundleResult.exceptionOrNull()!);
    final rfc = bundleResult.getOrThrow().rfc;

    final decisionsResult = await _repository.listDecisions(rfcId);
    if (decisionsResult.isError()) return Failure(decisionsResult.exceptionOrNull()!);
    final decisions = decisionsResult.getOrThrow();

    // Termination gate. An unverified critical is NOT a blocker (blockingCriticals
    // counts only verified ones), so hallucinated findings can't hold an RFC hostage.
    final blockers = <FieldSystemFailure>[];
    if (status.blockingCriticals > 0) {
      blockers.add(FieldSystemFailure(
        field: 'blockingCriticals',
        message: '${status.blockingCriticals} verified critical finding(s) still open',
      ));
    }
    if (!status.checklistComplete) {
      blockers.add(FieldSystemFailure(
        field: 'checklist',
        message: '${status.coveredRequired}/${status.requiredSections} required sections covered',
      ));
    }
    if (blockers.isNotEmpty) {
      return Failure(ValidatedFieldRfcFailure(
        errorMessage: 'RFC not ready to finalize',
        stackTrace: StackTrace.current,
        fields: blockers,
      ));
    }

    // Human gate for product decisions: any decision not human-approved parks the
    // RFC in awaiting_human — the agent prepares the decision up to the click.
    if (decisions.any((d) => !d.humanApproved)) {
      return _repository.setStatus(rfcId, RfcStatus.awaitingHuman);
    }

    // Write-back: learn each decision as a durable memory (kind=decision), then
    // link it. Best-effort — a failed save/link must not block approval.
    for (final decision in decisions) {
      if (decision.memoryId != null) continue;
      final saved = await _saveMemory(MemoryEntity(
        id: const IdVO.empty(),
        organizationId: rfc.organizationId,
        projectId: rfc.projectId,
        moduleId: rfc.moduleId,
        tier: MemoryTier.semantic,
        kind: MemoryKind.decision,
        title: TextVO(_decisionTitle(rfc, decision)),
        body: TextVO(_decisionBody(decision)),
        tags: const ['rfc', 'decision'],
        importance: 0.7,
      ));
      if (saved.isSuccess()) {
        await _repository.setDecisionMemory(decision.id, saved.getOrThrow().id);
      }
    }

    return _repository.setStatus(rfcId, RfcStatus.approved);
  }

  static String _decisionTitle(RfcEntity rfc, RfcDecisionEntity d) {
    final q = d.question.value.trim();
    return q.isEmpty ? 'Decisão RFC: ${rfc.title.value}' : 'Decisão RFC: $q';
  }

  static String _decisionBody(RfcDecisionEntity d) {
    final parts = <String>[];
    if (d.chosenOption.value.trim().isNotEmpty) parts.add('Opção: ${d.chosenOption.value.trim()}');
    if (d.rationale.value.trim().isNotEmpty) parts.add('Racional: ${d.rationale.value.trim()}');
    return parts.isEmpty ? d.question.value : parts.join('\n\n');
  }
}
