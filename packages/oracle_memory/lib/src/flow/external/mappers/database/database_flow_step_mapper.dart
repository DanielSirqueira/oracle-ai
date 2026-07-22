import 'package:oracle_core/oracle_core.dart';

import '../../../domain/entities/flow_step_entity.dart';
import '../../../domain/enums/flow_step_kind.dart';

/// Maps [FlowStepEntity] to/from the `flow_steps` table.
class DatabaseFlowStepMapper {
  const DatabaseFlowStepMapper._();

  static Map<String, Object?> toInsertParams(FlowStepEntity s) => {
    'flow_id': s.flowId.value,
    'step_key': s.stepKey,
    'name': s.name,
    'kind': s.kind.code,
    'agent': s.agent,
    'model': s.model,
    'role': s.role,
    'prompt_template': s.promptTemplate,
    'command': s.command,
    'output_schema': s.outputSchema,
    'permissions': s.permissions,
    'exit_criteria': s.exitCriteria,
    'max_iterations': s.maxIterations,
    'token_budget': s.tokenBudget,
    'timeout_minutes': s.timeoutMinutes,
    'on_fail': s.onFail,
    'config': s.config,
    'position': s.position,
  };

  static FlowStepEntity fromRow(Map<String, DataRowType> row) {
    return FlowStepEntity(
      id: IdVO(row['id']!.toText()!),
      flowId: IdVO(row['flow_id']!.toText()!),
      stepKey: row['step_key']?.toText() ?? '',
      name: row['name']?.toText() ?? '',
      kind: FlowStepKind.parse(row['kind']?.toText() ?? 'agent'),
      agent: row['agent']?.toText(),
      model: row['model']?.toText(),
      role: row['role']?.toText(),
      promptTemplate: row['prompt_template']?.toText() ?? '',
      command: row['command']?.toText(),
      outputSchema: row['output_schema']?.toText(),
      permissions: row['permissions']?.toText() ?? '{}',
      exitCriteria: row['exit_criteria']?.toText() ?? '{}',
      maxIterations: row['max_iterations']?.toInt() ?? 3,
      tokenBudget: row['token_budget']?.toInt(),
      timeoutMinutes: row['timeout_minutes']?.toInt() ?? 30,
      onFail: row['on_fail']?.toText() ?? 'park',
      config: row['config']?.toText() ?? '{}',
      position: row['position']?.toInt() ?? 0,
      createdAt: row['created_at']?.toDateTime(),
    );
  }
}
