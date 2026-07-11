/// Oracle AI domain — feature modules (Clean Architecture + DDD).
library;

// --- project ---
export 'src/project/domain/dtos/filters/project_filter.dart';
export 'src/project/domain/entities/project_entity.dart';
export 'src/project/domain/errors/project_failure.dart';
export 'src/project/domain/repositories/project_repository.dart';
export 'src/project/domain/usecases/get_project_by_id_usecase.dart';
export 'src/project/domain/usecases/list_projects_usecase.dart';
export 'src/project/domain/usecases/register_project_usecase.dart';
export 'src/project/domain/usecases/resolve_project_usecase.dart';
export 'src/project/infra/datasources/project_datasource.dart';
export 'src/project/infra/repositories/project_repository_impl.dart';
export 'src/project/external/datasources/database/database_project_datasource.dart';
export 'src/project/external/mappers/database/database_project_mapper.dart';
export 'src/project/project_module.dart';

// --- memory ---
export 'src/memory/domain/dtos/filters/memory_search_filter.dart';
export 'src/memory/domain/dtos/memory_neighbor.dart';
export 'src/memory/domain/dtos/memory_search_result.dart';
export 'src/memory/domain/entities/memory_entity.dart';
export 'src/memory/domain/enums/memory_kind.dart';
export 'src/memory/domain/enums/memory_tier.dart';
export 'src/memory/domain/errors/memory_failure.dart';
export 'src/memory/domain/repositories/memory_repository.dart';
export 'src/memory/domain/usecases/forget_memory_usecase.dart';
export 'src/memory/domain/usecases/get_memory_by_id_usecase.dart';
export 'src/memory/domain/usecases/relevant_memories_usecase.dart';
export 'src/memory/domain/usecases/save_memory_usecase.dart';
export 'src/memory/domain/usecases/search_memories_usecase.dart';
export 'src/memory/domain/usecases/top_memories_usecase.dart';
export 'src/memory/infra/datasources/memory_datasource.dart';
export 'src/memory/infra/repositories/memory_repository_impl.dart';
export 'src/memory/external/datasources/database/database_memory_datasource.dart';
export 'src/memory/external/mappers/database/database_memory_mapper.dart';
export 'src/memory/memory_module.dart';

// --- rule ---
export 'src/rule/domain/dtos/filters/rule_search_filter.dart';
export 'src/rule/domain/dtos/rule_neighbor.dart';
export 'src/rule/domain/dtos/rule_search_result.dart';
export 'src/rule/domain/dtos/rules_for_task_query.dart';
export 'src/rule/domain/entities/rule_entity.dart';
export 'src/rule/domain/enums/rule_severity.dart';
export 'src/rule/domain/errors/rule_failure.dart';
export 'src/rule/domain/repositories/rule_repository.dart';
export 'src/rule/domain/usecases/retire_rule_usecase.dart';
export 'src/rule/domain/usecases/rules_for_task_usecase.dart';
export 'src/rule/domain/usecases/save_rule_usecase.dart';
export 'src/rule/domain/usecases/search_rules_usecase.dart';
export 'src/rule/domain/usecases/set_rule_priority_usecase.dart';
export 'src/rule/infra/datasources/rule_datasource.dart';
export 'src/rule/infra/repositories/rule_repository_impl.dart';
export 'src/rule/external/datasources/database/database_rule_datasource.dart';
export 'src/rule/external/mappers/database/database_rule_mapper.dart';
export 'src/rule/rule_module.dart';

// --- skill ---
export 'src/skill/domain/dtos/filters/skill_search_filter.dart';
export 'src/skill/domain/dtos/skill_neighbor.dart';
export 'src/skill/domain/dtos/skill_search_result.dart';
export 'src/skill/domain/entities/skill_entity.dart';
export 'src/skill/domain/errors/skill_failure.dart';
export 'src/skill/domain/repositories/skill_repository.dart';
export 'src/skill/domain/usecases/get_skill_usecase.dart';
export 'src/skill/domain/usecases/list_skills_usecase.dart';
export 'src/skill/domain/usecases/retire_skill_usecase.dart';
export 'src/skill/domain/usecases/save_skill_usecase.dart';
export 'src/skill/domain/usecases/search_skills_usecase.dart';
export 'src/skill/infra/datasources/skill_datasource.dart';
export 'src/skill/infra/repositories/skill_repository_impl.dart';
export 'src/skill/external/datasources/database/database_skill_datasource.dart';
export 'src/skill/external/mappers/database/database_skill_mapper.dart';
export 'src/skill/skill_module.dart';

// --- organization ---
export 'src/organization/domain/dtos/filters/organization_filter.dart';
export 'src/organization/domain/entities/organization_entity.dart';
export 'src/organization/domain/errors/organization_failure.dart';
export 'src/organization/domain/repositories/organization_repository.dart';
export 'src/organization/domain/usecases/get_organization_by_id_usecase.dart';
export 'src/organization/domain/usecases/list_organizations_usecase.dart';
export 'src/organization/domain/usecases/register_organization_usecase.dart';
export 'src/organization/infra/datasources/organization_datasource.dart';
export 'src/organization/infra/repositories/organization_repository_impl.dart';
export 'src/organization/external/datasources/database/database_organization_datasource.dart';
export 'src/organization/external/mappers/database/database_organization_mapper.dart';
export 'src/organization/organization_module.dart';

