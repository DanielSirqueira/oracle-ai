import 'package:oracle_core/oracle_core.dart';

import 'domain/repositories/handoff_repository.dart';
import 'domain/usecases/accept_handoff_usecase.dart';
import 'domain/usecases/begin_handoff_usecase.dart';
import 'domain/usecases/pending_handoffs_usecase.dart';
import 'domain/usecases/recent_handoffs_usecase.dart';
import 'external/datasources/database/database_handoff_datasource.dart';
import 'infra/datasources/handoff_datasource.dart';
import 'infra/repositories/handoff_repository_impl.dart';

class HandoffModule extends Module {
  @override
  void binds(AutoInjector i) {
    i
      ..addLazySingleton<HandoffDatasource>(DatabaseHandoffDatasource.new)
      ..addLazySingleton<HandoffRepository>(HandoffRepositoryImpl.new)
      ..addLazySingleton<BeginHandoffUsecase>(BeginHandoffUsecaseImpl.new)
      ..addLazySingleton<PendingHandoffsUsecase>(PendingHandoffsUsecaseImpl.new)
      ..addLazySingleton<RecentHandoffsUsecase>(RecentHandoffsUsecaseImpl.new)
      ..addLazySingleton<AcceptHandoffUsecase>(AcceptHandoffUsecaseImpl.new);
  }
}
