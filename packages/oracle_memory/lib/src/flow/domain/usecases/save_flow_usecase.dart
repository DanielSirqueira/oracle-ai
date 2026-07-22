import 'dart:convert';

import 'package:oracle_core/oracle_core.dart';

import '../dtos/flow_graph.dart';
import '../entities/flow_edge_entity.dart';
import '../entities/flow_entity.dart';
import '../entities/flow_step_entity.dart';
import '../enums/flow_step_kind.dart';
import '../errors/flow_failure.dart';
import '../repositories/flow_repository.dart';

/// Saves (defines/versions) a whole process graph. Re-saving the same key in the
/// same scope supersedes the prior latest.
///
/// Guardrails: a key, a name, a scope, at least one step, and an entry step that
/// exists among the steps are required. Edges must reference known step keys.
/// At most ONE orchestrator step is allowed — and when present it IS the entry
/// (the orchestrator starts the flow).
abstract interface class SaveFlowUsecase {
  AsyncResultDart<FlowGraph, FlowFailure> call(
    FlowEntity flow,
    List<FlowStepEntity> steps,
    List<FlowEdgeEntity> edges,
  );
}

class SaveFlowUsecaseImpl implements SaveFlowUsecase {
  final FlowRepository _repository;
  const SaveFlowUsecaseImpl(this._repository);

