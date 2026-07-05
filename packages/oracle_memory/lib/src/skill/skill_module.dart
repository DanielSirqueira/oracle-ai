import 'package:oracle_core/oracle_core.dart';

import 'domain/repositories/skill_repository.dart';
import 'domain/usecases/get_skill_usecase.dart';
import 'domain/usecases/list_skills_usecase.dart';
import 'domain/usecases/retire_skill_usecase.dart';
import 'domain/usecases/save_skill_usecase.dart';
import 'domain/usecases/search_skills_usecase.dart';
import 'external/datasources/database/database_skill_datasource.dart';
import 'infra/datasources/skill_datasource.dart';
import 'infra/repositories/skill_repository_impl.dart';

/// DI bindings for the skill feature (Datasource → Repository → UseCases).
class SkillModule extends Module {
  @override
  void binds(AutoInjector i) {
    i
      ..addLazySingleton<SkillDatasource>(DatabaseSkillDatasource.new)
      ..addLazySingleton<SkillRepository>(SkillRepositoryImpl.new)
      ..addLazySingleton<SaveSkillUsecase>(SaveSkillUsecaseImpl.new)
      ..addLazySingleton<GetSkillUsecase>(GetSkillUsecaseImpl.new)
      ..addLazySingleton<SearchSkillsUsecase>(SearchSkillsUsecaseImpl.new)
      ..addLazySingleton<ListSkillsUsecase>(ListSkillsUsecaseImpl.new)
      ..addLazySingleton<RetireSkillUsecase>(RetireSkillUsecaseImpl.new);
  }
}
