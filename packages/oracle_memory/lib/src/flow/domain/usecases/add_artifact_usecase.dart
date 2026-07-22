import 'package:oracle_core/oracle_core.dart';

import '../entities/flow_artifact_entity.dart';
import '../errors/flow_failure.dart';
import '../repositories/flow_repository.dart';

/// Records an artifact a step produced (branch, commit, PR, RFC, doc, memory).
abstract interface class AddArtifactUsecase {
  AsyncResultDart<FlowArtifactEntity, FlowFailure> call(
    FlowArtifactEntity artifact,
  );
}

class AddArtifactUsecaseImpl implements AddArtifactUsecase {
  final FlowRepository _repository;
  const AddArtifactUsecaseImpl(this._repository);

  @override
  AsyncResultDart<FlowArtifactEntity, FlowFailure> call(
    FlowArtifactEntity artifact,
  ) {
    return _repository.addArtifact(artifact);
  }
}