  @override
  AsyncResultDart<FlowGraph, FlowFailure> call(
    FlowEntity flow,
    List<FlowStepEntity> steps,
    List<FlowEdgeEntity> edges,
  ) async {
    final fields = <FieldSystemFailure>[];
    bool jsonObject(String raw, String field) {
      try {
        if (jsonDecode(raw) is Map) return true;
      } catch (_) {
        // Added below with a field-specific message.
      }
      fields.add(
        FieldSystemFailure(
          field: field,
          message: 'Must be a valid JSON object',
        ),
      );
      return false;
    }

    if (flow.key.trim().isEmpty) {
      fields.add(const FieldSystemFailure(field: 'key', message: 'Required'));
    }
    if (flow.name.isBlank) {
      fields.add(const FieldSystemFailure(field: 'name', message: 'Required'));
    }
    if (flow.organizationId == null &&
        flow.projectId == null &&
        flow.moduleId == null) {
      fields.add(
        const FieldSystemFailure(
          field: 'scope',
          message: 'Organization, project or module required',
        ),
      );
    }
    if (steps.isEmpty) {
      fields.add(
        const FieldSystemFailure(
          field: 'steps',
          message: 'At least one step required',
        ),
      );
    }
    if (jsonObject(flow.budgets, 'budgets')) {
      final budget = jsonDecode(flow.budgets) as Map;
      for (final key in const ['maxTotalTokens', 'maxWallMinutes']) {
        final value = budget[key];
        if (value != null && (value is! num || value < 0)) {
          fields.add(
            FieldSystemFailure(
              field: 'budgets.$key',
              message: 'Must be a non-negative number',
            ),
          );
        }
      }
    }
    final stepKeys = steps.map((s) => s.stepKey).toSet();
    if (stepKeys.length != steps.length ||
        stepKeys.any((k) => k.trim().isEmpty)) {
      fields.add(
        const FieldSystemFailure(
          field: 'steps',
          message: 'Step keys must be non-empty and unique',
        ),
      );
    }
    const executableAgents = {
      'claude-code',
      'claude',
      'codex',
      'gemini',
      'cursor',
    };
    const agentKinds = {
      FlowStepKind.agent,
      FlowStepKind.orchestrator,
      FlowStepKind.decision,
      FlowStepKind.rfcCreate,
      FlowStepKind.rfcReview,
      FlowStepKind.rfcConsolidate,
    };
    for (final step in steps) {
      jsonObject(step.config, 'steps.${step.stepKey}.config');
      jsonObject(step.permissions, 'steps.${step.stepKey}.permissions');
      jsonObject(step.exitCriteria, 'steps.${step.stepKey}.exitCriteria');
      if (step.outputSchema != null && step.outputSchema!.trim().isNotEmpty) {
        jsonObject(step.outputSchema!, 'steps.${step.stepKey}.outputSchema');
      }
      if (step.tokenBudget != null && step.tokenBudget! < 0) {
        fields.add(
          FieldSystemFailure(
            field: 'steps.${step.stepKey}.tokenBudget',
            message: 'Cannot be negative',
          ),
        );
      }
      try {
        final permissions = jsonDecode(step.permissions);
        if (permissions is Map) {
          final workspace = permissions['workspace'];
          if (workspace != null &&
              workspace != 'read' &&
              workspace != 'write') {
            fields.add(
              FieldSystemFailure(
                field: 'steps.${step.stepKey}.permissions.workspace',
                message: 'Must be read or write',
              ),
            );
          }
          for (final key in const ['shell', 'mcp']) {
            if (permissions[key] != null && permissions[key] is! bool) {
              fields.add(
                FieldSystemFailure(
                  field: 'steps.${step.stepKey}.permissions.$key',
                  message: 'Must be boolean',
                ),
              );
            }
          }
          if (agentKinds.contains(step.kind) && permissions['mcp'] == false) {
            fields.add(
              FieldSystemFailure(
                field: 'steps.${step.stepKey}.permissions.mcp',
                message: 'Agent steps require MCP for context and reporting',
              ),
            );
          }
        }
      } catch (_) {
        // The generic JSON validation above already reports this.
      }
      if (!const {'continue', 'park', 'halt'}.contains(step.onFail)) {
        fields.add(
          FieldSystemFailure(
            field: 'steps.${step.stepKey}.onFail',
            message: 'Must be continue, park or halt',
          ),
        );
      }
      if (agentKinds.contains(step.kind)) {
        if (!executableAgents.contains(step.agent?.trim())) {
          fields.add(
            FieldSystemFailure(
              field: 'steps.${step.stepKey}.agent',
              message: 'Agent has no supported headless process adapter',
            ),
          );
        }
        if (step.maxIterations < 1) {
          fields.add(
            FieldSystemFailure(
              field: 'steps.${step.stepKey}.maxIterations',
              message: 'Must be at least 1',
            ),
          );
        }
      }
      if (step.timeoutMinutes < 0) {
        fields.add(
          FieldSystemFailure(
            field: 'steps.${step.stepKey}.timeoutMinutes',
            message: 'Cannot be negative',
          ),
        );
      }
      if (step.kind == FlowStepKind.command &&
          (step.command == null || step.command!.trim().isEmpty)) {
        fields.add(
          FieldSystemFailure(
            field: 'steps.${step.stepKey}.command',
            message: 'Command step requires a command',
          ),
        );
      }
      if (step.kind == FlowStepKind.subflow) {
        String flowKey = '';
        try {
          final config = jsonDecode(step.config);
          if (config is Map) flowKey = '${config['flowKey'] ?? ''}'.trim();
        } catch (_) {
          /* invalid config is handled as a missing target */
        }
        if (flowKey.isEmpty) {
          fields.add(
            FieldSystemFailure(
              field: 'steps.${step.stepKey}.flowKey',
              message: 'Sub-process step requires a target process',
            ),
          );
        }
      }
    }
    final orchestrators = steps
        .where((s) => s.kind == FlowStepKind.orchestrator)
        .toList();
    if (orchestrators.length > 1) {
      fields.add(
        const FieldSystemFailure(
          field: 'steps',
          message: 'Only ONE orchestrator step is allowed (it starts the flow)',
        ),
      );
    }
    // The orchestrator, when present, IS the entry.
    final entry = orchestrators.length == 1
        ? orchestrators.first.stepKey
        : (flow.entryStepKey.isEmpty
              ? (steps.isEmpty ? '' : steps.first.stepKey)
              : flow.entryStepKey);
    if (steps.isNotEmpty && !stepKeys.contains(entry)) {
      fields.add(
        const FieldSystemFailure(
          field: 'entryStepKey',
          message: 'Entry step must be one of the steps',
        ),
      );
    }
    for (final e in edges) {
      if (!const {
        'success',
        'failure',
        'always',
        'verdict',
      }.contains(e.condition)) {
        fields.add(
          const FieldSystemFailure(
            field: 'edges.condition',
            message: 'Must be success, failure, always or verdict',
          ),
        );
      }
      if (!stepKeys.contains(e.fromStep.value) ||
          !stepKeys.contains(e.toStep.value)) {
        fields.add(
          const FieldSystemFailure(
            field: 'edges',
            message: 'Edge references an unknown step key',
          ),
        );
        break;
      }
      if (e.fromStep.value == e.toStep.value) {
        fields.add(
          const FieldSystemFailure(
            field: 'edges',
            message: 'A step cannot connect to itself',
          ),
        );
      }
    }
    final edgeKeys = edges
        .map(
          (edge) =>
              '${edge.fromStep.value}|${edge.toStep.value}|${edge.condition}|${edge.verdictValue ?? ''}',
        )
        .toList();
    if (edgeKeys.toSet().length != edgeKeys.length) {
      fields.add(
        const FieldSystemFailure(
          field: 'edges',
          message: 'Duplicate connections are not allowed',
        ),
      );
    }
    for (final step in steps) {
      final incoming = edges
          .where((e) => e.toStep.value == step.stepKey)
          .map((e) => e.fromStep.value)
          .toSet();
      final outgoing = edges
          .where((e) => e.fromStep.value == step.stepKey)
          .toList();
      if (step.kind == FlowStepKind.join) {
        if (incoming.length < 2) {
          fields.add(
            FieldSystemFailure(
              field: 'steps.${step.stepKey}.incoming',
              message: 'Join requires at least two incoming branches',
            ),
          );
        }
      }
      final verdicts = outgoing.where((e) => e.condition == 'verdict').toList();
      if (step.kind == FlowStepKind.decision && verdicts.length < 2) {
        fields.add(
          FieldSystemFailure(
            field: 'steps.${step.stepKey}.verdicts',
            message: 'Decision requires at least two verdict connections',
          ),
        );
      }
      final verdictValues = verdicts
          .map((e) => e.verdictValue?.trim() ?? '')
          .where((v) => v.isNotEmpty)
          .toList();
      if (verdictValues.length != verdicts.length ||
          verdictValues.toSet().length != verdictValues.length) {
        fields.add(
          FieldSystemFailure(
            field: 'steps.${step.stepKey}.verdicts',
            message: 'Verdict values must be non-empty and unique per step',
          ),
        );
      }
    }
    if (entry.isNotEmpty && stepKeys.contains(entry)) {
      final reachable = <String>{entry};
      final pending = <String>[entry];
      while (pending.isNotEmpty) {
        final from = pending.removeLast();
        for (final edge in edges.where((e) => e.fromStep.value == from)) {
          final target = edge.toStep.value;
          if (reachable.add(target)) pending.add(target);
        }
      }
      final unreachable = stepKeys.difference(reachable);
      if (unreachable.isNotEmpty) {
        fields.add(
          FieldSystemFailure(
            field: 'steps',
            message: 'Unreachable from entry: ${unreachable.join(', ')}',
          ),
        );
      }
    }
    if (fields.isNotEmpty) {
      return Failure(
        ValidatedFieldFlowFailure(
          errorMessage: 'Invalid flow',
          stackTrace: StackTrace.current,
          fields: fields,
        ),
      );
    }

    return _repository.saveFlow(
      flow.copyWith(entryStepKey: entry),
      steps,
      edges,
    );
  }
}
