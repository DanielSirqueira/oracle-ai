import 'package:oracle_core/oracle_core.dart';

import 'domain/repositories/rule_repository.dart';
import 'domain/usecases/retire_rule_usecase.dart';
import 'domain/usecases/rules_for_task_usecase.dart';
import 'domain/usecases/save_rule_usecase.dart';
import 'domain/usecases/search_rules_usecase.dart';
import 'domain/usecases/set_rule_priority_usecase.dart';
import 'external/datasources/database/database_rule_datasource.dart';
import 'infra/datasources/rule_datasource.dart';
import 'infra/repositories/rule_repository_impl.dart';

/// DI bindings for the rule feature (Datasource → Repository → UseCases).
class RuleModule extends Module {
  @override
  void binds(AutoInjector i) {
    i
      ..addLazySingleton<RuleDatasource>(DatabaseRuleDatasource.new)
      ..addLazySingleton<RuleRepository>(RuleRepositoryImpl.new)
      ..addLazySingleton<SaveRuleUsecase>(SaveRuleUsecaseImpl.new)
      ..addLazySingleton<RulesForTaskUsecase>(RulesForTaskUsecaseImpl.new)
      ..addLazySingleton<SearchRulesUsecase>(SearchRulesUsecaseImpl.new)
      ..addLazySingleton<RetireRuleUsecase>(RetireRuleUsecaseImpl.new)
      ..addLazySingleton<SetRulePriorityUsecase>(SetRulePriorityUsecaseImpl.new);
  }
}
