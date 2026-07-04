import 'package:oracle_core/oracle_core.dart';

import '../../domain/dtos/filters/rule_search_filter.dart';
import '../../domain/dtos/rule_neighbor.dart';
import '../../domain/dtos/rule_search_result.dart';
import '../../domain/dtos/rules_for_task_query.dart';
import '../../domain/entities/rule_entity.dart';
import '../../domain/errors/rule_failure.dart';
import '../../domain/repositories/rule_repository.dart';
import '../datasources/rule_datasource.dart';

class RuleRepositoryImpl implements RuleRepository {
  final RuleDatasource _datasource;
  const RuleRepositoryImpl({required RuleDatasource datasource}) : _datasource = datasource;

  @override
  AsyncResultDart<RuleEntity, RuleFailure> saveRule(RuleEntity rule) async {
    try {
      return Success(await _datasource.saveRule(rule));
    } on RuleFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  Future<RuleEntity?> currentByKey({
    IdVO? productId,
    IdVO? projectId,
    required String key,
  }) async {
    try {
      return await _datasource.currentByKey(
          productId: productId, projectId: projectId, key: key);
    } on RuleFailure {
      return null; // optimization read only — degrade to a normal save
    }
  }

  @override
  Future<List<RuleNeighbor>> nearestByEmbedding({
    IdVO? productId,
    IdVO? projectId,
    required List<double> embedding,
    required String embeddingModel,
    IdVO? excludeId,
    double? maxDistance,
    int? limit,
  }) async {
    try {
      return await _datasource.nearestByEmbedding(
        productId: productId,
        projectId: projectId,
        embedding: embedding,
        embeddingModel: embeddingModel,
        excludeId: excludeId,
        maxDistance: maxDistance,
        limit: limit,
      );
    } on RuleFailure {
      return const []; // non-critical signal — degrade to no neighbors
    }
  }

  @override
  AsyncResultDart<List<RuleEntity>, RuleFailure> rulesForTask(RulesForTaskQuery query) async {
    try {
      return Success(await _datasource.rulesForTask(query));
    } on RuleFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<List<RuleSearchResult>, RuleFailure> searchRules(RuleSearchFilter filter) async {
    try {
      return Success(await _datasource.searchRules(filter));
    } on RuleFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<RuleEntity, RuleFailure> retireRule(
    IdVO id, {
    String? reason,
    bool hard = false,
  }) async {
    try {
      return Success(await _datasource.retireRule(id, reason: reason, hard: hard));
    } on RuleFailure catch (failure) {
      return Failure(failure);
    }
  }

  @override
  AsyncResultDart<RuleEntity, RuleFailure> setRulePriority(IdVO id, int priority) async {
    try {
      return Success(await _datasource.setRulePriority(id, priority));
    } on RuleFailure catch (failure) {
      return Failure(failure);
    }
  }
}
