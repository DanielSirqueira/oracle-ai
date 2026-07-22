import 'package:oracle_core/oracle_core.dart';

import '../../../domain/dtos/flow_graph.dart';
import '../../../domain/dtos/flow_run_bundle.dart';
import '../../../domain/dtos/step_context.dart';
import '../../../domain/dtos/task_neighbor.dart';
import '../../../domain/entities/flow_artifact_entity.dart';
import '../../../domain/entities/flow_edge_entity.dart';
import '../../../domain/entities/flow_entity.dart';
import '../../../domain/entities/flow_run_context_entity.dart';
import '../../../domain/entities/flow_run_entity.dart';
import '../../../domain/entities/flow_run_event_entity.dart';
import '../../../domain/entities/flow_run_step_entity.dart';
import '../../../domain/entities/flow_step_entity.dart';
import '../../../domain/entities/task_entity.dart';
import '../../../domain/enums/flow_run_status.dart';
import '../../../domain/enums/flow_run_step_status.dart';
import '../../../domain/enums/task_status.dart';
import '../../../domain/errors/flow_failure.dart';
import '../../../infra/datasources/flow_datasource.dart';
import '../../mappers/database/database_flow_artifact_mapper.dart';
import '../../mappers/database/database_flow_edge_mapper.dart';
import '../../mappers/database/database_flow_mapper.dart';
import '../../mappers/database/database_flow_run_context_mapper.dart';
import '../../mappers/database/database_flow_run_event_mapper.dart';
import '../../mappers/database/database_flow_run_mapper.dart';
import '../../mappers/database/database_flow_run_step_mapper.dart';
import '../../mappers/database/database_flow_step_mapper.dart';
import '../../mappers/database/database_task_mapper.dart';

/// PostgreSQL + pgvector backed [FlowDatasource]. Ids are generated client-side
/// (uuid v7) so a savepoint can wire a flow's steps and edges in one transaction.
/// Vector / jsonb columns are cast to text on read so [DataRowType] can parse
/// them; jsonb is carried as raw JSON text end-to-end.
class DatabaseFlowDatasource implements FlowDatasource {
  final Database _database;
  const DatabaseFlowDatasource({required Database database})
    : _database = database;

  static const _taskColumns =
      'id, organization_id, project_id, module_id, title, description, status, '
      'priority, source, rfc_id, created_by, embedding::text AS embedding, '
      'embedding_model, created_at, updated_at';

  static const _flowColumns =
      'id, organization_id, project_id, module_id, key, name, description, '
      'orchestrator_agent, entry_step_key, budgets::text AS budgets, version_no, '
      'is_latest, supersedes, retired_at, retired_reason, created_at, updated_at';

  static const _stepColumns =
      'id, flow_id, step_key, name, kind, agent, model, role, prompt_template, '
      'command, output_schema::text AS output_schema, permissions::text AS permissions, '
      'exit_criteria::text AS exit_criteria, max_iterations, token_budget, '
      'timeout_minutes, on_fail, config::text AS config, position, created_at';

  static const _edgeColumns =
      'id, flow_id, from_step, to_step, condition, verdict_value, instruction, created_at';

  static const _runColumns =
      'id, flow_id, task_id, project_id, status, current_step_id, branch_name, '
      'worktree_path, budgets::text AS budgets, tokens_used, started_by, claimed_by, '
      'heartbeat_at, error, execution_state::text AS execution_state, lease_epoch, '
      'parent_run_id, created_at, started_at, ended_at';

  static const _runStepColumns =
      'id, run_id, step_id, iteration, status, agent, session_id, agent_session_id, claim_token, '
      'rendered_prompt, report::text AS report, verifier::text AS verifier, '
      'tokens_used, started_at, ended_at';

  static const _contextColumns =
      'run_id, key, value::text AS value, updated_by, updated_at';

  static const _artifactColumns =
      'id, run_id, run_step_id, kind, locator, meta::text AS meta, created_at';

  static const _eventColumns =
      'id, run_id, run_step_id, kind, payload::text AS payload, created_at';

  // ── tasks ────────────────────────────────────────────────────────────────

