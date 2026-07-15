import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';

import '../../core/brand.dart';
import '../../core/fmt.dart';
import '../../core/l10n.dart';
import '../../widgets/async_view.dart';
import '../../widgets/editor_dialog.dart';
import '../../widgets/markdown_view.dart';

/// Browse and finalize the RFCs (technical specs published for multi-agent
/// review) in scope for the selected project. Opening seeds a canonical
/// checklist; the readiness gate (verified criticals + required coverage) is
/// what "Finalizar" enforces, and "Copiar prompt de revisão" hands the review
/// off to another agent (no process spawning).
class RfcsPage extends StatefulWidget {
  final ValueNotifier<ProjectEntity?> project;
  const RfcsPage({super.key, required this.project});

  @override
  State<RfcsPage> createState() => _RfcsPageState();
}

/// Client-side view filter over the loaded RFC list.
enum _RfcFilter { all, open, approved }

class _RfcsPageState extends State<RfcsPage> {
  RfcEntity? _selected;
  Future<List<RfcEntity>>? _future;
  _RfcFilter _filter = _RfcFilter.all;

  @override
  void initState() {
    super.initState();
    widget.project.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.project.removeListener(_reload);
    super.dispose();
  }

  void _reload({RfcEntity? select}) {
    final project = widget.project.value;
    if (project == null) return;
    setState(() {
      _selected = select;
      _future = injector
          .get<ListRfcsUsecase>()(
            organizationId: project.organizationId,
            projectId: project.id,
            limit: 100,
          )
          .then((r) => r.getOrThrow());
    });
  }

  bool _matchesFilter(RfcEntity rfc) {
    switch (_filter) {
      case _RfcFilter.all:
        return true;
      case _RfcFilter.approved:
        return rfc.status == RfcStatus.approved;
      case _RfcFilter.open:
        return const {
          RfcStatus.draft,
          RfcStatus.openForComments,
          RfcStatus.inReview,
          RfcStatus.inConsolidation,
          RfcStatus.awaitingHuman,
          RfcStatus.stalled,
        }.contains(rfc.status);
    }
  }

  Future<void> _createRfc() async {
    final project = widget.project.value;
    if (project == null) return;
    final title = TextEditingController();
    final rfcType = TextEditingController(text: 'generic');
    final summary = TextEditingController();

    final saved = await showEditorDialog(
      context,
      title: l10n.t('rfc.newTitle'),
      fields: (context, setState) => [
        FieldRow(l10n.t('rfc.fieldTitle'), title, description: l10n.t('rfc.fieldTitleDesc')),
        FieldRow(l10n.t('rfc.fieldType'), rfcType, description: l10n.t('rfc.fieldTypeDesc')),
        FieldRow(l10n.t('rfc.fieldSummary'), summary,
            maxLines: 8, description: l10n.t('rfc.fieldSummaryDesc')),
      ],
      onSave: () async {
        if (title.text.trim().isEmpty) return l10n.t('rfc.titleRequired');
        final rfc = RfcEntity(
          id: const IdVO.empty(),
          organizationId: project.organizationId,
          projectId: project.id,
          title: TextVO(title.text.trim()),
          rfcType: rfcType.text.trim().isEmpty ? 'generic' : rfcType.text.trim(),
          authorAgent: 'oracle-studio',
        );
        final version = RfcVersionEntity(
          id: const IdVO.empty(),
          rfcId: const IdVO.empty(),
          versionNo: 1,
          summary: TextVO(summary.text.trim()),
        );
        // Seed the canonical checklist as required + missing so the readiness
        // gate is meaningful from the first round.
        final sections = <RfcSectionEntity>[
          for (final key in const [
            'context',
            'problem',
            'business_rules',
            'data_model',
            'acceptance_criteria',
          ])
            RfcSectionEntity(
              id: const IdVO.empty(),
              versionId: const IdVO.empty(),
              sectionKey: key,
              content: const TextVO.empty(),
              required: true,
              coverage: 'missing',
            ),
        ];
        final result = await injector.get<OpenRfcUsecase>()(rfc, version, sections);
        return result.fold((created) {
          _created = created;
          return null;
        }, (f) => f.errorMessage);
      },
    );
    if (saved == true && mounted) {
      showSnack(context, l10n.t('rfc.created'));
      _reload(select: _created);
      _created = null;
    }
  }

