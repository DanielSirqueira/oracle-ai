import 'package:oracle_core/oracle_core.dart';

import '../../domain/dtos/filters/skill_search_filter.dart';
import '../../domain/dtos/skill_neighbor.dart';
import '../../domain/dtos/skill_search_result.dart';
import '../../domain/entities/skill_entity.dart';
import '../../domain/errors/skill_failure.dart';
import '../../domain/repositories/skill_repository.dart';
import '../datasources/skill_datasource.dart';

class SkillRepositoryImpl implements SkillRepository {
  final SkillDatasource _datasource;
  const SkillRepositoryImpl({required SkillDatasource datasource}) : _datasource = datasource;

  @override
  AsyncResultDart<SkillEntity, SkillFailure> saveSkill(SkillEntity skill) async {
    try {
      return Success(await _datasource.saveSkill(skill));
    } on SkillFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  Future<List<SkillNeighbor>> nearestByEmbedding({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    required List<double> embedding,
    required String embeddingModel,
    IdVO? excludeId,
    double maxDistance = 0.12,
    int limit = 3,
  }) async {
    try {
      return await _datasource.nearestByEmbedding(
        organizationId: organizationId,
        projectId: projectId,
        moduleId: moduleId,
        embedding: embedding,
        embeddingModel: embeddingModel,
        excludeId: excludeId,
        maxDistance: maxDistance,
        limit: limit,
      );
    } on SkillFailure {
      return const []; // non-critical signal — degrade to no neighbors
    }
  }

  @override
  Future<SkillEntity?> currentByKey({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    required String key,
  }) async {
    try {
      return await _datasource.currentByKey(
          organizationId: organizationId, projectId: projectId, moduleId: moduleId, key: key);
    } on SkillFailure {
      return null; // optimization read only — degrade to a normal save
    }
  }

  @override
  AsyncResultDart<SkillEntity, SkillFailure> getSkillById(IdVO id) async {
    try {
      return Success(await _datasource.getSkillById(id));
    } on SkillFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<SkillEntity, SkillFailure> getSkillByKey(
    String key, {
    IdVO? projectId,
    IdVO? organizationId,
    IdVO? moduleId,
  }) async {
    try {
      return Success(await _datasource.getSkillByKey(key,
          projectId: projectId, organizationId: organizationId, moduleId: moduleId));
    } on SkillFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<List<SkillSearchResult>, SkillFailure> searchSkills(
      SkillSearchFilter filter) async {
    try {
      return Success(await _datasource.searchSkills(filter));
    } on SkillFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<List<SkillEntity>, SkillFailure> listSkills({
    IdVO? projectId,
    IdVO? organizationId,
    int limit = 200,
  }) async {
    try {
      return Success(
          await _datasource.listSkills(projectId: projectId, organizationId: organizationId, limit: limit));
    } on SkillFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<SkillEntity, SkillFailure> retireSkill(
    IdVO id, {
    String? reason,
    bool hard = false,
  }) async {
    try {
      return Success(await _datasource.retireSkill(id, reason: reason, hard: hard));
    } on SkillFailure catch (failure) {
      return Failure(failure);
    }
  }
}
