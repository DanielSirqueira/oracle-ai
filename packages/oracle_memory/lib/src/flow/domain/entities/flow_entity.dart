import 'package:oracle_core/oracle_core.dart';

/// The definition of a process (the "n8n workflow"). A versioned graph of steps
/// (loops) and edges, owned by exactly one scope level (organization / project /
/// module), like rules/skills — re-saving the same [key] supersedes (is_latest /
/// supersedes). [orchestratorAgent] is the agent that decides at judgment nodes;
/// [entryStepKey] is the graph's start node; [budgets] (raw JSON) carries default
/// run limits (maxTotalTokens, maxWallMinutes…).
class FlowEntity {
  final IdVO id;
  final IdVO? organizationId;
  final IdVO? projectId;
  final IdVO? moduleId;
  final String key;
  final TextVO name;
  final String description;
  final String orchestratorAgent;
  final String entryStepKey;
  final String budgets;
  final int versionNo;
  final bool isLatest;
  final IdVO? supersedes;
  final DateTime? retiredAt;
  final String? retiredReason;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FlowEntity({
    required this.id,
    this.organizationId,
    this.projectId,
    this.moduleId,
    required this.key,
    required this.name,
    this.description = '',
    this.orchestratorAgent = 'claude-code',
    this.entryStepKey = '',
    this.budgets = '{}',
    this.versionNo = 1,
    this.isLatest = true,
    this.supersedes,
    this.retiredAt,
    this.retiredReason,
    this.createdAt,
    this.updatedAt,
  });

  factory FlowEntity.empty() =>
      const FlowEntity(id: IdVO.empty(), key: '', name: TextVO.empty());

  FlowEntity copyWith({
    IdVO? id,
    IdVO? organizationId,
    IdVO? projectId,
    IdVO? moduleId,
    String? key,
    TextVO? name,
    String? description,
    String? orchestratorAgent,
    String? entryStepKey,
    String? budgets,
    int? versionNo,
    bool? isLatest,
    IdVO? supersedes,
    DateTime? retiredAt,
    String? retiredReason,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FlowEntity(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      projectId: projectId ?? this.projectId,
      moduleId: moduleId ?? this.moduleId,
      key: key ?? this.key,
      name: name ?? this.name,
      description: description ?? this.description,
      orchestratorAgent: orchestratorAgent ?? this.orchestratorAgent,
      entryStepKey: entryStepKey ?? this.entryStepKey,
      budgets: budgets ?? this.budgets,
      versionNo: versionNo ?? this.versionNo,
      isLatest: isLatest ?? this.isLatest,
      supersedes: supersedes ?? this.supersedes,
      retiredAt: retiredAt ?? this.retiredAt,
      retiredReason: retiredReason ?? this.retiredReason,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FlowEntity &&
        other.id == id &&
        other.organizationId == organizationId &&
        other.projectId == projectId &&
        other.moduleId == moduleId &&
        other.key == key &&
        other.name == name &&
        other.description == description &&
        other.orchestratorAgent == orchestratorAgent &&
        other.entryStepKey == entryStepKey &&
        other.budgets == budgets &&
        other.versionNo == versionNo &&
        other.isLatest == isLatest &&
        other.supersedes == supersedes;
  }

  @override
  int get hashCode => Object.hash(
    id,
    organizationId,
    projectId,
    moduleId,
    key,
    name,
    description,
    orchestratorAgent,
    entryStepKey,
    versionNo,
    isLatest,
    supersedes,
  );
}