  // Carries the RFC returned by OpenRfcUsecase out of the dialog's onSave so we
  // can select it after the reload.
  RfcEntity? _created;

  Future<void> _finalize(RfcEntity rfc) async {
    final ok = await confirmAction(
      context,
      title: l10n.t('rfc.finalizeQ'),
      message: '"${rfc.title.value}" ${l10n.t('rfc.finalizeMsg')}',
      okLabel: l10n.t('rfc.finalize'),
    );
    if (!ok) return;
    final result = await injector.get<FinalizeRfcUsecase>()(rfc.id);
    if (!mounted) return;
    result.fold(
      (updated) {
        showSnack(context, '${l10n.t('rfc.finalized')} ${_statusLabel(updated.status)}.');
        _reload();
      },
      (f) {
        final blockers = f.fields.map((e) => e.message).join(' · ');
        showSnack(context, blockers.isEmpty
            ? '${l10n.t('common.failure')}: ${f.errorMessage}'
            : '${f.errorMessage}: $blockers');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_future == null) return Center(child: Text(l10n.t('common.selectProject')));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Text(l10n.t('rfc.header'), style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              FilledButton.icon(
                onPressed: _createRfc,
                icon: const Icon(Icons.add),
                label: Text(l10n.t('rfc.new')),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: [
            for (final f in _RfcFilter.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(_filterLabel(f)),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
              ),
          ]),
        ),
        Expanded(
          child: AsyncView<List<RfcEntity>>(
            future: _future!,
            builder: (context, rfcs) {
              final filtered = rfcs.where(_matchesFilter).toList();
              if (filtered.isEmpty) {
                return Center(child: Text(l10n.t('rfc.empty')));
              }
              return MasterDetail(
                master: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final r = filtered[i];
                    return ListTile(
                      selected: _selected?.id.value == r.id.value,
                      leading: const Icon(Icons.reviews_outlined, size: 20),
                      title: Text(r.title.value, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${r.rfcType} · ${fmtDateTime(r.updatedAt ?? r.createdAt)}',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: StatusBadge(_statusLabel(r.status), color: _statusColor(r.status)),
                      onTap: () => setState(() => _selected = r),
                    );
                  },
                ),
                detail: _selected == null
                    ? Center(child: Text(l10n.t('rfc.selectOne')))
                    : _RfcDetail(
                        key: ValueKey(_selected!.id.value),
                        rfc: _selected!,
                        onFinalize: () => _finalize(_selected!),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _filterLabel(_RfcFilter f) {
    switch (f) {
      case _RfcFilter.all:
        return l10n.t('rfc.filterAll');
      case _RfcFilter.open:
        return l10n.t('rfc.filterOpen');
      case _RfcFilter.approved:
        return l10n.t('rfc.filterApproved');
    }
  }
}

/// RFC detail: fetches the bundle + status report, then renders the readiness
/// gate, version summary, sections and structured findings, with the finalize
/// and review-handoff actions.
class _RfcDetail extends StatefulWidget {
  final RfcEntity rfc;
  final VoidCallback onFinalize;
  const _RfcDetail({super.key, required this.rfc, required this.onFinalize});

  @override
  State<_RfcDetail> createState() => _RfcDetailState();
}

class _RfcDetailState extends State<_RfcDetail> {
  late Future<(RfcBundle, RfcStatusReport)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(RfcBundle, RfcStatusReport)> _load() async {
    final bundle = await injector.get<GetRfcUsecase>()(widget.rfc.id).then((r) => r.getOrThrow());
    final status =
        await injector.get<RfcStatusUsecase>()(widget.rfc.id).then((r) => r.getOrThrow());
    return (bundle, status);
  }

  void _copyPrompt(RfcEntity rfc, RfcStatusReport status) {
    Clipboard.setData(ClipboardData(text: buildReviewPrompt(rfc, status)));
    showSnack(context, l10n.t('rfc.promptCopied'));
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<(RfcBundle, RfcStatusReport)>(
      future: _future,
      builder: (context, data) {
        final (bundle, status) = data;
        final rfc = bundle.rfc;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child: Text(rfc.title.value,
                        style: Theme.of(context).textTheme.titleLarge)),
                StatusBadge(_statusLabel(rfc.status), color: _statusColor(rfc.status)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              MetaChip(rfc.rfcType, icon: Icons.category_outlined),
              MetaChip('${l10n.t('rfc.round')} ${rfc.roundCount}', icon: Icons.loop),
              MetaChip(rfc.authorAgent, icon: Icons.smart_toy_outlined),
              MetaChip(fmtDateTime(rfc.updatedAt ?? rfc.createdAt), icon: Icons.schedule),
            ]),
            const SizedBox(height: 16),
            _ReadinessCard(status: status),
            const SizedBox(height: 16),
            Row(children: [
              FilledButton.icon(
                onPressed: widget.onFinalize,
                icon: const Icon(Icons.check_circle_outline),
                label: Text(l10n.t('rfc.finalize')),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _copyPrompt(rfc, status),
                icon: const Icon(Icons.content_copy_outlined),
                label: Text(l10n.t('rfc.copyPrompt')),
              ),
            ]),
            const Divider(height: 32),
            Text(l10n.t('rfc.summaryTitle'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            MarkdownView(bundle.version?.summary.value ?? ''),
            const Divider(height: 32),
            Text('${l10n.t('rfc.sections')} (${bundle.sections.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            for (final s in bundle.sections) _SectionTile(section: s),
            const Divider(height: 32),
            Text('${l10n.t('rfc.findings')} (${bundle.comments.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (bundle.comments.isEmpty)
              Text(l10n.t('rfc.noFindings'),
                  style: const TextStyle(fontSize: 12, color: OracleBrand.gray400)),
            for (final c in bundle.comments) _FindingCard(comment: c),
          ],
        );
      },
    );
  }
}

/// The readiness gate at a glance: blockers, majors, comment count, required
/// coverage and the checklist-complete badge.
class _ReadinessCard extends StatelessWidget {
  final RfcStatusReport status;
  const _ReadinessCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final ready = status.checklistComplete && status.blockingCriticals == 0;
    return SectionCard(
      title: l10n.t('rfc.readiness'),
      description: l10n.t('rfc.readinessDesc'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            StatusBadge(ready ? l10n.t('rfc.ready') : l10n.t('rfc.notReady'),
                color: ready ? OracleBrand.success : OracleBrand.warning),
            MetaChip('${l10n.t('rfc.blockingCriticals')}: ${status.blockingCriticals}',
                icon: Icons.block),
            MetaChip('${l10n.t('rfc.openMajors')}: ${status.openMajors}',
                icon: Icons.priority_high),
            MetaChip('${l10n.t('rfc.totalComments')}: ${status.totalComments}',
                icon: Icons.forum_outlined),
            MetaChip(
                '${l10n.t('rfc.requiredCovered')}: ${status.coveredRequired}/${status.requiredSections}',
                icon: Icons.checklist),
          ]),
        ),
      ],
    );
  }
}

/// One RFC section — key, coverage badge, required chip and its content
/// (collapsed by default).
class _SectionTile extends StatelessWidget {
  final RfcSectionEntity section;
  const _SectionTile({required this.section});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: const EdgeInsets.only(left: 4, right: 4, bottom: 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Row(children: [
          Expanded(
              child: Text(section.sectionKey,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          if (section.required)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: MetaChip('required', icon: Icons.gavel),
            ),
          StatusBadge(section.coverage, color: _coverageColor(section.coverage)),
        ]),
        children: [MarkdownView(section.content.value)],
      ),
    );
  }
}

/// One structured finding — typed, severity-badged, verified state and the
/// problem/proposed-solution body.
class _FindingCard extends StatelessWidget {
  final RfcCommentEntity comment;
  const _FindingCard({required this.comment});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              StatusBadge(comment.type.code, color: OracleBrand.blue),
              StatusBadge(comment.severity.code, color: _severityColor(comment.severity)),
              StatusBadge(
                  comment.verified ? l10n.t('rfc.verified') : l10n.t('rfc.unverified'),
                  color: comment.verified ? OracleBrand.success : OracleBrand.gray500),
              MetaChip(
                  comment.reviewerRole == null
                      ? comment.authorAgent
                      : '${comment.authorAgent} · ${comment.reviewerRole}',
                  icon: Icons.person_outline),
            ]),
            const SizedBox(height: 10),
            if (comment.problem.value.trim().isNotEmpty) ...[
              Text(l10n.t('rfc.problem'),
                  style: const TextStyle(fontSize: 12, color: OracleBrand.gray400)),
              const SizedBox(height: 2),
              MarkdownView(comment.problem.value),
            ],
            if (comment.proposedSolution.value.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(l10n.t('rfc.solution'),
                  style: const TextStyle(fontSize: 12, color: OracleBrand.gray400)),
              const SizedBox(height: 2),
              MarkdownView(comment.proposedSolution.value),
            ],
          ],
        ),
      ),
    );
  }
}