  @override
  Future<TaskEntity> createTask(TaskEntity task) async {
    try {
      final result = await _database.executeUpdate(
        SqlStatement(
          'INSERT INTO tasks '
          '(organization_id, project_id, module_id, title, description, status, '
          'priority, source, rfc_id, created_by, embedding, embedding_model) '
          'VALUES (:organization_id::uuid, :project_id::uuid, :module_id::uuid, :title, '
          ':description, :status, :priority, :source, :rfc_id::uuid, :created_by, '
          ':embedding::vector(1024), :embedding_model) '
          'RETURNING id, created_at, updated_at',
          DatabaseTaskMapper.toInsertParams(task),
        ),
      );
      final row = result.rows.first;
      return task.copyWith(
        id: IdVO(row['id']!.toText()!),
        createdAt: row['created_at']?.toDateTime(),
        updatedAt: row['updated_at']?.toDateTime(),
      );
    } on DatabaseFailure catch (error) {
      throw DatasourceFlowFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  @override
  Future<TaskEntity> getTask(IdVO id) async {
    try {
      final result = await _database.select(
        SqlStatement('SELECT $_taskColumns FROM tasks WHERE id = :id::uuid', {
          'id': id.value,
        }),
      );
      if (result.rows.isEmpty) {
        throw FlowNotFoundFailure(stackTrace: StackTrace.current);
      }
      return DatabaseTaskMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceFlowFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  @override
  Future<List<TaskEntity>> listTasks({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    String? status,
    String? search,
    int? limit,
  }) async {
    try {
      final params = <String, Object?>{'lim': limit ?? 50};
      final where = <String>[];
      final owners = <String>[];
      if (moduleId != null) {
        owners.add('module_id = :mid::uuid');
        params['mid'] = moduleId.value;
      }
      if (projectId != null) {
        owners.add('project_id = :pid::uuid');
        params['pid'] = projectId.value;
      }
      if (organizationId != null) {
        owners.add('organization_id = :oid::uuid');
        params['oid'] = organizationId.value;
      }
      if (owners.isNotEmpty) where.add('(${owners.join(' OR ')})');
      if (status != null && status.isNotEmpty) {
        where.add('status = :status');
        params['status'] = status;
      }
      if (search != null && search.trim().isNotEmpty) {
        where.add('(title ILIKE :q OR description ILIKE :q)');
        params['q'] = '%${search.trim()}%';
      }
      final clause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')} ';
      final result = await _database.select(
        SqlStatement(
          'SELECT $_taskColumns FROM tasks $clause'
          'ORDER BY priority DESC, updated_at DESC LIMIT :lim',
          params,
        ),
      );
      return result.rows.map(DatabaseTaskMapper.fromRow).toList();
    } on DatabaseFailure catch (error) {
      throw DatasourceFlowFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  @override
  Future<TaskEntity> updateTask(
    IdVO id, {
    TaskStatus? status,
    int? priority,
    String? description,
  }) async {
    try {
      final sets = <String>['updated_at = now()'];
      final params = <String, Object?>{'id': id.value};
      if (status != null) {
        sets.add('status = :status');
        params['status'] = status.code;
      }
      if (priority != null) {
        sets.add('priority = :priority');
        params['priority'] = priority;
      }
      if (description != null) {
        sets.add('description = :description');
        params['description'] = description;
      }
      final result = await _database.executeUpdate(
        SqlStatement(
          'UPDATE tasks SET ${sets.join(', ')} WHERE id = :id::uuid '
          'RETURNING $_taskColumns',
          params,
        ),
      );
      if (result.rows.isEmpty) {
        throw FlowNotFoundFailure(stackTrace: StackTrace.current);
      }
      return DatabaseTaskMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceFlowFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  @override
  Future<List<TaskNeighbor>> nearestTasks({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    required List<double> embedding,
    required String embeddingModel,
    IdVO? excludeId,
    double? maxDistance,
    int? limit,
  }) async {
    try {
      final params = <String, Object?>{
        'vec': SqlVector(embedding),
        'model': embeddingModel,
        'maxd': maxDistance ?? 0.15,
        'lim': limit ?? 3,
        'xid': excludeId?.value,
      };
      final owners = <String>[];
      if (moduleId != null) {
        owners.add('module_id = :mid::uuid');
        params['mid'] = moduleId.value;
      }
      if (projectId != null) {
        owners.add('project_id = :pid::uuid');
        params['pid'] = projectId.value;
      }
      if (organizationId != null) {
        owners.add('organization_id = :oid::uuid');
        params['oid'] = organizationId.value;
      }
      final scope = <String>[
        'embedding IS NOT NULL',
        'embedding_model = :model',
        '(:xid::uuid IS NULL OR id <> :xid::uuid)',
        '(embedding <=> :vec::vector(1024)) < :maxd',
      ];
      if (owners.isNotEmpty) scope.add('(${owners.join(' OR ')})');
      final result = await _database.select(
        SqlStatement(
          'SELECT $_taskColumns, (embedding <=> :vec::vector(1024)) AS distance '
          'FROM tasks WHERE ${scope.join(' AND ')} ORDER BY distance LIMIT :lim',
          params,
        ),
      );
      return result.rows
          .map(
            (r) => TaskNeighbor(
              task: DatabaseTaskMapper.fromRow(r),
              distance: r['distance']?.toDouble() ?? 1.0,
            ),
          )
          .toList();
    } on DatabaseFailure catch (error) {
      throw DatasourceFlowFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  // ── flows ──────────────────────────────────────────────────────────────

  @override
  Future<FlowGraph> saveFlow(
    FlowEntity flow,
    List<FlowStepEntity> steps,
    List<FlowEdgeEntity> edges,
  ) async {
    try {
      final flowId = IdVO.generate();

      // Prior latest of the same key in the same scope (for version_no + supersede).
      final priorResult = await _database.select(
        SqlStatement(
          'SELECT id, version_no FROM flows '
          'WHERE is_latest AND key = :key '
          'AND organization_id IS NOT DISTINCT FROM :oid::uuid '
          'AND project_id IS NOT DISTINCT FROM :pid::uuid '
          'AND module_id IS NOT DISTINCT FROM :mid::uuid LIMIT 1',
          {
            'key': flow.key,
            'oid': flow.organizationId?.value,
            'pid': flow.projectId?.value,
            'mid': flow.moduleId?.value,
          },
        ),
      );
      final prior = priorResult.rows.isEmpty ? null : priorResult.rows.first;
      final priorId = prior?['id']?.toText();
      final versionNo = (prior?['version_no']?.toInt() ?? 0) + 1;

      // step_key -> generated id, so edges can reference steps by key.
      final stepIds = <String, IdVO>{
        for (final s in steps) s.stepKey: IdVO.generate(),
      };

      final queries = <SavePointQuery>[];
      if (priorId != null) {
        queries.add(
          SavePointQuery(
            statement: SqlStatement(
              'UPDATE flows SET is_latest = false, updated_at = now() WHERE id = :id::uuid',
              {'id': priorId},
            ),
          ),
        );
      }

      final flowParams = DatabaseFlowMapper.toInsertParams(flow)
        ..['id'] = flowId.value
        ..['version_no'] = versionNo
        ..['is_latest'] = true
        ..['supersedes'] = priorId;
      queries.add(
        SavePointQuery(
          statement: SqlStatement(
            'INSERT INTO flows '
            '(id, organization_id, project_id, module_id, key, name, description, '
            'orchestrator_agent, entry_step_key, budgets, version_no, is_latest, supersedes) '
            'VALUES (:id::uuid, :organization_id::uuid, :project_id::uuid, :module_id::uuid, '
            ':key, :name, :description, :orchestrator_agent, :entry_step_key, :budgets::jsonb, '
            ':version_no, :is_latest, :supersedes::uuid)',
            flowParams,
          ),
        ),
      );

      for (final step in steps) {
        final params = DatabaseFlowStepMapper.toInsertParams(
          step.copyWith(flowId: flowId),
        )..['id'] = stepIds[step.stepKey]!.value;
        queries.add(
          SavePointQuery(
            statement: SqlStatement(
              'INSERT INTO flow_steps '
              '(id, flow_id, step_key, name, kind, agent, model, role, prompt_template, command, '
              'output_schema, permissions, exit_criteria, max_iterations, token_budget, '
              'timeout_minutes, on_fail, config, position) '
              'VALUES (:id::uuid, :flow_id::uuid, :step_key, :name, :kind, :agent, :model, :role, '
              ':prompt_template, :command, :output_schema::jsonb, :permissions::jsonb, '
              ':exit_criteria::jsonb, :max_iterations, :token_budget, :timeout_minutes, :on_fail, '
              ':config::jsonb, :position)',
              params,
            ),
          ),
        );
      }

      for (final edge in edges) {
        final fromId =
            stepIds[edge.fromStep.value]?.value ?? edge.fromStep.value;
        final toId = stepIds[edge.toStep.value]?.value ?? edge.toStep.value;
        queries.add(
          SavePointQuery(
            statement: SqlStatement(
              'INSERT INTO flow_edges (id, flow_id, from_step, to_step, condition, verdict_value, '
              'instruction) '
              'VALUES (:id::uuid, :flow_id::uuid, :from_step::uuid, :to_step::uuid, :condition, '
              ':verdict_value, :instruction)',
              {
                'id': IdVO.generate().value,
                'flow_id': flowId.value,
                'from_step': fromId,
                'to_step': toId,
                'condition': edge.condition,
                'verdict_value': edge.verdictValue,
                'instruction': edge.instruction,
              },
            ),
          ),
        );
      }

      await _database.executeSavePoint(queries);
      return getFlow(flowId);
    } on DatabaseFailure catch (error) {
      throw DatasourceFlowFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  @override
  Future<FlowGraph> getFlow(IdVO id) async {
    try {
      final flowResult = await _database.select(
        SqlStatement('SELECT $_flowColumns FROM flows WHERE id = :id::uuid', {
          'id': id.value,
        }),
      );
      if (flowResult.rows.isEmpty) {
        throw FlowNotFoundFailure(stackTrace: StackTrace.current);
      }
      final flow = DatabaseFlowMapper.fromRow(flowResult.rows.first);

      final stepResult = await _database.select(
        SqlStatement(
          'SELECT $_stepColumns FROM flow_steps WHERE flow_id = :id::uuid '
          'ORDER BY position, created_at',
          {'id': id.value},
        ),
      );
      final steps = stepResult.rows
          .map(DatabaseFlowStepMapper.fromRow)
          .toList();

      final edgeResult = await _database.select(
        SqlStatement(
          'SELECT $_edgeColumns FROM flow_edges WHERE flow_id = :id::uuid ORDER BY created_at',
          {'id': id.value},
        ),
      );
      final edges = edgeResult.rows
          .map(DatabaseFlowEdgeMapper.fromRow)
          .toList();

      return FlowGraph(flow: flow, steps: steps, edges: edges);
    } on DatabaseFailure catch (error) {
      throw DatasourceFlowFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  @override
  Future<FlowGraph?> getFlowByKey({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    required String key,
  }) async {
    try {
      final params = <String, Object?>{'key': key};
      final owners = <String>[];
      if (moduleId != null) {
        owners.add('module_id = :mid::uuid');
        params['mid'] = moduleId.value;
      }
      if (projectId != null) {
        owners.add('project_id = :pid::uuid');
        params['pid'] = projectId.value;
      }
      if (organizationId != null) {
        owners.add('organization_id = :oid::uuid');
        params['oid'] = organizationId.value;
      }
      final scope = <String>['is_latest', 'key = :key'];
      if (owners.isNotEmpty) scope.add('(${owners.join(' OR ')})');
      final result = await _database.select(
        SqlStatement(
          'SELECT id FROM flows WHERE ${scope.join(' AND ')} '
          'ORDER BY (module_id IS NOT NULL) DESC, (project_id IS NOT NULL) DESC LIMIT 1',
          params,
        ),
      );
      if (result.rows.isEmpty) return null;
      return getFlow(IdVO(result.rows.first['id']!.toText()!));
    } on DatabaseFailure catch (error) {
      throw DatasourceFlowFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  @override
  Future<List<FlowEntity>> listFlows({
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    int? limit,
  }) async {
    try {
      final params = <String, Object?>{'lim': limit ?? 50};
      final owners = <String>[];
      if (moduleId != null) {
        owners.add('module_id = :mid::uuid');
        params['mid'] = moduleId.value;
      }
      if (projectId != null) {
        owners.add('project_id = :pid::uuid');
        params['pid'] = projectId.value;
      }
      if (organizationId != null) {
        owners.add('organization_id = :oid::uuid');
        params['oid'] = organizationId.value;
      }
      final scope = <String>['is_latest'];
      if (owners.isNotEmpty) scope.add('(${owners.join(' OR ')})');
      final result = await _database.select(
        SqlStatement(
          'SELECT $_flowColumns FROM flows WHERE ${scope.join(' AND ')} '
          'ORDER BY (module_id IS NOT NULL) DESC, (project_id IS NOT NULL) DESC, '
          'updated_at DESC LIMIT :lim',
          params,
        ),
      );
      return result.rows.map(DatabaseFlowMapper.fromRow).toList();
    } on DatabaseFailure catch (error) {
      throw DatasourceFlowFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  // ── runs ────────────────────────────────────────────────────────────────

  @override
  Future<FlowRunEntity> startRun(FlowRunEntity run) async {
    try {
      final params = DatabaseFlowRunMapper.toInsertParams(run);
      params.addAll({
        'guard_task_id': run.taskId?.value,
        'guard_task_id_check': run.taskId?.value,
        'existing_task_id_check': run.taskId?.value,
        'existing_task_id_query': run.taskId?.value,
        'guard_parent_id': run.parentRunId?.value,
        'guard_parent_id_check': run.parentRunId?.value,
      });
      final result = await _database.executeUpdate(
        SqlStatement(
          'WITH task_lock AS MATERIALIZED ('
          'SELECT id FROM tasks '
          'WHERE id = :guard_task_id::uuid AND :guard_task_id_check::uuid IS NOT NULL '
          'AND :guard_parent_id::uuid IS NULL '
          "AND status NOT IN ('running', 'done', 'cancelled') FOR UPDATE"
          '), eligible AS ('
          'SELECT 1 WHERE :existing_task_id_check::uuid IS NULL OR :guard_parent_id_check::uuid IS NOT NULL '
          'UNION ALL '
          'SELECT 1 FROM task_lock WHERE NOT EXISTS ('
          'SELECT 1 FROM flow_runs WHERE task_id = :existing_task_id_query::uuid '
          "AND parent_run_id IS NULL AND status NOT IN ('completed', 'failed', 'cancelled')"
          ')), inserted AS ('
          'INSERT INTO flow_runs (flow_id, task_id, project_id, status, budgets, started_by, '
          'execution_state, parent_run_id, claimed_by, heartbeat_at, lease_epoch) '
          'SELECT :flow_id::uuid, :task_id::uuid, :project_id::uuid, :status, :budgets::jsonb, '
          ':started_by, :execution_state::jsonb, :parent_run_id::uuid, :claimed_by::text, '
          'CASE WHEN :claimed_by::text IS NULL THEN NULL ELSE now() END, :lease_epoch FROM eligible '
          'RETURNING id, created_at, task_id, parent_run_id'
          '), task_mark AS ('
          "UPDATE tasks SET status = 'running', updated_at = now() FROM inserted "
          'WHERE tasks.id = inserted.task_id AND inserted.parent_run_id IS NULL '
          'RETURNING tasks.id'
          ') SELECT id, created_at FROM inserted',
          params,
        ),
      );
      if (result.rows.isEmpty) {
        throw ValidatedFieldFlowFailure(
          errorMessage: 'This task already has an active process execution.',
          stackTrace: StackTrace.current,
          fields: const [
            FieldSystemFailure(
              field: 'taskId',
              message: 'A task can only own one active root execution',
            ),
          ],
        );
      }
      final row = result.rows.first;
      return run.copyWith(
        id: IdVO(row['id']!.toText()!),
        createdAt: row['created_at']?.toDateTime(),
      );
    } on DatabaseFailure catch (error) {
      throw DatasourceFlowFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  @override
  Future<FlowRunBundle> getRun(IdVO id) async {
    try {
      final runResult = await _database.select(
        SqlStatement(
          'SELECT $_runColumns FROM flow_runs WHERE id = :id::uuid',
          {'id': id.value},
        ),
      );
      if (runResult.rows.isEmpty) {
        throw FlowNotFoundFailure(stackTrace: StackTrace.current);
      }
      final run = DatabaseFlowRunMapper.fromRow(runResult.rows.first);

      final stepResult = await _database.select(
        SqlStatement(
          'SELECT $_runStepColumns FROM flow_run_steps WHERE run_id = :id::uuid '
          'ORDER BY started_at, iteration',
          {'id': id.value},
        ),
      );
      final steps = stepResult.rows
          .map(DatabaseFlowRunStepMapper.fromRow)
          .toList();

      final ctxResult = await _database.select(
        SqlStatement(
          'SELECT $_contextColumns FROM flow_run_context WHERE run_id = :id::uuid ORDER BY key',
          {'id': id.value},
        ),
      );
      final context = ctxResult.rows
          .map(DatabaseFlowRunContextMapper.fromRow)
          .toList();

      final artResult = await _database.select(
        SqlStatement(
          'SELECT $_artifactColumns FROM flow_artifacts WHERE run_id = :id::uuid '
          'ORDER BY created_at',
          {'id': id.value},
        ),
      );
      final artifacts = artResult.rows
          .map(DatabaseFlowArtifactMapper.fromRow)
          .toList();

      final evResult = await _database.select(
        SqlStatement(
          'SELECT $_eventColumns FROM flow_run_events WHERE run_id = :id::uuid '
          'ORDER BY created_at DESC LIMIT 100',
          {'id': id.value},
        ),
      );
      final events = evResult.rows
          .map(DatabaseFlowRunEventMapper.fromRow)
          .toList();

      return FlowRunBundle(
        run: run,
        steps: steps,
        context: context,
        artifacts: artifacts,
        events: events,
      );
    } on DatabaseFailure catch (error) {
      throw DatasourceFlowFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  @override
  Future<List<FlowRunEntity>> listRuns({
    IdVO? projectId,
    String? status,
    int? limit,
  }) async {
    try {
      final params = <String, Object?>{'lim': limit ?? 50};
      final where = <String>[];
      if (projectId != null) {
        where.add('project_id = :pid::uuid');
        params['pid'] = projectId.value;
      }
      if (status != null && status.isNotEmpty) {
        where.add('status = :status');
        params['status'] = status;
      }
      final clause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')} ';
      final result = await _database.select(
        SqlStatement(
          'SELECT $_runColumns FROM flow_runs $clause ORDER BY created_at DESC LIMIT :lim',
          params,
        ),
      );
      return result.rows.map(DatabaseFlowRunMapper.fromRow).toList();
    } on DatabaseFailure catch (error) {
      throw DatasourceFlowFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  @override
  Future<FlowRunEntity?> claimRun(String workerId) async {
    try {
      // Atomic claim: pick the oldest queued run with FOR UPDATE SKIP LOCKED so
      // two workers never grab the same run, then mark it running + stamp lease.
      // ORPHAN RECOVERY: a 'running' run whose heartbeat went stale (>5 min —
      // the worker beats every 60s even while an agent works) lost its worker
      // (crash, Studio closed); it is reclaimable and resumes from
      // current_step_id instead of staying stuck forever.
      final result = await _database.executeUpdate(
        SqlStatement(
          'UPDATE flow_runs SET status = :running, claimed_by = :w, heartbeat_at = now(), '
          'lease_epoch = lease_epoch + 1, ended_at = NULL, error = NULL, '
          'started_at = COALESCE(started_at, now()) '
          'WHERE id = ('
          "  SELECT id FROM flow_runs WHERE parent_run_id IS NULL AND (status = 'queued' "
          "  OR (status = 'running' AND heartbeat_at IS NOT NULL "
          "      AND heartbeat_at < now() - interval '5 minutes') "
          '  ) '
          '  ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED'
          ') '
          'RETURNING $_runColumns',
          {'running': FlowRunStatus.running.code, 'w': workerId},
        ),
      );
      if (result.rows.isEmpty) return null;
      final claimedId = result.rows.first['id']!.toText()!;
      await _database.executeUpdate(
        SqlStatement(
          "UPDATE flow_run_steps SET status = 'abandoned', ended_at = now() "
          "WHERE run_id = :id::uuid AND status IN ('running', 'verifying')",
          {'id': claimedId},
        ),
      );
      return DatabaseFlowRunMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceFlowFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  @override
  Future<bool> heartbeatRun(IdVO id, String workerId, int leaseEpoch) async {
    try {
      final result = await _database.executeUpdate(
        SqlStatement(
          'UPDATE flow_runs SET heartbeat_at = now() '
          "WHERE id = :id::uuid AND claimed_by = :w AND lease_epoch = :epoch "
          "AND status = 'running' RETURNING id",
          {'id': id.value, 'w': workerId, 'epoch': leaseEpoch},
        ),
      );
      return result.rows.isNotEmpty;
    } on DatabaseFailure catch (error) {
      throw DatasourceFlowFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  @override
  Future<FlowRunEntity?> claimChildRun(IdVO id, String workerId) async {
    try {
      final result = await _database.executeUpdate(
        SqlStatement(
          'UPDATE flow_runs SET status = :running, claimed_by = :worker, '
          'heartbeat_at = now(), lease_epoch = lease_epoch + 1, ended_at = NULL '
          'WHERE id = :id::uuid AND parent_run_id IS NOT NULL '
          "AND status IN ('queued', 'running', 'paused', 'awaiting_human', 'stalled') "
          'RETURNING $_runColumns',
          {
            'id': id.value,
            'worker': workerId,
            'running': FlowRunStatus.running.code,
          },
        ),
      );
      if (result.rows.isNotEmpty) {
        await _database.executeUpdate(
          SqlStatement(
            "UPDATE flow_run_steps SET status = 'abandoned', ended_at = now() "
            "WHERE run_id = :id::uuid AND status IN ('running', 'verifying')",
            {'id': id.value},
          ),
        );
      }
      return result.rows.isEmpty
          ? null
          : DatabaseFlowRunMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceFlowFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  @override
  Future<bool> checkpointRun(
    IdVO id,
    String workerId,
    int leaseEpoch, {
    String? executionState,
    IdVO? currentStepId,
    bool clearCurrentStep = false,
    String? branchName,
    String? worktreePath,
    int addTokens = 0,
  }) async {
    try {
      final sets = <String>['heartbeat_at = now()'];
      final params = <String, Object?>{
        'id': id.value,
        'w': workerId,
        'epoch': leaseEpoch,
      };
      if (executionState != null) {
        sets.add('execution_state = :state::jsonb');
        params['state'] = executionState;
      }
      if (clearCurrentStep) {
        sets.add('current_step_id = NULL');
      } else if (currentStepId != null) {
        sets.add('current_step_id = :step::uuid');
        params['step'] = currentStepId.value;
      }
      if (branchName != null) {
        sets.add('branch_name = :branch');
        params['branch'] = branchName;
      }
      if (worktreePath != null) {
        sets.add('worktree_path = :worktree');
        params['worktree'] = worktreePath;
      }
      if (addTokens != 0) {
        sets.add('tokens_used = tokens_used + :tokens');
        params['tokens'] = addTokens;
      }
      final result = await _database.executeUpdate(
        SqlStatement(
          'UPDATE flow_runs SET ${sets.join(', ')} '
          'WHERE id = :id::uuid AND claimed_by = :w AND lease_epoch = :epoch '
          "AND status = 'running' RETURNING id",
          params,
        ),
      );
      return result.rows.isNotEmpty;
    } on DatabaseFailure catch (error) {
      throw DatasourceFlowFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  @override
  Future<FlowRunEntity> updateRunStatus(
    IdVO id,
    FlowRunStatus status, {
    IdVO? currentStepId,
    String? error,
    String? branchName,
    String? worktreePath,
    int addTokens = 0,
    String? expectedWorkerId,
    int? expectedLeaseEpoch,
    Set<FlowRunStatus>? expectedStatuses,
  }) async {
    try {
      final sets = <String>['status = :status'];
      final params = <String, Object?>{'id': id.value, 'status': status.code};
      if (currentStepId != null) {
        sets.add('current_step_id = :csid::uuid');
        params['csid'] = currentStepId.value;
      }
      if (error != null) {
        sets.add('error = :error');
        params['error'] = error;
      }
      if (branchName != null) {
        sets.add('branch_name = :branch');
        params['branch'] = branchName;
      }
      if (worktreePath != null) {
        sets.add('worktree_path = :wt');
        params['wt'] = worktreePath;
      }
      if (addTokens != 0) {
        sets.add('tokens_used = tokens_used + :addt');
        params['addt'] = addTokens;
      }
      if (status == FlowRunStatus.running) {
        sets.add('started_at = COALESCE(started_at, now())');
      } else {
        sets.add('claimed_by = NULL');
        sets.add('heartbeat_at = NULL');
      }
      if (status == FlowRunStatus.queued) sets.add('ended_at = NULL');
      if (status.isTerminal || status == FlowRunStatus.stalled) {
        sets.add('ended_at = now()');
      }
      final where = <String>['id = :id::uuid'];
      if (expectedWorkerId != null) {
        where.add('claimed_by = :expected_worker');
        params['expected_worker'] = expectedWorkerId;
      }
      if (expectedLeaseEpoch != null) {
        where.add('lease_epoch = :expected_epoch');
        params['expected_epoch'] = expectedLeaseEpoch;
      }
      if (expectedStatuses != null && expectedStatuses.isNotEmpty) {
        final statusParams = <String>[];
        var index = 0;
        for (final expected in expectedStatuses) {
          final key = 'expected_status_${index++}';
          params[key] = expected.code;
          statusParams.add(':$key');
        }
        where.add('status IN (${statusParams.join(', ')})');
      }
      final result = await _database.executeUpdate(
        SqlStatement(
          'UPDATE flow_runs SET ${sets.join(', ')} WHERE ${where.join(' AND ')} '
          'RETURNING $_runColumns',
          params,
        ),
      );
      if (result.rows.isEmpty) {
        throw FlowNotFoundFailure(stackTrace: StackTrace.current);
      }
      return DatabaseFlowRunMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (dbError) {
      throw DatasourceFlowFailure(
        errorMessage: dbError.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  // ── run steps ─────────────────────────────────────────────────────────

  @override
  Future<FlowRunStepEntity> startRunStep(FlowRunStepEntity runStep) async {
    try {
      final result = await _database.executeUpdate(
        SqlStatement(
          'INSERT INTO flow_run_steps '
          '(run_id, step_id, iteration, status, agent, session_id, agent_session_id, claim_token, '
          'rendered_prompt, report, verifier, tokens_used) '
          'VALUES (:run_id::uuid, :step_id::uuid, :iteration, :status, :agent, :session_id::uuid, '
          ':agent_session_id, :claim_token, :rendered_prompt, :report::jsonb, :verifier::jsonb, :tokens_used) '
          'RETURNING id, started_at',
          DatabaseFlowRunStepMapper.toInsertParams(runStep),
        ),
      );
      final row = result.rows.first;
      return runStep.copyWith(
        id: IdVO(row['id']!.toText()!),
        startedAt: row['started_at']?.toDateTime(),
      );
    } on DatabaseFailure catch (error) {
      throw DatasourceFlowFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  @override
  Future<FlowRunStepEntity> updateRunStep(FlowRunStepEntity runStep) async {
    try {
      // A step iteration that reached a resolved status stamps ended_at (computed
      // in Dart so the :status param isn't referenced twice — some drivers reject
      // a reused named param).
      const resolved = {
        FlowRunStepStatus.passed,
        FlowRunStepStatus.failed,
        FlowRunStepStatus.skipped,
        FlowRunStepStatus.parked,
      };
      final endedClause = resolved.contains(runStep.status)
          ? ', ended_at = now()'
          : '';
      final result = await _database.executeUpdate(
        SqlStatement(
          'UPDATE flow_run_steps SET status = :status, agent = :agent, '
          'session_id = :session_id::uuid, agent_session_id = :agent_session_id, '
          'claim_token = :claim_token, '
          'rendered_prompt = :rendered_prompt, report = :report::jsonb, '
          'verifier = :verifier::jsonb, tokens_used = :tokens_used$endedClause '
          'WHERE id = :id::uuid RETURNING $_runStepColumns',
          {
            'id': runStep.id.value,
            'status': runStep.status.code,
            'agent': runStep.agent,
            'session_id': runStep.sessionId?.value,
            'agent_session_id': runStep.agentSessionId,
            'claim_token': runStep.claimToken,
            'rendered_prompt': runStep.renderedPrompt,
            'report': runStep.report,
            'verifier': runStep.verifier,
            'tokens_used': runStep.tokensUsed,
          },
        ),
      );
      if (result.rows.isEmpty) {
        throw FlowNotFoundFailure(stackTrace: StackTrace.current);
      }
      return DatabaseFlowRunStepMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceFlowFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  @override
  Future<FlowRunStepEntity> getRunStep(IdVO id) async {
    try {
      final result = await _database.select(
        SqlStatement(
          'SELECT $_runStepColumns FROM flow_run_steps WHERE id = :id::uuid',
          {'id': id.value},
        ),
      );
      if (result.rows.isEmpty) {
        throw FlowNotFoundFailure(stackTrace: StackTrace.current);
      }
      return DatabaseFlowRunStepMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceFlowFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  @override
  Future<StepContext> stepContext(IdVO runStepId) async {
    try {
      final runStep = await getRunStep(runStepId);

      final runResult = await _database.select(
        SqlStatement(
          'SELECT $_runColumns FROM flow_runs WHERE id = :id::uuid',
          {'id': runStep.runId.value},
        ),
      );
      if (runResult.rows.isEmpty) {
        throw FlowNotFoundFailure(stackTrace: StackTrace.current);
      }
      final run = DatabaseFlowRunMapper.fromRow(runResult.rows.first);

      final stepResult = await _database.select(
        SqlStatement(
          'SELECT $_stepColumns FROM flow_steps WHERE id = :id::uuid',
          {'id': runStep.stepId.value},
        ),
      );
      if (stepResult.rows.isEmpty) {
        throw FlowNotFoundFailure(stackTrace: StackTrace.current);
      }
      final step = DatabaseFlowStepMapper.fromRow(stepResult.rows.first);

      TaskEntity? task;
      if (run.taskId != null) {
        final taskResult = await _database.select(
          SqlStatement('SELECT $_taskColumns FROM tasks WHERE id = :id::uuid', {
            'id': run.taskId!.value,
          }),
        );
        if (taskResult.rows.isNotEmpty) {
          task = DatabaseTaskMapper.fromRow(taskResult.rows.first);
        }
      }

      final ctxResult = await _database.select(
        SqlStatement(
          'SELECT $_contextColumns FROM flow_run_context WHERE run_id = :id::uuid ORDER BY key',
          {'id': runStep.runId.value},
        ),
      );
      final context = ctxResult.rows
          .map(DatabaseFlowRunContextMapper.fromRow)
          .toList();

      final priorResult = await _database.select(
        SqlStatement(
          'SELECT $_runStepColumns FROM flow_run_steps '
          'WHERE run_id = :id::uuid AND report IS NOT NULL AND id <> :self::uuid '
          'ORDER BY started_at',
          {'id': runStep.runId.value, 'self': runStepId.value},
        ),
      );
      final priorReports = priorResult.rows
          .map(DatabaseFlowRunStepMapper.fromRow)
          .toList();

      final artResult = await _database.select(
        SqlStatement(
          'SELECT $_artifactColumns FROM flow_artifacts WHERE run_id = :id::uuid ORDER BY created_at',
          {'id': runStep.runId.value},
        ),
      );
      final artifacts = artResult.rows
          .map(DatabaseFlowArtifactMapper.fromRow)
          .toList();

      return StepContext(
        runStep: runStep,
        run: run,
        step: step,
        task: task,
        context: context,
        priorReports: priorReports,
        artifacts: artifacts,
      );
    } on DatabaseFailure catch (error) {
      throw DatasourceFlowFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  @override
  Future<IdVO?> resolveSessionId({
    IdVO? projectId,
    required String externalId,
  }) async {
    try {
      final params = <String, Object?>{'e': externalId};
      final where = <String>['external_id = :e'];
      if (projectId != null) {
        where.add('project_id = :p::uuid');
        params['p'] = projectId.value;
      }
      final result = await _database.select(
        SqlStatement(
          'SELECT id FROM sessions WHERE ${where.join(' AND ')} '
          'ORDER BY created_at DESC LIMIT 1',
          params,
        ),
      );
      if (result.rows.isEmpty) return null;
      return IdVO(result.rows.first['id']!.toText()!);
    } on DatabaseFailure catch (error) {
      throw DatasourceFlowFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  // ── blackboard / artifacts / timeline ───────────────────────────────────

  @override
  Future<FlowRunContextEntity> putContext(FlowRunContextEntity ctx) async {
    try {
      final result = await _database.executeUpdate(
        SqlStatement(
          'INSERT INTO flow_run_context (run_id, key, value, updated_by) '
          'VALUES (:run_id::uuid, :key, :value::jsonb, :updated_by::uuid) '
          'ON CONFLICT (run_id, key) DO UPDATE SET '
          'value = EXCLUDED.value, updated_by = EXCLUDED.updated_by, updated_at = now() '
          'RETURNING $_contextColumns',
          DatabaseFlowRunContextMapper.toInsertParams(ctx),
        ),
      );
      return DatabaseFlowRunContextMapper.fromRow(result.rows.first);
    } on DatabaseFailure catch (error) {
      throw DatasourceFlowFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  @override
  Future<FlowArtifactEntity> addArtifact(FlowArtifactEntity artifact) async {
    try {
      final result = await _database.executeUpdate(
        SqlStatement(
          'INSERT INTO flow_artifacts (run_id, run_step_id, kind, locator, meta) '
          'VALUES (:run_id::uuid, :run_step_id::uuid, :kind, :locator, :meta::jsonb) '
          'RETURNING id, created_at',
          DatabaseFlowArtifactMapper.toInsertParams(artifact),
        ),
      );
      final row = result.rows.first;
      return artifact.copyWith(
        id: IdVO(row['id']!.toText()!),
        createdAt: row['created_at']?.toDateTime(),
      );
    } on DatabaseFailure catch (error) {
      throw DatasourceFlowFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }

  @override
  Future<FlowRunEventEntity> addEvent(FlowRunEventEntity event) async {
    try {
      final result = await _database.executeUpdate(
        SqlStatement(
          'INSERT INTO flow_run_events (run_id, run_step_id, kind, payload) '
          'VALUES (:run_id::uuid, :run_step_id::uuid, :kind, :payload::jsonb) '
          'RETURNING id, created_at',
          DatabaseFlowRunEventMapper.toInsertParams(event),
        ),
      );
      final row = result.rows.first;
      return event.copyWith(
        id: IdVO(row['id']!.toText()!),
        createdAt: row['created_at']?.toDateTime(),
      );
    } on DatabaseFailure catch (error) {
      throw DatasourceFlowFailure(
        errorMessage: error.errorMessage,
        stackTrace: StackTrace.current,
      );
    }
  }
}
