import 'package:oracle_core/oracle_core.dart';

import '../../domain/dtos/filters/skill_search_filter.dart';
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
  Future<SkillEntity?> currentByKey({
    IdVO? productId,
    IdVO? projectId,
    required String key,
  }) async {
    try {
      return await _datasource.currentByKey(
          productId: productId, projectId: projectId, key: key);
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
    IdVO? productId,
  }) async {
    try {
      return Success(
          await _datasource.getSkillByKey(key, projectId: projectId, productId: productId));
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
    IdVO? productId,
    int limit = 200,
  }) async {
    try {
      return Success(
          await _datasource.listSkills(projectId: projectId, productId: productId, limit: limit));
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