/// Builds the Portuguese reviewer hand-off prompt — the orchestration bridge to
/// another agent (no process spawning).
String buildReviewPrompt(RfcEntity rfc, RfcStatusReport status) {
  return 'Você é um revisor técnico do projeto. Revise a RFC ${rfc.id.value} — '
      '"${rfc.title.value}" no Oracle AI. Leia com oracle_rfc_get e poste achados '
      'ESTRUTURADOS com oracle_rfc_comment (cada gap/inconsistency/bug/blocker exige '
      'proposedSolution). Fundamente cada achado com oracle_rfc_evidence_add citando uma '
      'regra/memória real (por id) ou arquivo+trecho — achados não verificados não travam '
      'a conclusão. Priorize seções fracas (coverage missing/thin) e regras/arquitetura do '
      'projeto. Não alucine.\n\n'
      'Estado atual: ${status.coveredRequired}/${status.requiredSections} seções '
      'obrigatórias cobertas, ${status.blockingCriticals} bloqueadores verificados, '
      '${status.openMajors} majors abertos.';
}

String _statusLabel(RfcStatus status) => l10n.t('rfc.st.${status.code}');

Color _statusColor(RfcStatus status) {
  switch (status) {
    case RfcStatus.draft:
    case RfcStatus.inConsolidation:
      return OracleBrand.violet;
    case RfcStatus.openForComments:
    case RfcStatus.inReview:
      return OracleBrand.blue;
    case RfcStatus.awaitingHuman:
    case RfcStatus.stalled:
      return OracleBrand.warning;
    case RfcStatus.approved:
      return OracleBrand.success;
    case RfcStatus.rejected:
      return OracleBrand.error;
    case RfcStatus.superseded:
    case RfcStatus.obsolete:
      return OracleBrand.gray500;
  }
}

Color _coverageColor(String coverage) {
  switch (coverage) {
    case 'covered':
      return OracleBrand.success;
    case 'thin':
      return OracleBrand.warning;
    default:
      return OracleBrand.error;
  }
}

Color _severityColor(RfcSeverity severity) {
  switch (severity) {
    case RfcSeverity.critical:
      return OracleBrand.error;
    case RfcSeverity.major:
      return OracleBrand.warning;
    case RfcSeverity.minor:
    case RfcSeverity.info:
      return OracleBrand.gray500;
  }
}
