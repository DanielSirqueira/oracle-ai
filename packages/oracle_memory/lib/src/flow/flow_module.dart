import 'package:oracle_core/oracle_core.dart';

import 'domain/repositories/flow_repository.dart';
import 'domain/usecases/add_artifact_usecase.dart';
import 'domain/usecases/control_flow_run_usecase.dart';
import 'domain/usecases/create_task_usecase.dart';
import 'domain/usecases/decide_gate_usecase.dart';
import 'domain/usecases/flow_run_status_usecase.dart';
import 'domain/usecases/get_flow_usecase.dart';
import 'domain/usecases/list_flow_runs_usecase.dart';
import 'domain/usecases/list_flows_usecase.dart';
import 'domain/usecases/list_tasks_usecase.dart';
import 'domain/usecases/put_context_usecase.dart';
import 'domain/usecases/report_step_usecase.dart';
import 'domain/usecases/save_flow_usecase.dart';
import 'domain/usecases/start_flow_run_usecase.dart';
import 'domain/usecases/step_context_usecase.dart';
import 'domain/usecases/update_task_usecase.dart';
import 'external/datasources/database/database_flow_datasource.dart';
import 'infra/datasources/flow_datasource.dart';
import 'infra/repositories/flow_repository_impl.dart';

/// DI bindings for the Loop Engineering (flow) feature
/// (Datasource → Repository → UseCases). Requires a `Database` and an `Embedder`
/// to be registered.
class FlowModule extends Module {
  @override
  void binds(AutoInjector i) {
    i
      ..addLazySingleton<FlowDatasource>(DatabaseFlowDatasource.new)
      ..addLazySingleton<FlowRepository>(FlowRepositoryImpl.new)
      ..addLazySingleton<CreateTaskUsecase>(CreateTaskUsecaseImpl.new)
      ..addLazySingleton<ListTasksUsecase>(ListTasksUsecaseImpl.new)
      ..addLazySingleton<UpdateTaskUsecase>(UpdateTaskUsecaseImpl.new)
      ..addLazySingleton<SaveFlowUsecase>(SaveFlowUsecaseImpl.new)
      ..addLazySingleton<ListFlowsUsecase>(ListFlowsUsecaseImpl.new)
      ..addLazySingleton<GetFlowUsecase>(GetFlowUsecaseImpl.new)
      ..addLazySingleton<StartFlowRunUsecase>(StartFlowRunUsecaseImpl.new)
      ..addLazySingleton<FlowRunStatusUsecase>(FlowRunStatusUsecaseImpl.new)
      ..addLazySingleton<ListFlowRunsUsecase>(ListFlowRunsUsecaseImpl.new)
      ..addLazySingleton<ControlFlowRunUsecase>(ControlFlowRunUsecaseImpl.new)
      ..addLazySingleton<DecideGateUsecase>(DecideGateUsecaseImpl.new)
      ..addLazySingleton<StepContextUsecase>(StepContextUsecaseImpl.new)
      ..addLazySingleton<PutContextUsecase>(PutContextUsecaseImpl.new)
      ..addLazySingleton<AddArtifactUsecase>(AddArtifactUsecaseImpl.new)
      ..addLazySingleton<ReportStepUsecase>(ReportStepUsecaseImpl.new);
  }
}