// --- architecture ---
export 'src/architecture/domain/dtos/filters/architecture_search_filter.dart';
export 'src/architecture/domain/dtos/architecture_search_result.dart';
export 'src/architecture/domain/entities/architecture_entity.dart';
export 'src/architecture/domain/errors/architecture_failure.dart';
export 'src/architecture/domain/repositories/architecture_repository.dart';
export 'src/architecture/domain/usecases/get_architecture_by_area_usecase.dart';
export 'src/architecture/domain/usecases/retire_architecture_usecase.dart';
export 'src/architecture/domain/usecases/save_architecture_usecase.dart';
export 'src/architecture/domain/usecases/search_architecture_usecase.dart';
export 'src/architecture/infra/datasources/architecture_datasource.dart';
export 'src/architecture/infra/repositories/architecture_repository_impl.dart';
export 'src/architecture/external/datasources/database/database_architecture_datasource.dart';
export 'src/architecture/external/mappers/database/database_architecture_mapper.dart';
export 'src/architecture/architecture_module.dart';

// --- maintenance ---
export 'src/maintenance/domain/dtos/decay_policy.dart';
export 'src/maintenance/domain/dtos/lint_report.dart';
export 'src/maintenance/domain/dtos/maintenance_report.dart';
export 'src/maintenance/domain/dtos/reembed_report.dart';
export 'src/maintenance/domain/dtos/reembed_target.dart';
export 'src/maintenance/domain/errors/maintenance_failure.dart';
export 'src/maintenance/domain/repositories/maintenance_repository.dart';
export 'src/maintenance/domain/usecases/lint_usecase.dart';
export 'src/maintenance/domain/usecases/reembed_usecase.dart';
export 'src/maintenance/domain/usecases/run_maintenance_usecase.dart';
export 'src/maintenance/infra/datasources/maintenance_datasource.dart';
export 'src/maintenance/infra/repositories/maintenance_repository_impl.dart';
export 'src/maintenance/external/datasources/database/database_maintenance_datasource.dart';
export 'src/maintenance/maintenance_module.dart';

// --- metrics ---
export 'src/metrics/domain/dtos/metric_delta.dart';
export 'src/metrics/domain/dtos/metrics_summary.dart';
export 'src/metrics/domain/entities/session_metric_entity.dart';
export 'src/metrics/domain/errors/metrics_failure.dart';
export 'src/metrics/domain/repositories/metrics_repository.dart';
export 'src/metrics/domain/usecases/add_session_metric_usecase.dart';
export 'src/metrics/domain/usecases/metrics_summary_usecase.dart';
export 'src/metrics/domain/usecases/recent_metrics_usecase.dart';
export 'src/metrics/infra/datasources/metrics_datasource.dart';
export 'src/metrics/infra/repositories/metrics_repository_impl.dart';
export 'src/metrics/external/datasources/database/database_metrics_datasource.dart';
export 'src/metrics/metrics_module.dart';

// --- handoff ---
export 'src/handoff/domain/enums/handoff_status.dart';
export 'src/handoff/domain/entities/handoff_entity.dart';
export 'src/handoff/domain/errors/handoff_failure.dart';
export 'src/handoff/domain/repositories/handoff_repository.dart';
export 'src/handoff/domain/usecases/accept_handoff_usecase.dart';
export 'src/handoff/domain/usecases/begin_handoff_usecase.dart';
export 'src/handoff/domain/usecases/pending_handoffs_usecase.dart';
export 'src/handoff/domain/usecases/recent_handoffs_usecase.dart';
export 'src/handoff/infra/datasources/handoff_datasource.dart';
export 'src/handoff/infra/repositories/handoff_repository_impl.dart';
export 'src/handoff/external/datasources/database/database_handoff_datasource.dart';
export 'src/handoff/external/mappers/database/database_handoff_mapper.dart';
export 'src/handoff/handoff_module.dart';

// --- capture ---
export 'src/capture/domain/enums/agent_event_kind.dart';
export 'src/capture/domain/enums/message_role.dart';
export 'src/capture/domain/entities/agent_event_entity.dart';
export 'src/capture/domain/entities/message_entity.dart';
export 'src/capture/domain/entities/request_entity.dart';
export 'src/capture/domain/entities/session_entity.dart';
export 'src/capture/domain/errors/capture_failure.dart';
export 'src/capture/domain/repositories/capture_repository.dart';
export 'src/capture/domain/usecases/open_request_usecase.dart';
export 'src/capture/domain/usecases/recent_sessions_usecase.dart';
export 'src/capture/domain/usecases/request_messages_usecase.dart';
export 'src/capture/domain/usecases/request_search_usecase.dart';
export 'src/capture/domain/usecases/session_history_usecase.dart';
export 'src/capture/domain/usecases/session_requests_usecase.dart';
export 'src/capture/infra/datasources/capture_datasource.dart';
export 'src/capture/infra/repositories/capture_repository_impl.dart';
export 'src/capture/external/datasources/database/database_capture_datasource.dart';
export 'src/capture/external/mappers/database/database_capture_mapper.dart';
export 'src/capture/capture_module.dart';
