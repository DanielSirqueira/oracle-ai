import 'package:oracle_core/oracle_core.dart';

import '../../domain/dtos/rfc_bundle.dart';
import '../../domain/dtos/rfc_comment_neighbor.dart';
import '../../domain/dtos/rfc_status_report.dart';
import '../../domain/entities/rfc_comment_entity.dart';
import '../../domain/entities/rfc_entity.dart';
import '../../domain/entities/rfc_evidence_entity.dart';
import '../../domain/entities/rfc_section_entity.dart';
import '../../domain/entities/rfc_version_entity.dart';
import '../../domain/errors/rfc_failure.dart';
import '../../domain/repositories/rfc_repository.dart';
import '../datasources/rfc_datasource.dart';

class RfcRepositoryImpl implements RfcRepository {
  final RfcDatasource _datasource;
  const RfcRepositoryImpl({required RfcDatasource datasource}) : _datasource = datasource;

  @override
  AsyncResultDart<RfcEntity, RfcFailure> openRfc(
    RfcEntity rfc,
    RfcVersionEntity version,
    List<RfcSectionEntity> sections,
  ) async {
    try {
      return Success(await _datasource.openRfc(rfc, version, sections));
    } on RfcFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<RfcBundle, RfcFailure> getRfc(IdVO id) async {
    try {
      return Success(await _datasource.getRfc(id));
    } on RfcFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<List<RfcEntity>, RfcFailure> listOpenRfcs({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    int limit = 50,
  }) async {
    try {
      return Success(await _datasource.listOpenRfcs(
        organizationId: organizationId,
        projectId: projectId,
        moduleId: moduleId,
        limit: limit,
      ));
    } on RfcFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<RfcCommentEntity, RfcFailure> addComment(RfcCommentEntity comment) async {
    try {
      return Success(await _datasource.addComment(comment));
    } on RfcFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<RfcEvidenceEntity, RfcFailure> addEvidence(RfcEvidenceEntity evidence) async {
    try {
      return Success(await _datasource.addEvidence(evidence));
    } on RfcFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  Future<List<RfcCommentNeighbor>> nearestComments({
    required IdVO rfcId,
    required List<double> embedding,
    required String embeddingModel,
    IdVO? excludeId,
    double maxDistance = 0.12,
    int limit = 3,
  }) async {
    try {
      return await _datasource.nearestComments(
        rfcId: rfcId,
        embedding: embedding,
        embeddingModel: embeddingModel,
        excludeId: excludeId,
        maxDistance: maxDistance,
        limit: limit,
      );
    } on RfcFailure {
      return const []; // non-critical signal — degrade to no neighbors
    }
  }

  @override
  AsyncResultDart<RfcVersionEntity, RfcFailure> reviseRfc(
    RfcVersionEntity version,
    List<RfcSectionEntity> sections,
  ) async {
    try {
      return Success(await _datasource.reviseRfc(version, sections));
    } on RfcFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<RfcStatusReport, RfcFailure> rfcStatus(IdVO rfcId) async {
    try {
      return Success(await _datasource.rfcStatus(rfcId));
    } on RfcFailure catch (failure) {
      return Failure(failure);
    }
  }
}
