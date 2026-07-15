import 'package:oracle_core/oracle_core.dart';

import 'domain/repositories/rfc_repository.dart';
import 'domain/usecases/add_comment_usecase.dart';
import 'domain/usecases/add_evidence_usecase.dart';
import 'domain/usecases/close_round_usecase.dart';
import 'domain/usecases/finalize_rfc_usecase.dart';
import 'domain/usecases/get_rfc_usecase.dart';
import 'domain/usecases/list_open_rfcs_usecase.dart';
import 'domain/usecases/open_rfc_usecase.dart';
import 'domain/usecases/record_decision_usecase.dart';
import 'domain/usecases/relate_comments_usecase.dart';
import 'domain/usecases/resolve_comment_usecase.dart';
import 'domain/usecases/revise_rfc_usecase.dart';
import 'domain/usecases/rfc_status_usecase.dart';
import 'domain/usecases/start_round_usecase.dart';
import 'external/datasources/database/database_rfc_datasource.dart';
import 'infra/datasources/rfc_datasource.dart';
import 'infra/repositories/rfc_repository_impl.dart';

/// DI bindings for the RFC feature (Datasource → Repository → UseCases).
/// Requires a `Database` and an `Embedder` to be registered.
class RfcModule extends Module {
  @override
  void binds(AutoInjector i) {
    i
      ..addLazySingleton<RfcDatasource>(DatabaseRfcDatasource.new)
      ..addLazySingleton<RfcRepository>(RfcRepositoryImpl.new)
      ..addLazySingleton<OpenRfcUsecase>(OpenRfcUsecaseImpl.new)
      ..addLazySingleton<GetRfcUsecase>(GetRfcUsecaseImpl.new)
      ..addLazySingleton<ListOpenRfcsUsecase>(ListOpenRfcsUsecaseImpl.new)
      ..addLazySingleton<AddCommentUsecase>(AddCommentUsecaseImpl.new)
      ..addLazySingleton<AddEvidenceUsecase>(AddEvidenceUsecaseImpl.new)
      ..addLazySingleton<ReviseRfcUsecase>(ReviseRfcUsecaseImpl.new)
      ..addLazySingleton<RfcStatusUsecase>(RfcStatusUsecaseImpl.new)
      ..addLazySingleton<RelateCommentsUsecase>(RelateCommentsUsecaseImpl.new)
      ..addLazySingleton<ResolveCommentUsecase>(ResolveCommentUsecaseImpl.new)
      ..addLazySingleton<StartRoundUsecase>(StartRoundUsecaseImpl.new)
      ..addLazySingleton<CloseRoundUsecase>(CloseRoundUsecaseImpl.new)
      ..addLazySingleton<RecordDecisionUsecase>(RecordDecisionUsecaseImpl.new)
      ..addLazySingleton<FinalizeRfcUsecase>(FinalizeRfcUsecaseImpl.new);
  }
}
