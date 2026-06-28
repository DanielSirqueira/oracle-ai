import 'package:oracle_core/oracle_core.dart';

import 'domain/repositories/capture_repository.dart';
import 'domain/usecases/open_request_usecase.dart';
import 'domain/usecases/recent_sessions_usecase.dart';
import 'domain/usecases/request_messages_usecase.dart';
import 'domain/usecases/request_search_usecase.dart';
import 'domain/usecases/session_history_usecase.dart';
import 'domain/usecases/session_requests_usecase.dart';
import 'external/datasources/database/database_capture_datasource.dart';
import 'infra/datasources/capture_datasource.dart';
import 'infra/repositories/capture_repository_impl.dart';

class CaptureModule extends Module {
  @override
  void binds(AutoInjector i) {
    i
      ..addLazySingleton<CaptureDatasource>(DatabaseCaptureDatasource.new)
      ..addLazySingleton<CaptureRepository>(CaptureRepositoryImpl.new)
      ..addLazySingleton<OpenRequestUsecase>(OpenRequestUsecaseImpl.new)
      ..addLazySingleton<SessionHistoryUsecase>(SessionHistoryUsecaseImpl.new)
      ..addLazySingleton<SessionRequestsUsecase>(SessionRequestsUsecaseImpl.new)
      ..addLazySingleton<RequestMessagesUsecase>(RequestMessagesUsecaseImpl.new)
      ..addLazySingleton<RequestSearchUsecase>(RequestSearchUsecaseImpl.new)
      ..addLazySingleton<RecentSessionsUsecase>(RecentSessionsUsecaseImpl.new);
  }
}
