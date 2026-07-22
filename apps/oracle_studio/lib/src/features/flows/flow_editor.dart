import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';
import 'package:oracle_server/oracle_server.dart' as server;

import '../../core/brand.dart';
import '../../core/l10n.dart';
import '../../widgets/editor_dialog.dart';
import 'flow_guide_page.dart';
import 'flow_labels.dart';

const _nodeW = 196.0;
const _nodeH = 92.0;
const _minCanvasW = 3200.0;
const _minCanvasH = 2000.0;
const _canvasPadding = 420.0;
const _gridSize = 28.0;

/// N8N-style CANVAS editor: nodes are placed FREELY on a pannable/zoomable
/// canvas and connected by DRAGGING the port that appears when you hover a node
/// onto another node — branches, joins and loop-backs included. Dragging works
/// at any zoom (pointer positions are mapped to scene coordinates, never
/// deltas). Right-click a node for actions (duplicate, entry, delete). Node
/// positions persist in the step's config; the orchestrator (at most one) is
/// the flow's START.
class FlowEditorPage extends StatefulWidget {
  final ProjectEntity project;

  /// Existing graph to edit (a save creates a new version of the same key).
  final FlowGraph? initial;

  /// Seed steps for the one-click template.
  final List<StepDraft>? seed;

  /// Seed connections as (fromKey, toKey, condition, verdictValue,
  /// instruction) — when null, the seed steps are chained linearly.
  final List<(String, String, String, String?, String?)>? seedEdges;
  final String? seedKey;
  final String? seedName;

  const FlowEditorPage({
    super.key,
    required this.project,
    this.initial,
    this.seed,
    this.seedEdges,
    this.seedKey,
    this.seedName,
  });

  @override
  State<FlowEditorPage> createState() => _FlowEditorPageState();
}

class _FlowEditorPageState extends State<FlowEditorPage> {
  late final TextEditingController _key;
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _budget;
  late String _orchestratorAgent;

  final List<StepDraft> _steps = [];
  final List<EdgeDraft> _edges = [];
  final TransformationController _viewport = TransformationController();
  final GlobalKey _viewerKey = GlobalKey();

  int _selected = 0;
  int? _hovered;
  EdgeDraft? _hoveredEdge;
  EdgeDraft? _lastPressedEdge;
  DateTime? _lastEdgePressAt;

  /// Node being dragged and the grab offset inside it (scene coords).
  int? _dragging;
  Offset _dragGrab = Offset.zero;

  /// Connection in progress: source node, live pointer (scene coords) while
  /// dragging, and how far the pointer travelled (to tell a click from a drag).
  int? _connectFrom;
  Offset? _connectPoint;
  double _connectTravel = 0;

  /// Entry step (by OBJECT reference — key renames never break it) when there
  /// is NO orchestrator (the orchestrator, when present, is always the start).
  StepDraft? _entry;

  /// Skills registered in Oracle for this scope — the picker's source.
  List<SkillEntity> _availableSkills = const [];

  /// Processes registered in Oracle for this scope — the SUB-PROCESS picker's
  /// source (a subflow step points at one of these by key).
  List<FlowEntity> _availableFlows = const [];

  /// Per-agent health diagnostics (cached; re-check on demand).
  late final server.AgentDoctor _doctor;
  final Map<String, Future<server.AgentHealth>> _health = {};

  bool _saving = false;
  bool _snapToGrid = true;
  int? _panPointer;
  bool _canvasPanning = false;

  @override
  void initState() {
    super.initState();
    final g = widget.initial;
    _key = TextEditingController(text: g?.flow.key ?? widget.seedKey ?? '');
    _name = TextEditingController(
      text: g?.flow.name.value ?? widget.seedName ?? '',
    );
    _desc = TextEditingController(text: g?.flow.description ?? '');
    _budget = TextEditingController(text: _budgetOf(g?.flow.budgets));
    _orchestratorAgent = g?.flow.orchestratorAgent ?? 'claude-code';

    if (g != null) {
      final byId = {for (final s in g.steps) s.id.value: s.stepKey};
      _steps.addAll(g.steps.map(StepDraft.fromEntity));
      final byKey = {for (final d in _steps) d.key.text: d};
      for (final e in g.edges) {
        final from = byKey[byId[e.fromStep.value]];
        final to = byKey[byId[e.toStep.value]];
        if (from == null || to == null) continue;
        _edges.add(
          EdgeDraft(from: from, to: to)
            ..condition = e.condition
            ..verdict.text = e.verdictValue ?? ''
            ..instruction.text = e.instruction ?? '',
        );
      }
      _entry = byKey[g.flow.entryStepKey];
    } else if (widget.seed != null && widget.seed!.isNotEmpty) {
      _steps.addAll(widget.seed!);
      final seedEdges = widget.seedEdges;
      if (seedEdges != null) {
        final byKey = {for (final d in _steps) d.key.text: d};
        for (final (fromKey, toKey, condition, verdict, instruction)
            in seedEdges) {
          final from = byKey[fromKey];
          final to = byKey[toKey];
          if (from == null || to == null) continue;
          _edges.add(
            EdgeDraft(from: from, to: to)
              ..condition = condition
              ..verdict.text = verdict ?? ''
              ..instruction.text = instruction ?? '',
          );
        }
      } else {
        for (var i = 0; i < _steps.length - 1; i++) {
          _edges.add(EdgeDraft(from: _steps[i], to: _steps[i + 1]));
        }
      }
      _entry = _steps.first;
    } else {
      final first = StepDraft.of(
        key: 'inicio',
        kind: FlowStepKind.orchestrator,
      );
      _steps.add(first);
      _entry = first;
    }
    _autoLayout();
    _ensureCanvasPadding();
    _loadSkills();
    _loadFlows();
    _doctor = server.AgentDoctor(repoRoot: widget.project.repoPath);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitView());
  }

  Future<server.AgentHealth> _healthOf(String agent) =>
      _health[agent] ??= _doctor.check(agent);

  Future<void> _loadSkills() async {
    final result = await injector.get<ListSkillsUsecase>()(
      projectId: widget.project.id,
      organizationId: widget.project.organizationId,
    );
    if (!mounted) return;
    setState(() => _availableSkills = result.getOrDefault(const []));
  }

  Future<void> _loadFlows() async {
    final result = await injector.get<ListFlowsUsecase>()(
      projectId: widget.project.id,
      organizationId: widget.project.organizationId,
    );
    if (!mounted) return;
    // A process must not call ITSELF (recursion) — hide the flow being edited.
    final self = widget.initial?.flow.key ?? widget.seedKey;
    setState(
      () => _availableFlows = result
          .getOrDefault(const [])
          .where((f) => f.key != self)
          .toList(),
    );
  }

  /// Places any node still at (0,0) in a left-to-right cascade.
  void _autoLayout() {
    var i = 0;
    for (final d in _steps) {
      if (d.x == 0 && d.y == 0) {
        d.x = 90.0 + (i % 5) * (_nodeW + 70);
        d.y = 120.0 + (i ~/ 5) * (_nodeH + 90) + (i % 2) * 24;
      }
      i++;
    }
  }

  /// Keeps content away from the scene origin. The router is allowed to send
  /// loop-back connections around the outside of the graph, so nodes need real
  /// breathing room on every side instead of starting at x/y ≈ 0.
  void _ensureCanvasPadding() {
    if (_steps.isEmpty) return;
    var minX = _steps.first.x;
    var minY = _steps.first.y;
    for (final step in _steps.skip(1)) {
      if (step.x < minX) minX = step.x;
      if (step.y < minY) minY = step.y;
    }
    final dx = minX < _canvasPadding ? _canvasPadding - minX : 0.0;
    final dy = minY < _canvasPadding ? _canvasPadding - minY : 0.0;
    if (dx == 0 && dy == 0) return;
    for (final step in _steps) {
      step.x += dx;
      step.y += dy;
    }
  }

  double get _canvasWidth {
    var right = _minCanvasW - _canvasPadding;
    for (final step in _steps) {
      if (step.x + _nodeW > right) right = step.x + _nodeW;
    }
    return (right + _canvasPadding * 2).clamp(_minCanvasW, 20000.0);
  }

  double get _canvasHeight {
    var bottom = _minCanvasH - _canvasPadding;
    for (final step in _steps) {
      if (step.y + _nodeH > bottom) bottom = step.y + _nodeH;
    }
    return (bottom + _canvasPadding * 2).clamp(_minCanvasH, 14000.0);
  }

  /// Organizes the graph in readable left-to-right layers. Loop-back edges do
  /// not push nodes into ever deeper columns: the first visit fixes a node's
  /// layer, which keeps cycles compact and visually obvious.
  void _organizeGraph() {
    if (_steps.isEmpty) return;
    final level = <StepDraft, int>{};
    final queue = <StepDraft>[];

    void visitComponent(StepDraft root, int baseLevel) {
      if (level.containsKey(root)) return;
      level[root] = baseLevel;
      queue.add(root);
      while (queue.isNotEmpty) {
        final current = queue.removeAt(0);
        final nextLevel = level[current]! + 1;
        final outgoing = _edges
            .where((e) => identical(e.from, current))
            .map((e) => e.to)
            .toList();
        for (final next in outgoing) {
          if (level.containsKey(next)) continue;
          level[next] = nextLevel;
          queue.add(next);
        }
      }
    }

    visitComponent(_startDraft ?? _steps.first, 0);
    var disconnectedLevel = level.values.fold(0, (a, b) => a > b ? a : b) + 1;
    for (final step in _steps) {
      if (!level.containsKey(step)) {
        visitComponent(step, disconnectedLevel);
        disconnectedLevel = level.values.fold(0, (a, b) => a > b ? a : b) + 1;
      }
    }

    final columns = <int, List<StepDraft>>{};
    for (final step in _steps) {
      columns.putIfAbsent(level[step]!, () => []).add(step);
    }
    setState(() {
      for (final entry in columns.entries) {
        final items = entry.value;
        final totalHeight = items.length * _nodeH + (items.length - 1) * 72;
        final top = (160 + (420 - totalHeight) / 2).clamp(70.0, 500.0);
        for (var i = 0; i < items.length; i++) {
          items[i].x = _canvasPadding + entry.key * (_nodeW + 112);
          items[i].y = _canvasPadding + top + i * (_nodeH + 72);
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitView());
  }

  Rect get _graphBounds {
    if (_steps.isEmpty) return const Rect.fromLTWH(0, 0, 800, 500);
    var left = _steps.first.x;
    var top = _steps.first.y;
    var right = left + _nodeW;
    var bottom = top + _nodeH;
    for (final step in _steps.skip(1)) {
      left = left < step.x ? left : step.x;
      top = top < step.y ? top : step.y;
      right = right > step.x + _nodeW ? right : step.x + _nodeW;
      bottom = bottom > step.y + _nodeH ? bottom : step.y + _nodeH;
    }
    // Fit the CONNECTIONS too. Loop-back routes deliberately travel around the
    // graph and were previously cut off even when every node fitted on screen.
    final routes = _EdgeRouter.routeAll(_edges, _steps);
    for (final route in routes.values) {
      for (final point in route.points) {
        if (point.dx < left) left = point.dx;
        if (point.dy < top) top = point.dy;
        if (point.dx > right) right = point.dx;
        if (point.dy > bottom) bottom = point.dy;
      }
    }
    return Rect.fromLTRB(left, top, right, bottom).inflate(110);
  }

  void _fitView() {
    if (!mounted || _viewerKey.currentContext == null) return;
    final box = _viewerKey.currentContext!.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.isEmpty) return;
    final bounds = _graphBounds;
    final scale = math
        .min(box.size.width / bounds.width, box.size.height / bounds.height)
        .clamp(0.2, 1.25);
    final tx =
        (box.size.width - bounds.width * scale) / 2 - bounds.left * scale;
    final ty =
        (box.size.height - bounds.height * scale) / 2 - bounds.top * scale;
    _viewport.value = _viewMatrix(
      scale.toDouble(),
      tx.toDouble(),
      ty.toDouble(),
    );
  }

  void _zoomBy(double factor) {
    if (_viewerKey.currentContext == null) return;
    final box = _viewerKey.currentContext!.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final center = box.size.center(Offset.zero);
    _zoomAt(factor, center);
  }

  void _zoomAt(double factor, Offset focalPoint) {
    final sceneCenter = _viewport.toScene(focalPoint);
    final current = _viewport.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(0.2, 2.5);
    _viewport.value = _viewMatrix(
      next.toDouble(),
      focalPoint.dx - sceneCenter.dx * next,
      focalPoint.dy - sceneCenter.dy * next,
    );
  }

  void _panViewport(Offset delta) {
    final matrix = _viewport.value;
    _viewport.value = _viewMatrix(
      matrix.getMaxScaleOnAxis(),
      matrix.entry(0, 3) + delta.dx,
      matrix.entry(1, 3) + delta.dy,
    );
  }

  void _handleCanvasSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _dragging != null) return;
    final keyboard = HardwareKeyboard.instance;
    final controlPressed = keyboard.isControlPressed || keyboard.isMetaPressed;
    if (controlPressed) {
      final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return;
      final local = box.globalToLocal(event.position);
      _zoomAt(math.exp(-event.scrollDelta.dy * 0.0015), local);
      return;
    }
    final horizontal = keyboard.isShiftPressed
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    final vertical = keyboard.isShiftPressed ? 0.0 : event.scrollDelta.dy;
    _panViewport(Offset(-horizontal, -vertical));
  }

  void _startCanvasPan(PointerDownEvent event) {
    final spacePressed = HardwareKeyboard.instance.isLogicalKeyPressed(
      LogicalKeyboardKey.space,
    );
    final middleButton = event.buttons == kMiddleMouseButton;
    final spaceAndPrimary =
        spacePressed && (event.buttons & kPrimaryMouseButton) != 0;
    if (!middleButton && !spaceAndPrimary) return;
    if (_dragging != null || _connectFrom != null) return;
    setState(() {
      _panPointer = event.pointer;
      _canvasPanning = true;
    });
  }

  void _moveCanvasPan(PointerMoveEvent event) {
    if (_panPointer != event.pointer) return;
    _panViewport(event.delta);
  }

  void _endCanvasPan(PointerEvent event) {
    if (_panPointer != event.pointer) return;
    setState(() {
      _panPointer = null;
      _canvasPanning = false;
    });
  }

  Matrix4 _viewMatrix(double scale, double tx, double ty) => Matrix4.identity()
    ..setEntry(0, 0, scale)
    ..setEntry(1, 1, scale)
    ..setEntry(0, 3, tx)
    ..setEntry(1, 3, ty);

  StepDraft? get _orchestrator {
    for (final d in _steps) {
      if (d.kind == FlowStepKind.orchestrator) return d;
    }
    return null;
  }

  /// The flow's start: the orchestrator when present, else [_entry].
  StepDraft? get _startDraft {
    final orch = _orchestrator;
    if (orch != null) return orch;
    final e = _entry;
    if (e != null && _steps.contains(e)) return e;
    return _steps.isEmpty ? null : _steps.first;
  }

  /// Maps a GLOBAL pointer position to canvas SCENE coordinates — exact at any
  /// zoom/pan, which is what makes dragging stable.
  Offset _toScene(Offset global) {
    final box = _viewerKey.currentContext!.findRenderObject()! as RenderBox;
    return _viewport.toScene(box.globalToLocal(global));
  }

  // ── node mechanics ──

  Future<void> _addNode() async {
    final make = await _pickStep(
      context,
      orchestratorTaken: _orchestrator != null,
    );
    if (make == null) return;
    setState(() {
      final d = make();
      d.key.text = _freshKey(d.key.text);
      final last = _steps.isEmpty ? null : _steps[_steps.length - 1];
      d.x = (last?.x ?? _canvasPadding) + _nodeW + 70;
      d.y = last?.y ?? _canvasPadding;
      if (d.x > 19000) {
        d.x = _canvasPadding;
        d.y = (last?.y ?? 120) + _nodeH + 90;
      }
      _steps.add(d);
      _selected = _steps.length - 1;
      _entry ??= d;
    });
  }

  String _freshKey(String base0) {
    final used = {for (final s in _steps) s.key.text};
    final base = base0.isEmpty ? 'etapa' : base0;
    if (!used.contains(base)) return base;
    var i = 2;
    while (used.contains('$base$i')) {
      i++;
    }
    return '$base$i';
  }

  void _duplicateStep(int index) {
    setState(() {
      final d = _steps[index].duplicate(_freshKey(_steps[index].key.text));
      // An orchestrator copy degrades to a plain agent step (only one allowed).
      if (d.kind == FlowStepKind.orchestrator) d.kind = FlowStepKind.agent;
      d.x = (_steps[index].x + 42).clamp(80.0, 19800.0 - _nodeW);
      d.y = (_steps[index].y + 42).clamp(80.0, 13800.0 - _nodeH);
      _steps.add(d);
      _selected = _steps.length - 1;
    });
  }

  void _removeStep(int index) {
    if (_steps.length <= 1) return;
    setState(() {
      final removed = _steps[index];
      _steps.removeAt(index);
      _edges.removeWhere((e) => e.from == removed || e.to == removed);
      if (_entry == removed) _entry = _steps.first;
      _selected = _selected.clamp(0, _steps.length - 1);
      _hovered = null;
      if (_connectFrom != null && _connectFrom! >= _steps.length) {
        _cancelConnect();
      }
    });
  }

  void _removeConnectionsOf(int index) {
    setState(() {
      final d = _steps[index];
      _edges.removeWhere((e) => e.from == d || e.to == d);
    });
  }

  Future<void> _nodeMenu(int index, Offset globalPos) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final d = _steps[index];
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPos & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'duplicate',
          child: _menuRow(Icons.copy_outlined, l10n.t('flows.duplicate')),
        ),
        if (_orchestrator == null && !identical(d, _startDraft))
          PopupMenuItem(
            value: 'entry',
            child: _menuRow(Icons.flag_outlined, l10n.t('flows.setEntry')),
          ),
        PopupMenuItem(
          value: 'disconnect',
          child: _menuRow(Icons.link_off, l10n.t('flows.removeConnections')),
        ),
        if (_steps.length > 1)
          PopupMenuItem(
            value: 'delete',
            child: _menuRow(
              Icons.delete_outline,
              l10n.t('common.delete'),
              color: OracleBrand.error,
            ),
          ),
      ],
    );
    switch (action) {
      case 'duplicate':
        _duplicateStep(index);
      case 'entry':
        setState(() => _entry = d);
      case 'disconnect':
        _removeConnectionsOf(index);
      case 'delete':
        _removeStep(index);
    }
  }

  Widget _menuRow(IconData icon, String label, {Color? color}) => Row(
    children: [
      Icon(icon, size: 17, color: color ?? OracleBrand.gray400),
      const SizedBox(width: 10),
      Text(label, style: TextStyle(fontSize: 13.5, color: color)),
    ],
  );

  // ── connection mechanics (n8n drag-from-port) ──

  void _portDragStart(int index, Offset global) {
    setState(() {
      _connectFrom = index;
      _connectPoint = _toScene(global);
      _connectTravel = 0;
    });
  }

  void _portDragUpdate(Offset global, Offset delta) {
    if (_connectFrom == null) return;
    setState(() {
      _connectPoint = _toScene(global);
      _connectTravel += delta.distance;
    });
  }

  void _portDragEnd() {
    final from = _connectFrom;
    final point = _connectPoint;
    if (from == null || point == null) return;
    // A real drag connects to the node under the pointer; a mere click enters
    // click-to-connect mode (banner) instead.
    if (_connectTravel < 8) {
      setState(() => _connectPoint = null);
      return;
    }
    int? target;
    for (var i = 0; i < _steps.length; i++) {
      final d = _steps[i];
      final rect = Rect.fromLTWH(d.x - 8, d.y - 8, _nodeW + 16, _nodeH + 16);
      if (rect.contains(point)) {
        target = i;
        break;
      }
    }
    if (target != null && target != from) {
      _createEdge(from, target);
    }
    _cancelConnect();
  }

  void _createEdge(int fromIndex, int toIndex) {
    final from = _steps[fromIndex];
    final to = _steps[toIndex];
    final exists = _edges.any((e) => e.from == from && e.to == to);
    setState(() {
      if (!exists) _edges.add(EdgeDraft(from: from, to: to));
    });
  }

  void _cancelConnect() => setState(() {
    _connectFrom = null;
    _connectPoint = null;
    _connectTravel = 0;
  });

  Future<void> _editEdge(EdgeDraft e) async {
    var condition = e.condition;
    final verdict = TextEditingController(text: e.verdict.text);
    final instruction = TextEditingController(text: e.instruction.text);
    var removed = false;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          title: Text('${e.from.key.text}  →  ${e.to.key.text}'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LabeledDropdown(
                  label: l10n.t('flows.condition'),
                  value: condition,
                  options: edgeConditions,
                  labelOf: conditionLabel,
                  onChanged: (v) => setDlg(() => condition = v),
                ),
                if (condition == 'verdict') ...[
                  FieldRow(
                    l10n.t('flows.verdict'),
                    verdict,
                    description: l10n.t('flows.verdictDesc'),
                  ),
                  FieldRow(
                    l10n.t('flows.edgeInstruction'),
                    instruction,
                    maxLines: 3,
                    description: l10n.t('flows.edgeInstructionDesc'),
                    hint: l10n.t('flows.edgeInstructionHint'),
                    expandable: true,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                removed = true;
                Navigator.pop(context);
              },
              child: Text(
                l10n.t('flows.deleteConnection'),
                style: const TextStyle(color: OracleBrand.error),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.t('common.cancel')),
            ),
            FilledButton(
              onPressed: () {
                e.condition = condition;
                e.verdict.text = verdict.text;
                e.instruction.text = instruction.text;
                Navigator.pop(context);
              },
              child: Text(l10n.t('common.save')),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      if (removed) _edges.remove(e);
    });
  }

  // ── save ──

  Future<void> _save() async {
    String? fail;
    if (_key.text.trim().isEmpty) fail = l10n.t('flows.keyRequired');
    if (_name.text.trim().isEmpty) fail ??= l10n.t('flows.nameRequired');
    for (final s in _steps) {
      if (s.key.text.trim().isEmpty) fail ??= l10n.t('flows.stepKeyRequired');
    }
    final keys = {for (final s in _steps) s.key.text.trim()};
    if (keys.length != _steps.length) fail ??= l10n.t('flows.dupStepKey');
    if (_steps.where((s) => s.kind == FlowStepKind.orchestrator).length > 1) {
      fail ??= l10n.t('flows.onlyOneOrchestrator');
    }
    if (_steps.any(
      (s) => s.kind == FlowStepKind.subflow && s.subflowKey.trim().isEmpty,
    )) {
      fail ??= l10n.t('flows.subflowRequired');
    }
    for (final s in _steps) {
      final isAgent =
          s.kind == FlowStepKind.agent ||
          s.kind == FlowStepKind.orchestrator ||
          s.kind == FlowStepKind.decision ||
          s.kind == FlowStepKind.rfcCreate ||
          s.kind == FlowStepKind.rfcReview ||
          s.kind == FlowStepKind.rfcConsolidate;
      if (isAgent && !{...agentIds, 'claude'}.contains(s.agent)) {
        fail ??= l10n.t('flows.unsupportedAgent');
      }
      if (isAgent && (int.tryParse(s.maxIter.text.trim()) ?? 0) < 1) {
        fail ??= l10n.t('flows.invalidMaxIterations');
      }
      final timeoutText = s.timeout.text.trim();
      if (timeoutText.isNotEmpty && (int.tryParse(timeoutText) ?? -1) < 0) {
        fail ??= l10n.t('flows.invalidTimeout');
      }
      if (s.kind == FlowStepKind.command && s.command.text.trim().isEmpty) {
        fail ??= l10n.t('flows.commandRequired');
      }
      if (s.kind == FlowStepKind.rfcGate &&
          (int.tryParse(s.maxRounds.text.trim()) ?? 0) < 1) {
        fail ??= l10n.t('flows.invalidMaxRounds');
      }
      final incoming = _edges
          .where((e) => identical(e.to, s))
          .map((e) => e.from)
          .toSet();
      final outgoing = _edges.where((e) => identical(e.from, s)).toList();
      if (s.kind == FlowStepKind.join && incoming.length < 2) {
        fail ??= l10n.t('flows.joinIncomingRequired');
      }
      if (s.kind == FlowStepKind.decision) {
        final verdicts = outgoing
            .where((e) => e.condition == 'verdict')
            .toList();
        if (verdicts.length < 2) {
          fail ??= l10n.t('flows.decisionVerdictsRequired');
        }
        final values = verdicts.map((e) => e.verdict.text.trim()).toList();
        if (values.any((v) => v.isEmpty) ||
            values.toSet().length != values.length) {
          fail ??= l10n.t('flows.invalidVerdictValues');
        }
      }
    }
    if (fail != null) {
      showSnack(context, fail);
      return;
    }

    setState(() => _saving = true);
    final stepEntities = <FlowStepEntity>[
      for (var i = 0; i < _steps.length; i++) _steps[i].toEntity(i),
    ];
    final edgeEntities = <FlowEdgeEntity>[
      for (final e in _edges)
        FlowEdgeEntity(
          id: const IdVO.empty(),
          flowId: const IdVO.empty(),
          fromStep: IdVO(e.from.key.text.trim()),
          toStep: IdVO(e.to.key.text.trim()),
          condition: e.condition,
          verdictValue: e.verdict.text.trim().isEmpty
              ? null
              : e.verdict.text.trim(),
          instruction: e.instruction.text.trim().isEmpty
              ? null
              : e.instruction.text.trim(),
        ),
    ];
    final flow = FlowEntity(
      id: const IdVO.empty(),
      organizationId: widget.project.organizationId,
      projectId: widget.project.id,
      key: _key.text.trim(),
      name: TextVO(_name.text.trim()),
      description: _desc.text.trim(),
      orchestratorAgent: _orchestrator?.agent ?? _orchestratorAgent,
      entryStepKey: _startDraft?.key.text.trim() ?? '',
      budgets: _budgetJson(_budget.text),
    );

    final result = await injector.get<SaveFlowUsecase>()(
      flow,
      stepEntities,
      edgeEntities,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    result.fold(
      (g) => Navigator.pop(context, g.flow),
      (f) => showSnack(
        context,
        f.fields.isEmpty
            ? f.errorMessage
            : '${f.errorMessage}: ${f.fields.map((e) => e.message).join(' · ')}',
      ),
    );
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return Scaffold(
      backgroundColor: OracleBrand.gray950,
      body: Column(
        children: [
          _header(editing),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _canvas()),
                const VerticalDivider(width: 1),
                SizedBox(width: 420, child: _propertiesPanel()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(bool editing) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: OracleBrand.gray900,
        border: Border(bottom: BorderSide(color: OracleBrand.gray700)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 4),
          Text(
            editing ? l10n.t('flows.editorEdit') : l10n.t('flows.editorNew'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (editing) ...[
            const SizedBox(width: 10),
            MetaChipSmall(
              'v${widget.initial!.flow.versionNo} → v${widget.initial!.flow.versionNo + 1}',
            ),
          ],
          const SizedBox(width: 22),
          SizedBox(
            width: 190,
            child: _denseField(l10n.t('flows.fName'), _name),
          ),
          const SizedBox(width: 12),
          // The key is the process IDENTITY — locked while editing (saving always
          // creates a new version of the SAME key; changing it would fork).
          SizedBox(
            width: 160,
            child: _denseField(
              l10n.t('flows.fKey'),
              _key,
              enabled: editing == false,
              lockTooltip: editing ? l10n.t('flows.keyLocked') : null,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 150,
            child: _denseField(
              l10n.t('flows.fBudget'),
              _budget,
              hint: '800000',
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: l10n.t('flows.guide'),
            icon: const Icon(Icons.help_outline, size: 20),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const FlowGuidePage())),
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            onPressed: _addNode,
            icon: const Icon(Icons.add, size: 18),
            label: Text(l10n.t('flows.addStep')),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined, size: 18),
            label: Text(
              _saving ? l10n.t('common.saving') : l10n.t('flows.saveProcess'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _denseField(
    String label,
    TextEditingController c, {
    String? hint,
    bool enabled = true,
    String? lockTooltip,
  }) {
    return TextField(
      controller: c,
      enabled: enabled,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        suffixIcon: lockTooltip == null
            ? null
            : Tooltip(
                message: lockTooltip,
                child: const Icon(
                  Icons.lock_outline,
                  size: 15,
                  color: OracleBrand.gray500,
                ),
              ),
      ),
    );
  }

  Widget _canvas() {
    final connectSource = _connectFrom != null && _connectFrom! < _steps.length
        ? _steps[_connectFrom!]
        : null;
    final routes = _EdgeRouter.routeAll(_edges, _steps);
    return Stack(
      children: [
        MouseRegion(
          cursor: _canvasPanning
              ? SystemMouseCursors.grabbing
              : _hoveredEdge == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          onHover: (event) => _updateHoveredEdge(event.position, routes),
          onExit: (_) {
            if (_hoveredEdge != null) setState(() => _hoveredEdge = null);
          },
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerSignal: _handleCanvasSignal,
            onPointerDown: (event) {
              _startCanvasPan(event);
              _handleCanvasPointerDown(event, routes);
            },
            onPointerMove: _moveCanvasPan,
            onPointerUp: _endCanvasPan,
            onPointerCancel: _endCanvasPan,
            child: InteractiveViewer(
              key: _viewerKey,
              transformationController: _viewport,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(_canvasPadding),
              minScale: 0.2,
              maxScale: 2.5,
              panEnabled: false,
              scaleEnabled: false,
              child: SizedBox(
                width: _canvasWidth,
                height: _canvasHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // grid + edges + live connection preview
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _CanvasPainter(
                          edges: _edges,
                          routes: routes,
                          hoveredNode:
                              _hovered != null && _hovered! < _steps.length
                              ? _steps[_hovered!]
                              : null,
                          hoveredEdge: _hoveredEdge,
                          previewFrom: connectSource,
                          previewTo: _connectPoint,
                        ),
                      ),
                    ),
                    // edge label chips (tap to edit the connection)
                    for (final e in _edges) _edgeChip(e, routes[e]!),
                    // nodes
                    for (var i = 0; i < _steps.length; i++) _node(i),
                  ],
                ),
              ),
            ),
          ),
        ),
        // click-to-connect banner (when the port was clicked, not dragged)
        if (_connectFrom != null && _connectPoint == null)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Material(
                color: OracleBrand.violet,
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.linear_scale,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${l10n.t('flows.connectingFrom')} '
                        '"${_steps[_connectFrom!].key.text}" — '
                        '${l10n.t('flows.connectingHint')}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(width: 10),
                      InkWell(
                        onTap: _cancelConnect,
                        child: const Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Positioned(top: 12, right: 12, child: _canvasToolbar()),
        // canvas hint
        Positioned(
          left: 12,
          bottom: 10,
          child: Text(
            l10n.t('flows.canvasHint'),
            style: const TextStyle(fontSize: 11.5, color: OracleBrand.gray500),
          ),
        ),
      ],
    );
  }

  EdgeDraft? _edgeAt(Offset scene, Map<EdgeDraft, _EdgeRoute> routes) {
    final tolerance = 9 / _viewport.value.getMaxScaleOnAxis();
    EdgeDraft? nearest;
    var nearestDistance = double.infinity;
    for (final entry in routes.entries) {
      final points = entry.value.points;
      for (var i = 0; i < points.length - 1; i++) {
        final distance = _distanceToSegment(scene, points[i], points[i + 1]);
        if (distance <= tolerance && distance < nearestDistance) {
          nearest = entry.key;
          nearestDistance = distance;
        }
      }
    }
    return nearest;
  }

  double _distanceToSegment(Offset point, Offset a, Offset b) {
    final segment = b - a;
    final lengthSquared = segment.dx * segment.dx + segment.dy * segment.dy;
    if (lengthSquared == 0) return (point - a).distance;
    final relative = point - a;
    final t =
        ((relative.dx * segment.dx + relative.dy * segment.dy) / lengthSquared)
            .clamp(0.0, 1.0);
    return (point - (a + segment * t)).distance;
  }

  void _updateHoveredEdge(Offset global, Map<EdgeDraft, _EdgeRoute> routes) {
    if (_dragging != null || _connectFrom != null) return;
    final edge = _edgeAt(_toScene(global), routes);
    if (!identical(edge, _hoveredEdge)) setState(() => _hoveredEdge = edge);
  }

  void _handleCanvasPointerDown(
    PointerDownEvent event,
    Map<EdgeDraft, _EdgeRoute> routes,
  ) {
    if (_canvasPanning ||
        event.buttons != 1 ||
        _dragging != null ||
        _connectFrom != null) {
      return;
    }
    final edge = _edgeAt(_toScene(event.position), routes);
    if (edge == null) {
      _lastPressedEdge = null;
      _lastEdgePressAt = null;
      return;
    }
    final now = DateTime.now();
    final isDoubleClick =
        identical(edge, _lastPressedEdge) &&
        _lastEdgePressAt != null &&
        now.difference(_lastEdgePressAt!).inMilliseconds <= 420;
    _lastPressedEdge = edge;
    _lastEdgePressAt = now;
    if (isDoubleClick) {
      _lastPressedEdge = null;
      _lastEdgePressAt = null;
      _editEdge(edge);
    }
  }

  Widget _canvasToolbar() {
    return Material(
      color: OracleBrand.gray900.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          border: Border.all(color: OracleBrand.gray700),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 12)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _canvasAction(
              Icons.auto_fix_high,
              l10n.t('flows.organize'),
              _organizeGraph,
            ),
            _canvasAction(Icons.fit_screen, l10n.t('flows.fitView'), _fitView),
            const SizedBox(height: 22, child: VerticalDivider(width: 9)),
            _canvasAction(
              Icons.remove,
              l10n.t('flows.zoomOut'),
              () => _zoomBy(0.84),
            ),
            AnimatedBuilder(
              animation: _viewport,
              builder: (context, _) => SizedBox(
                width: 46,
                child: Text(
                  '${(_viewport.value.getMaxScaleOnAxis() * 100).round()}%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: OracleBrand.gray400,
                  ),
                ),
              ),
            ),
            _canvasAction(
              Icons.add,
              l10n.t('flows.zoomIn'),
              () => _zoomBy(1.19),
            ),
            const SizedBox(height: 22, child: VerticalDivider(width: 9)),
            Tooltip(
              message: l10n.t('flows.snapGrid'),
              child: InkWell(
                borderRadius: BorderRadius.circular(7),
                onTap: () => setState(() => _snapToGrid = !_snapToGrid),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _snapToGrid
                        ? OracleBrand.violet.withValues(alpha: 0.18)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(
                    Icons.grid_4x4,
                    size: 17,
                    color: _snapToGrid
                        ? OracleBrand.violetSoft
                        : OracleBrand.gray400,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _canvasAction(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: SizedBox(width: 32, height: 32, child: Icon(icon, size: 17)),
      ),
    );
  }

  Widget _edgeChip(EdgeDraft e, _EdgeRoute route) {
    final mid = route.label;
    final color = _CanvasPainter.edgeColor(e.condition);
    final hoveredNode = _hovered != null && _hovered! < _steps.length
        ? _steps[_hovered!]
        : null;
    final focusActive = hoveredNode != null || _hoveredEdge != null;
    final emphasized =
        identical(e, _hoveredEdge) ||
        (hoveredNode != null &&
            (identical(e.from, hoveredNode) || identical(e.to, hoveredNode)));
    final label = e.condition == 'verdict' && e.verdict.text.trim().isNotEmpty
        ? e.verdict.text.trim()
        : conditionLabel(e.condition);
    final hint = e.instruction.text.trim();
    return Positioned(
      left: mid.dx - 40,
      top: mid.dy - 12,
      child: AnimatedOpacity(
        opacity: !focusActive || emphasized ? 1 : .28,
        duration: const Duration(milliseconds: 120),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hoveredEdge = e),
          onExit: (_) {
            if (identical(_hoveredEdge, e)) setState(() => _hoveredEdge = null);
          },
          child: Tooltip(
            message: hint.isEmpty ? l10n.t('flows.editConnection') : hint,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => _editEdge(e),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 120),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: OracleBrand.gray900,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color.withValues(alpha: 0.55)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hint.isNotEmpty) ...[
                      Icon(Icons.notes, size: 10, color: color),
                      const SizedBox(width: 3),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _node(int i) {
    final d = _steps[i];
    final selected = i == _selected;
    final color = kindColor(d.kind);
    final isStart = identical(d, _startDraft);
    final clickConnecting = _connectFrom != null && _connectPoint == null;
    final showPort =
        _hovered == i || selected || _connectFrom == i || clickConnecting;
    return Positioned(
      left: d.x,
      top: d.y,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = i),
        onExit: (_) =>
            setState(() => _hovered = _hovered == i ? null : _hovered),
        child: GestureDetector(
          onTap: () {
            if (clickConnecting) {
              if (_connectFrom != i) _createEdge(_connectFrom!, i);
              _cancelConnect();
            } else {
              setState(() => _selected = i);
            }
          },
          onSecondaryTapDown: (details) {
            setState(() => _selected = i);
            _nodeMenu(i, details.globalPosition);
          },
          // Drag via SCENE coordinates (exact under any zoom/pan).
          onPanStart: (details) {
            if (_canvasPanning ||
                HardwareKeyboard.instance.isLogicalKeyPressed(
                  LogicalKeyboardKey.space,
                )) {
              return;
            }
            final scene = _toScene(details.globalPosition);
            setState(() {
              _selected = i;
              _dragging = i;
              _dragGrab = scene - Offset(d.x, d.y);
            });
          },
          onPanUpdate: (details) {
            if (_dragging != i) return;
            final scene = _toScene(details.globalPosition);
            setState(() {
              var x = scene.dx - _dragGrab.dx;
              var y = scene.dy - _dragGrab.dy;
              if (_snapToGrid) {
                x = (x / _gridSize).round() * _gridSize;
                y = (y / _gridSize).round() * _gridSize;
              }
              d.x = x.clamp(80.0, 19800.0 - _nodeW);
              d.y = y.clamp(80.0, 13800.0 - _nodeH);
            });
          },
          onPanEnd: (_) => setState(() => _dragging = null),
          onPanCancel: () => setState(() => _dragging = null),
          child: AnimatedBuilder(
            animation: Listenable.merge([d.key, d.name, d.command, d.model]),
            builder: (context, _) => Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: _nodeW,
                  height: _nodeH,
                  padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
                  decoration: BoxDecoration(
                    color: clickConnecting && _connectFrom != i
                        ? OracleBrand.gray800
                        : OracleBrand.gray900,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? color : OracleBrand.gray700,
                      width: selected ? 2 : 1,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.25),
                              blurRadius: 14,
                            ),
                          ]
                        : const [],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(kindIcon(d.kind), size: 14, color: color),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    kindLabel(d.kind),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: color,
                                    ),
                                  ),
                                ),
                                if (isStart)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: OracleBrand.success.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      l10n.t('flows.startBadge'),
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: OracleBrand.success,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              d.key.text.isEmpty ? '—' : d.key.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _nodeSubtitle(d),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: OracleBrand.gray400,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // output port — appears on hover; DRAG it onto another node
                      AnimatedOpacity(
                        opacity: showPort ? 1 : 0,
                        duration: const Duration(milliseconds: 120),
                        child: IgnorePointer(
                          ignoring: !showPort,
                          child: Tooltip(
                            message: l10n.t('flows.connect'),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: (details) =>
                                  _portDragStart(i, details.globalPosition),
                              onPanUpdate: (details) => _portDragUpdate(
                                details.globalPosition,
                                details.delta,
                              ),
                              onPanEnd: (_) => _portDragEnd(),
                              onPanCancel: _cancelConnect,
                              onTap: () => setState(() {
                                _connectFrom = i;
                                _connectPoint = null;
                                _connectTravel = 0;
                              }),
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _connectFrom == i
                                        ? color
                                        : OracleBrand.gray800,
                                    border: Border.all(
                                      color: color.withValues(alpha: 0.8),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.arrow_forward,
                                    size: 14,
                                    color: _connectFrom == i
                                        ? Colors.white
                                        : color,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 120),
                  left: showPort ? -5 : 0,
                  top: _nodeH / 2 - 5,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: showPort ? 1 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: OracleBrand.gray900,
                          border: Border.all(
                            color: clickConnecting
                                ? color
                                : OracleBrand.gray500,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _nodeSubtitle(StepDraft d) {
    switch (d.kind) {
      case FlowStepKind.command:
        return d.command.text.isEmpty
            ? l10n.t('flows.noCommand')
            : d.command.text;
      case FlowStepKind.subflow:
        return d.subflowKey.isEmpty
            ? l10n.t('flows.noSubflow')
            : '▶ ${d.subflowKey}';
      case FlowStepKind.humanGate:
        return l10n.t('flowkindDesc.human_gate');
      case FlowStepKind.rfcGate:
        return l10n.t('flowkindDesc.rfc_gate');
      case FlowStepKind.join:
        return l10n.t('flowkindDesc.join');
      default:
        final model = d.model.text.trim();
        return model.isEmpty
            ? agentLabel(d.agent)
            : '${agentLabel(d.agent)} · $model';
    }
  }

  // ── properties panel ──

  Widget _propertiesPanel() {
    if (_steps.isEmpty) return const SizedBox();
    final i = _selected.clamp(0, _steps.length - 1);
    final d = _steps[i];
    final isAgent =
        d.kind == FlowStepKind.agent ||
        d.kind == FlowStepKind.orchestrator ||
        d.kind == FlowStepKind.decision ||
        d.kind == FlowStepKind.rfcCreate ||
        d.kind == FlowStepKind.rfcReview ||
        d.kind == FlowStepKind.rfcConsolidate;
    final orch = _orchestrator;
    return Container(
      color: OracleBrand.gray900,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        children: [
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              l10n.t('flows.secProcess'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            children: [
              FieldRow(
                l10n.t('flows.fDesc'),
                _desc,
                maxLines: 3,
                expandable: true,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: kindColor(d.kind).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  kindIcon(d.kind),
                  size: 17,
                  color: kindColor(d.kind),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kindLabel(d.kind),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${l10n.t('flows.step')} ${i + 1} · ${_steps.length} ${l10n.t('flows.stepsShort')}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: OracleBrand.gray500,
                      ),
                    ),
                    Text(
                      kindDescription(d.kind),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: OracleBrand.gray500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.t('flows.duplicate'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_outlined, size: 18),
                onPressed: () => _duplicateStep(i),
              ),
              IconButton(
                tooltip: l10n.t('common.delete'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline, size: 19),
                onPressed: _steps.length <= 1 ? null : () => _removeStep(i),
              ),
            ],
          ),
          _connectionOverview(d),
          _sectionHeader(l10n.t('flows.secIdentity')),
          LabeledDropdown(
            label: l10n.t('flows.fKind'),
            value: d.kind.code,
            options: FlowStepKind.values.map((k) => k.code).toList(),
            labelOf: (c) => kindLabel(FlowStepKind.parse(c)),
            onChanged: (v) {
              final kind = FlowStepKind.parse(v);
              if (kind == FlowStepKind.orchestrator &&
                  orch != null &&
                  orch != d) {
                showSnack(context, l10n.t('flows.onlyOneOrchestrator'));
                return;
              }
              setState(() => d.kind = kind);
            },
          ),
          FieldRow(
            l10n.t('flows.fStepKey'),
            d.key,
            description: l10n.t('flows.fStepKeyDesc'),
            hint: 'dev',
          ),
          FieldRow(l10n.t('flows.fStepName'), d.name),
          if (orch == null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                l10n.t('flows.setEntry'),
                style: const TextStyle(fontSize: 13.5),
              ),
              value: identical(d, _startDraft),
              onChanged: (v) {
                if (v) setState(() => _entry = d);
              },
            ),
          if (isAgent) ...[
            _sectionHeader(l10n.t('flows.secAgent')),
            LabeledDropdown(
              label: l10n.t('flows.fAgent'),
              value: d.agent,
              options: agentIds,
              labelOf: agentLabel,
              onChanged: (v) => setState(() {
                d.agent = v;
                // A model id from another agent is meaningless — reset both.
                if (!modelOptions(v).contains(d.model.text)) {
                  d.model.text = '';
                }
                if (!effortOptions(v).contains(d.effort)) d.effort = '';
              }),
            ),
            _modelField(d),
            if (effortOptions(d.agent).isNotEmpty)
              LabeledDropdown(
                label: l10n.t('flows.fEffort'),
                value: effortOptions(d.agent).contains(d.effort)
                    ? d.effort
                    : '',
                options: ['', ...effortOptions(d.agent)],
                labelOf: (v) =>
                    v.isEmpty ? l10n.t('flows.modelDefault') : effortLabel(v),
                onChanged: (v) => setState(() => d.effort = v),
              ),
            if (effortOptions(d.agent).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 8),
                child: Text(
                  l10n.t('flows.fEffortDesc.${d.agent}'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            _agentHealthRow(d.agent),
            FieldRow(
              l10n.t('flows.fRole'),
              d.role,
              description: l10n.t('flows.fRoleDesc'),
              hint: 'implementer',
            ),
            FieldRow(
              l10n.t('flows.fPrompt'),
              d.prompt,
              maxLines: 5,
              description: l10n.t('flows.fPromptDesc'),
              expandable: true,
            ),
            _skillsField(d),
            FieldRow(
              l10n.t('flows.fTags'),
              d.tags,
              description: l10n.t('flows.fTagsDesc'),
              hint: 'review, security',
            ),
          ],
          if (d.kind == FlowStepKind.subflow) ...[
            _sectionHeader(l10n.t('flows.secSubflow')),
            LabeledDropdown(
              label: l10n.t('flows.fSubflow'),
              value: d.subflowKey,
              options: [
                '',
                ..._availableFlows.map((f) => f.key),
                // Keep a stale target visible instead of crashing the dropdown.
                if (d.subflowKey.isNotEmpty &&
                    !_availableFlows.any((f) => f.key == d.subflowKey))
                  d.subflowKey,
              ],
              labelOf: (c) => c.isEmpty
                  ? l10n.t('flows.fSubflowNone')
                  : _availableFlows
                            .where((f) => f.key == c)
                            .map((f) => '${f.name.value} ($c)')
                            .firstOrNull ??
                        c,
              onChanged: (v) => setState(() => d.subflowKey = v),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                l10n.t('flows.fSubflowDesc'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          if (isAgent ||
              d.kind == FlowStepKind.command ||
              d.kind == FlowStepKind.rfcGate ||
              d.kind == FlowStepKind.subflow)
            _sectionHeader(l10n.t('flows.secExecution')),
          if (isAgent) ...[
            FieldRow(
              l10n.t('flows.fExit'),
              d.exit,
              description: l10n.t('flows.fExitDesc'),
              hint: 'dart analyze, dart test',
              expandable: true,
            ),
            FieldRow(l10n.t('flows.fMaxIter'), d.maxIter),
            FieldRow(
              l10n.t('flows.fTimeout'),
              d.timeout,
              description: l10n.t('flows.fTimeoutDesc'),
            ),
            FieldRow(
              l10n.t('flows.fTokenBudget'),
              d.tokenBudget,
              description: l10n.t('flows.fTokenBudgetDesc'),
            ),
            FieldRow(
              l10n.t('flows.fVerifierTimeout'),
              d.verifierTimeout,
              description: l10n.t('flows.fVerifierTimeoutDesc'),
            ),
            FieldRow(
              l10n.t('flows.fOutputSchema'),
              d.outputSchema,
              maxLines: 4,
              description: l10n.t('flows.fOutputSchemaDesc'),
              hint: '{"type":"object","required":["result"]}',
              expandable: true,
            ),
            FieldRow(
              l10n.t('flows.fPermissions'),
              d.permissions,
              maxLines: 4,
              description: l10n.t('flows.fPermissionsDesc'),
              expandable: true,
            ),
          ],
          if (d.kind == FlowStepKind.command)
            FieldRow(
              l10n.t('flows.fCommand'),
              d.command,
              description: l10n.t('flows.fCommandDesc'),
              hint: 'dart test',
              expandable: true,
            ),
          if (d.kind == FlowStepKind.rfcGate)
            FieldRow(
              l10n.t('flows.fMaxRounds'),
              d.maxRounds,
              description: l10n.t('flows.fMaxRoundsDesc'),
              hint: '3',
            ),
          if (d.kind != FlowStepKind.humanGate &&
              d.kind != FlowStepKind.rfcGate &&
              d.kind != FlowStepKind.join)
            LabeledDropdown(
              label: l10n.t('flows.fOnFail'),
              value: d.onFail,
              options: onFailOptions,
              labelOf: onFailLabel,
              onChanged: (v) => setState(() => d.onFail = v),
            ),
        ],
      ),
    );
  }

  Widget _connectionOverview(StepDraft step) {
    final incoming = _edges.where((e) => identical(e.to, step)).toList();
    final outgoing = _edges.where((e) => identical(e.from, step)).toList();
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
      decoration: BoxDecoration(
        color: OracleBrand.gray950.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: OracleBrand.gray700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_tree_outlined, size: 15),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  l10n.t('flows.connections'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${incoming.length} → ${outgoing.length}',
                style: const TextStyle(
                  fontSize: 11,
                  color: OracleBrand.gray500,
                ),
              ),
            ],
          ),
          if (incoming.isEmpty && outgoing.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 7, 4, 5),
              child: Text(
                l10n.t('flows.noEdges'),
                style: const TextStyle(
                  fontSize: 11.5,
                  color: OracleBrand.gray500,
                ),
              ),
            ),
          for (final edge in incoming)
            _connectionRow(
              edge,
              peer: edge.from,
              icon: Icons.call_received,
              prefix: l10n.t('flows.from'),
            ),
          for (final edge in outgoing)
            _connectionRow(
              edge,
              peer: edge.to,
              icon: Icons.call_made,
              prefix: l10n.t('flows.to'),
            ),
        ],
      ),
    );
  }

  Widget _connectionRow(
    EdgeDraft edge, {
    required StepDraft peer,
    required IconData icon,
    required String prefix,
  }) {
    final color = _CanvasPainter.edgeColor(edge.condition);
    final condition =
        edge.condition == 'verdict' && edge.verdict.text.trim().isNotEmpty
        ? edge.verdict.text.trim()
        : conditionLabel(edge.condition);
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: () {
        final index = _steps.indexOf(peer);
        if (index >= 0) setState(() => _selected = index);
      },
      child: Padding(
        padding: const EdgeInsets.only(left: 2, top: 6, bottom: 2),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 7),
            Text(
              '$prefix ',
              style: const TextStyle(fontSize: 11, color: OracleBrand.gray500),
            ),
            Expanded(
              child: Text(
                peer.key.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              constraints: const BoxConstraints(maxWidth: 92),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                condition,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 9.5, color: color),
              ),
            ),
            IconButton(
              tooltip: l10n.t('flows.editConnection'),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 30, height: 28),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.edit_outlined, size: 14),
              onPressed: () => _editEdge(edge),
            ),
          ],
        ),
      ),
    );
  }

  /// Live agent diagnostics: is the flow going to work with this agent?
  /// (CLI on PATH + Oracle MCP = it runs; hooks/receiver = capture too.)
  Widget _agentHealthRow(String agent) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: FutureBuilder<server.AgentHealth>(
        future: _healthOf(agent),
        builder: (context, snapshot) {
          final h = snapshot.data;
          final Color color;
          final IconData icon;
          final String label;
          if (h == null) {
            color = OracleBrand.gray500;
            icon = Icons.hourglass_empty;
            label = l10n.t('flows.health.checking');
          } else if (h.fullyWired) {
            color = OracleBrand.success;
            icon = Icons.verified_outlined;
            label = l10n.t('flows.health.ready');
          } else if (h.ready) {
            color = OracleBrand.warning;
            icon = Icons.check_circle_outline;
            label = l10n.t('flows.health.warn');
          } else {
            color = OracleBrand.error;
            icon = Icons.error_outline;
            label = l10n.t('flows.health.fail');
          }
          return InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: h == null ? null : () => _showHealthDialog(agent),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (h != null)
                    Text(
                      l10n.t('flows.health.details'),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: OracleBrand.gray400,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showHealthDialog(String agent) async {
    server.AgentCheck? smoke;
    var smoking = false;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          title: Text('${l10n.t('flows.health.title')} — ${agentLabel(agent)}'),
          content: SizedBox(
            width: 520,
            child: FutureBuilder<server.AgentHealth>(
              future: _healthOf(agent),
              builder: (context, snapshot) {
                final h = snapshot.data;
                if (h == null) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _healthLine(
                      l10n.t('flows.health.cli'),
                      h.cli,
                      fix: l10n.t('flows.health.cliFix'),
                      required_: true,
                    ),
                    _healthLine(
                      l10n.t('flows.health.mcp'),
                      h.mcp,
                      fix: l10n.t('flows.health.mcpFix'),
                      required_: true,
                    ),
                    _healthLine(
                      l10n.t('flows.health.hooks'),
                      h.hooks,
                      fix: l10n.t('flows.health.hooksFix'),
                    ),
                    _healthLine(
                      l10n.t('flows.health.receiver'),
                      h.receiver,
                      fix: l10n.t('flows.health.receiverFix'),
                    ),
                    _healthLine(
                      l10n.t('flows.health.sandbox'),
                      h.sandbox,
                      fix: l10n.t('flows.health.sandboxFix'),
                    ),
                    if (smoke != null) ...[
                      const Divider(height: 22),
                      _healthLine(
                        smoke!.ok
                            ? l10n.t('flows.health.smokeOk')
                            : l10n.t('flows.health.smokeFail'),
                        smoke!,
                        required_: true,
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                _health.remove(agent);
                setDlg(() {});
                setState(() {});
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(l10n.t('flows.health.recheck')),
            ),
            OutlinedButton.icon(
              onPressed: smoking
                  ? null
                  : () async {
                      setDlg(() => smoking = true);
                      final result = await _doctor.smokeTest(agent);
                      setDlg(() {
                        smoking = false;
                        smoke = result;
                      });
                    },
              icon: smoking
                  ? const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow, size: 16),
              label: Text(
                smoking
                    ? l10n.t('flows.health.smokeRunning')
                    : l10n.t('flows.health.smoke'),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.t('common.close')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _healthLine(
    String label,
    server.AgentCheck check, {
    String? fix,
    bool required_ = false,
  }) {
    final color = check.ok
        ? OracleBrand.success
        : (required_ ? OracleBrand.error : OracleBrand.warning);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            check.ok ? Icons.check_circle : Icons.cancel_outlined,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  check.detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: OracleBrand.gray500,
                  ),
                ),
                if (!check.ok && fix != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      fix,
                      style: TextStyle(fontSize: 11.5, color: color),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 12),
    child: Row(
      children: [
        Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 10.5,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
            color: OracleBrand.gray500,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(child: Divider(height: 1)),
      ],
    ),
  );

  /// Skills picker: chips of the step's skills + a button that lists the skills
  /// REGISTERED in Oracle for this scope — no typing skill keys by hand.
  Widget _skillsField(StepDraft d) {
    final known = {for (final s in _availableSkills) s.key: s};
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.t('flows.fSkills'),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.t('flows.fSkillsDesc'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final key in d.skillKeys)
                InputChip(
                  label: Text(
                    known[key]?.name.value ?? key,
                    style: const TextStyle(fontSize: 12),
                  ),
                  tooltip: key,
                  visualDensity: VisualDensity.compact,
                  onDeleted: () => setState(() => d.skillKeys.remove(key)),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: Text(
                  l10n.t('flows.addSkill'),
                  style: const TextStyle(fontSize: 12),
                ),
                visualDensity: VisualDensity.compact,
                onPressed: () => _pickSkillsFor(d),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Model: an EDITABLE field with per-agent suggestions — model catalogs
  /// change monthly, so the list is a hint, never a cage. Empty = CLI default.
  Widget _modelField(StepDraft d) {
    final options = modelOptions(d.agent);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: FieldRow(
            l10n.t('flows.fModel'),
            d.model,
            description: l10n.t('flows.fModelDesc.${d.agent}'),
            hint: l10n.t('flows.modelDefault'),
          ),
        ),
        if (options.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: PopupMenuButton<String>(
              tooltip: l10n.t('flows.modelSuggestions'),
              icon: const Icon(
                Icons.expand_circle_down_outlined,
                size: 18,
                color: OracleBrand.gray400,
              ),
              color: OracleBrand.gray900,
              itemBuilder: (context) => [
                for (final m in options)
                  PopupMenuItem(
                    value: m,
                    height: 36,
                    child: Text(m, style: const TextStyle(fontSize: 12.5)),
                  ),
              ],
              onSelected: (m) => setState(() => d.model.text = m),
            ),
          ),
      ],
    );
  }

  Future<void> _pickSkillsFor(StepDraft d) async {
    if (_availableSkills.isEmpty) {
      showSnack(context, l10n.t('flows.noRegisteredSkills'));
      return;
    }
    final selected = {...d.skillKeys};
    final filter = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlg) {
          final q = filter.text.trim().toLowerCase();
          final visible = _availableSkills
              .where(
                (s) =>
                    q.isEmpty ||
                    s.key.toLowerCase().contains(q) ||
                    s.name.value.toLowerCase().contains(q) ||
                    s.description.value.toLowerCase().contains(q),
              )
              .toList();
          return AlertDialog(
            title: Text(l10n.t('flows.pickSkills')),
            content: SizedBox(
              width: 480,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    controller: filter,
                    onChanged: (_) => setDlg(() {}),
                    decoration: InputDecoration(
                      hintText: l10n.t('flows.searchSkill'),
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final s in visible)
                          CheckboxListTile(
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: selected.contains(s.key),
                            title: Text(
                              s.name.value,
                              style: const TextStyle(fontSize: 13.5),
                            ),
                            subtitle: Text(
                              s.description.value.isEmpty
                                  ? s.key
                                  : s.description.value,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: OracleBrand.gray500,
                              ),
                            ),
                            onChanged: (v) => setDlg(() {
                              if (v == true) {
                                selected.add(s.key);
                              } else {
                                selected.remove(s.key);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.t('common.cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.t('common.save')),
              ),
            ],
          );
        },
      ),
    );
    if (ok == true && mounted) {
      setState(() {
        // Keep the original order; append newly picked ones.
        d.skillKeys
          ..removeWhere((k) => !selected.contains(k))
          ..addAll(selected.where((k) => !d.skillKeys.contains(k)));
      });
    }
  }

  static String _budgetOf(String? budgetsJson) {
    if (budgetsJson == null) return '';
    try {
      final j = jsonDecode(budgetsJson);
      if (j is Map && j['maxTotalTokens'] is num) {
        return (j['maxTotalTokens'] as num).toInt().toString();
      }
    } catch (_) {
      /* none */
    }
    return '';
  }

  static String _budgetJson(String raw) {
    final n = int.tryParse(raw.trim());
    return n == null || n <= 0 ? '{}' : jsonEncode({'maxTotalTokens': n});
  }
}

enum _PortSide { left, right, top, bottom }

class _EdgeRoute {
  final List<Offset> points;
  final Offset label;
  const _EdgeRoute(this.points, this.label);
}

/// Obstacle-aware orthogonal routing. Each connection picks the shortest
/// candidate that does not cross a node, and already placed routes are used as
/// a soft penalty so parallel branches naturally fan out into separate lanes.
class _EdgeRouter {
  static const _clearance = 22.0;
  static const _stub = 24.0;

  static Map<EdgeDraft, _EdgeRoute> routeAll(
    List<EdgeDraft> edges,
    List<StepDraft> steps,
  ) {
    final sides = <EdgeDraft, (_PortSide, _PortSide)>{};
    for (final edge in edges) {
      final a = Offset(edge.from.x + _nodeW / 2, edge.from.y + _nodeH / 2);
      final b = Offset(edge.to.x + _nodeW / 2, edge.to.y + _nodeH / 2);
      final dx = b.dx - a.dx;
      final dy = b.dy - a.dy;
      if (dx.abs() >= dy.abs() * .8) {
        sides[edge] = dx >= 0
            ? (_PortSide.right, _PortSide.left)
            : (_PortSide.left, _PortSide.right);
      } else {
        sides[edge] = dy >= 0
            ? (_PortSide.bottom, _PortSide.top)
            : (_PortSide.top, _PortSide.bottom);
      }
    }

    final sourceGroups = <(StepDraft, _PortSide), List<EdgeDraft>>{};
    final targetGroups = <(StepDraft, _PortSide), List<EdgeDraft>>{};
    for (final edge in edges) {
      final pair = sides[edge]!;
      sourceGroups.putIfAbsent((edge.from, pair.$1), () => []).add(edge);
      targetGroups.putIfAbsent((edge.to, pair.$2), () => []).add(edge);
    }
    for (final group in [...sourceGroups.values, ...targetGroups.values]) {
      group.sort((a, b) {
        final ac = Offset(a.to.x + _nodeW / 2, a.to.y + _nodeH / 2);
        final bc = Offset(b.to.x + _nodeW / 2, b.to.y + _nodeH / 2);
        return ac.dy == bc.dy ? ac.dx.compareTo(bc.dx) : ac.dy.compareTo(bc.dy);
      });
    }

    final result = <EdgeDraft, _EdgeRoute>{};
    final placed = <(Offset, Offset)>[];
    for (var ordinal = 0; ordinal < edges.length; ordinal++) {
      final edge = edges[ordinal];
      final pair = sides[edge]!;
      final sourceGroup = sourceGroups[(edge.from, pair.$1)]!;
      final targetGroup = targetGroups[(edge.to, pair.$2)]!;
      final p0 = _anchor(
        edge.from,
        pair.$1,
        sourceGroup.indexOf(edge),
        sourceGroup.length,
      );
      final p3 = _anchor(
        edge.to,
        pair.$2,
        targetGroup.indexOf(edge),
        targetGroup.length,
      );
      final route = _bestRoute(
        p0,
        p3,
        pair.$1,
        pair.$2,
        steps
            .where((s) => !identical(s, edge.from) && !identical(s, edge.to))
            .toList(),
        placed,
        ordinal,
      );
      result[edge] = route;
      for (var i = 0; i < route.points.length - 1; i++) {
        placed.add((route.points[i], route.points[i + 1]));
      }
    }
    return result;
  }

  static Offset _anchor(StepDraft node, _PortSide side, int index, int count) {
    final horizontal = side == _PortSide.top || side == _PortSide.bottom;
    final span = (horizontal ? _nodeW : _nodeH) - 28;
    final gap = count <= 1 ? 0.0 : (span / (count - 1)).clamp(0.0, 18.0);
    final shift = (index - (count - 1) / 2) * gap;
    return switch (side) {
      _PortSide.left => Offset(node.x, node.y + _nodeH / 2 + shift),
      _PortSide.right => Offset(node.x + _nodeW, node.y + _nodeH / 2 + shift),
      _PortSide.top => Offset(node.x + _nodeW / 2 + shift, node.y),
      _PortSide.bottom => Offset(node.x + _nodeW / 2 + shift, node.y + _nodeH),
    };
  }

  static Offset _unit(_PortSide side) => switch (side) {
    _PortSide.left => const Offset(-1, 0),
    _PortSide.right => const Offset(1, 0),
    _PortSide.top => const Offset(0, -1),
    _PortSide.bottom => const Offset(0, 1),
  };

  static _EdgeRoute _bestRoute(
    Offset p0,
    Offset p3,
    _PortSide sourceSide,
    _PortSide targetSide,
    List<StepDraft> obstacles,
    List<(Offset, Offset)> placed,
    int ordinal,
  ) {
    final s = p0 + _unit(sourceSide) * _stub;
    final t = p3 + _unit(targetSide) * _stub;
    final candidates = <List<Offset>>[];
    final horizontal =
        sourceSide == _PortSide.left || sourceSide == _PortSide.right;
    final laneNudge = (ordinal % 5 - 2) * 8.0;

    if (horizontal) {
      final middleX = (s.dx + t.dx) / 2 + laneNudge;
      candidates.add([
        p0,
        s,
        Offset(middleX, s.dy),
        Offset(middleX, t.dy),
        t,
        p3,
      ]);
      for (final x in [
        s.dx < t.dx ? s.dx + _clearance : s.dx - _clearance,
        s.dx < t.dx ? t.dx - _clearance : t.dx + _clearance,
        s.dx < t.dx ? s.dx - 48 - laneNudge.abs() : t.dx - 48 - laneNudge.abs(),
        s.dx > t.dx ? s.dx + 48 + laneNudge.abs() : t.dx + 48 + laneNudge.abs(),
      ]) {
        candidates.add([p0, s, Offset(x, s.dy), Offset(x, t.dy), t, p3]);
      }
      final top =
          obstacles.fold(
            p0.dy < p3.dy ? p0.dy : p3.dy,
            (v, n) => v < n.y ? v : n.y,
          ) -
          48 -
          laneNudge.abs();
      final bottom =
          obstacles.fold(
            p0.dy > p3.dy ? p0.dy : p3.dy,
            (v, n) => v > n.y + _nodeH ? v : n.y + _nodeH,
          ) +
          48 +
          laneNudge.abs();
      candidates.add([p0, s, Offset(s.dx, top), Offset(t.dx, top), t, p3]);
      candidates.add([
        p0,
        s,
        Offset(s.dx, bottom),
        Offset(t.dx, bottom),
        t,
        p3,
      ]);
    } else {
      final middleY = (s.dy + t.dy) / 2 + laneNudge;
      candidates.add([
        p0,
        s,
        Offset(s.dx, middleY),
        Offset(t.dx, middleY),
        t,
        p3,
      ]);
      for (final y in [
        s.dy < t.dy ? s.dy + _clearance : s.dy - _clearance,
        s.dy < t.dy ? t.dy - _clearance : t.dy + _clearance,
      ]) {
        candidates.add([p0, s, Offset(s.dx, y), Offset(t.dx, y), t, p3]);
      }
      final left =
          obstacles.fold(
            p0.dx < p3.dx ? p0.dx : p3.dx,
            (v, n) => v < n.x ? v : n.x,
          ) -
          48 -
          laneNudge.abs();
      final right =
          obstacles.fold(
            p0.dx > p3.dx ? p0.dx : p3.dx,
            (v, n) => v > n.x + _nodeW ? v : n.x + _nodeW,
          ) +
          48 +
          laneNudge.abs();
      candidates.add([p0, s, Offset(left, s.dy), Offset(left, t.dy), t, p3]);
      candidates.add([p0, s, Offset(right, s.dy), Offset(right, t.dy), t, p3]);
    }

    List<Offset>? best;
    var bestScore = double.infinity;
    for (final raw in candidates) {
      final points = _simplify(raw);
      var score = (points.length - 2) * 18.0;
      for (var i = 0; i < points.length - 1; i++) {
        final a = points[i];
        final b = points[i + 1];
        score += (b - a).distance;
        for (final node in obstacles) {
          final rect = Rect.fromLTWH(
            node.x,
            node.y,
            _nodeW,
            _nodeH,
          ).inflate(14);
          if (_segmentHitsRect(a, b, rect)) score += 100000;
        }
        for (final old in placed) {
          if (_segmentsCross(a, b, old.$1, old.$2)) score += 650;
          if (_segmentsOverlap(a, b, old.$1, old.$2)) score += 1100;
        }
      }
      if (score < bestScore) {
        bestScore = score;
        best = points;
      }
    }
    final points = best!;
    var longest = -1.0;
    var label = (p0 + p3) / 2;
    for (var i = 1; i < points.length - 2; i++) {
      final length = (points[i + 1] - points[i]).distance;
      if (length > longest) {
        longest = length;
        label = (points[i] + points[i + 1]) / 2;
      }
    }
    return _EdgeRoute(points, label);
  }

  static List<Offset> _simplify(List<Offset> input) {
    final result = <Offset>[];
    for (final point in input) {
      if (result.isNotEmpty && (result.last - point).distance < .5) continue;
      if (result.length >= 2) {
        final a = result[result.length - 2];
        final b = result.last;
        final sameX = (a.dx - b.dx).abs() < .5 && (b.dx - point.dx).abs() < .5;
        final sameY = (a.dy - b.dy).abs() < .5 && (b.dy - point.dy).abs() < .5;
        if (sameX || sameY) result.removeLast();
      }
      result.add(point);
    }
    return result;
  }

  static bool _segmentHitsRect(Offset a, Offset b, Rect r) {
    if ((a.dx - b.dx).abs() < .5) {
      return a.dx > r.left &&
          a.dx < r.right &&
          (a.dy < b.dy ? a.dy : b.dy) < r.bottom &&
          (a.dy > b.dy ? a.dy : b.dy) > r.top;
    }
    return a.dy > r.top &&
        a.dy < r.bottom &&
        (a.dx < b.dx ? a.dx : b.dx) < r.right &&
        (a.dx > b.dx ? a.dx : b.dx) > r.left;
  }

  static bool _segmentsCross(Offset a, Offset b, Offset c, Offset d) {
    final abVertical = (a.dx - b.dx).abs() < .5;
    final cdVertical = (c.dx - d.dx).abs() < .5;
    if (abVertical == cdVertical) return false;
    final v1 = abVertical ? a : c;
    final v2 = abVertical ? b : d;
    final h1 = abVertical ? c : a;
    final h2 = abVertical ? d : b;
    final minV = v1.dy < v2.dy ? v1.dy : v2.dy;
    final maxV = v1.dy > v2.dy ? v1.dy : v2.dy;
    final minH = h1.dx < h2.dx ? h1.dx : h2.dx;
    final maxH = h1.dx > h2.dx ? h1.dx : h2.dx;
    return v1.dx > minH && v1.dx < maxH && h1.dy > minV && h1.dy < maxV;
  }

  static bool _segmentsOverlap(Offset a, Offset b, Offset c, Offset d) {
    final abVertical = (a.dx - b.dx).abs() < .5;
    final cdVertical = (c.dx - d.dx).abs() < .5;
    if (abVertical != cdVertical) return false;
    if (abVertical) {
      if ((a.dx - c.dx).abs() > 2) return false;
      final a1 = a.dy < b.dy ? a.dy : b.dy;
      final a2 = a.dy > b.dy ? a.dy : b.dy;
      final c1 = c.dy < d.dy ? c.dy : d.dy;
      final c2 = c.dy > d.dy ? c.dy : d.dy;
      return a1 < c2 && c1 < a2;
    }
    if ((a.dy - c.dy).abs() > 2) return false;
    final a1 = a.dx < b.dx ? a.dx : b.dx;
    final a2 = a.dx > b.dx ? a.dx : b.dx;
    final c1 = c.dx < d.dx ? c.dx : d.dx;
    final c2 = c.dx > d.dx ? c.dx : d.dx;
    return a1 < c2 && c1 < a2;
  }
}

/// Dotted grid + rounded orthogonal edges with directional arrowheads.
class _CanvasPainter extends CustomPainter {
  final List<EdgeDraft> edges;
  final Map<EdgeDraft, _EdgeRoute> routes;
  final StepDraft? hoveredNode;
  final EdgeDraft? hoveredEdge;
  final StepDraft? previewFrom;
  final Offset? previewTo;
  _CanvasPainter({
    required this.edges,
    required this.routes,
    this.hoveredNode,
    this.hoveredEdge,
    this.previewFrom,
    this.previewTo,
  });

  static Color edgeColor(String condition) => switch (condition) {
    'failure' => OracleBrand.error,
    'verdict' => OracleBrand.warning,
    'always' => OracleBrand.blue,
    _ => OracleBrand.gray500,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = OracleBrand.gray800;
    for (var x = 0.0; x < size.width; x += _gridSize) {
      for (var y = 0.0; y < size.height; y += _gridSize) {
        canvas.drawCircle(Offset(x, y), 1, grid);
      }
    }

    final focusActive = hoveredNode != null || hoveredEdge != null;
    final ordered = [...edges]
      ..sort((a, b) {
        final ah = _isEmphasized(a);
        final bh = _isEmphasized(b);
        return ah == bh ? 0 : (ah ? 1 : -1);
      });
    for (final edge in ordered) {
      final emphasized = _isEmphasized(edge);
      _drawEdge(
        canvas,
        routes[edge]!.points,
        edgeColor(edge.condition),
        arrow: true,
        alpha: !focusActive || emphasized ? 1 : .16,
        width: emphasized ? 3.4 : 2,
        glow: emphasized,
      );
    }

    final from = previewFrom;
    final to = previewTo;
    if (from != null && to != null) {
      final start = Offset(from.x + _nodeW, from.y + _nodeH / 2);
      final midX = (start.dx + to.dx) / 2;
      _drawEdge(
        canvas,
        [start, Offset(midX, start.dy), Offset(midX, to.dy), to],
        OracleBrand.violetSoft,
        arrow: false,
        dashed: true,
      );
      canvas.drawCircle(to, 4, Paint()..color = OracleBrand.violetSoft);
    }
  }

  bool _isEmphasized(EdgeDraft edge) =>
      identical(edge, hoveredEdge) ||
      (hoveredNode != null &&
          (identical(edge.from, hoveredNode) ||
              identical(edge.to, hoveredNode)));

  void _drawEdge(
    Canvas canvas,
    List<Offset> points,
    Color color, {
    required bool arrow,
    bool dashed = false,
    double alpha = 1,
    double width = 2,
    bool glow = false,
  }) {
    final path = _roundedPath(points);
    if (glow) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: .22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 11
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = OracleBrand.gray950.withValues(alpha: .92 * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width + 4
        ..strokeCap = StrokeCap.round,
    );
    final paint = Paint()
      ..color = color.withValues(alpha: 0.92 * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (dashed) {
      _drawDashed(canvas, points, paint);
    } else {
      canvas.drawPath(path, paint);
    }

    if (arrow && points.length >= 2) {
      final tip = points.last;
      final previous = points[points.length - 2];
      final delta = tip - previous;
      if (delta.distance > 0) {
        final direction = delta / delta.distance;
        final normal = Offset(-direction.dy, direction.dx);
        final base = tip - direction * 10;
        final arrowPath = Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo((base + normal * 5).dx, (base + normal * 5).dy)
          ..lineTo((base - normal * 5).dx, (base - normal * 5).dy)
          ..close();
        canvas.drawPath(
          arrowPath,
          Paint()..color = color.withValues(alpha: alpha),
        );
      }
    }
    canvas.drawCircle(
      points.first,
      emphasizedRadius(width),
      Paint()..color = color.withValues(alpha: alpha),
    );
  }

  double emphasizedRadius(double width) => width > 2 ? 4 : 3;

  Path _roundedPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length - 1; i++) {
      final previous = points[i - 1];
      final corner = points[i];
      final next = points[i + 1];
      final inDistance = (corner - previous).distance;
      final outDistance = (next - corner).distance;
      final radius = (inDistance < outDistance ? inDistance : outDistance)
          .clamp(0.0, 9.0);
      if (radius < 1) {
        path.lineTo(corner.dx, corner.dy);
        continue;
      }
      final before = corner + (previous - corner) / inDistance * radius;
      final after = corner + (next - corner) / outDistance * radius;
      path.lineTo(before.dx, before.dy);
      path.quadraticBezierTo(corner.dx, corner.dy, after.dx, after.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  void _drawDashed(Canvas canvas, List<Offset> points, Paint paint) {
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final delta = points[i + 1] - a;
      final length = delta.distance;
      if (length == 0) continue;
      final unit = delta / length;
      for (var cursor = 0.0; cursor < length; cursor += 12) {
        canvas.drawLine(
          a + unit * cursor,
          a + unit * (cursor + 7).clamp(0, length),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter old) => true;
}

/// The n8n-style "what node?" picker: the 5 executor kinds + ready-made AGENT
/// presets (they are agent steps with a role/prompt prefilled). Returns a
/// factory that builds the new draft.
Future<StepDraft Function()?> _pickStep(
  BuildContext context, {
  required bool orchestratorTaken,
}) {
  return showDialog<StepDraft Function()?>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(l10n.t('flows.pickKind')),
      children: [
        for (final k in FlowStepKind.values)
          if (k != FlowStepKind.orchestrator || !orchestratorTaken)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(
                context,
                () => StepDraft.of(key: _suggestedKey(k), kind: k),
              ),
              child: _pickRow(
                kindIcon(k),
                kindColor(k),
                kindLabel(k),
                kindDescription(k),
              ),
            ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 6),
          child: Text(
            l10n.t('flows.presets'),
            style: const TextStyle(fontSize: 12, color: OracleBrand.gray400),
          ),
        ),
        for (final p in _agentPresets)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(
              context,
              () => StepDraft.of(
                key: p.key,
                name: p.name,
                kind: FlowStepKind.agent,
                agent: p.agent,
                role: p.role,
                prompt: p.promptText,
              ),
            ),
            child: _pickRow(p.icon, OracleBrand.violet, p.name, p.description),
          ),
      ],
    ),
  );
}

String _suggestedKey(FlowStepKind k) => switch (k) {
  FlowStepKind.agent => 'dev',
  FlowStepKind.orchestrator => 'inicio',
  FlowStepKind.decision => 'decisao',
  FlowStepKind.subflow => 'sub-processo',
  FlowStepKind.join => 'juncao',
  FlowStepKind.rfcCreate => 'rfc',
  FlowStepKind.rfcReview => 'rfc-review',
  FlowStepKind.rfcConsolidate => 'consolidar',
  FlowStepKind.rfcGate => 'rodadas',
  FlowStepKind.command => 'cmd',
  FlowStepKind.humanGate => 'gate',
};

Widget _pickRow(IconData icon, Color color, String title, String description) {
  return Row(
    children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              description,
              style: const TextStyle(fontSize: 12, color: OracleBrand.gray400),
            ),
          ],
        ),
      ),
    ],
  );
}

/// A ready-made agent step. All user-facing text (name, description and the
/// step PROMPT itself) is localized via l10n keys derived from [key].
class _AgentPreset {
  final String key;
  final String agent;
  final String role;
  final IconData icon;
  const _AgentPreset(this.key, this.agent, this.role, this.icon);

  String get name => l10n.t('flows.preset.$key');
  String get description => l10n.t('flows.presetDesc.$key');
  String get promptText => l10n.t('flows.presetPrompt.$key');
}

const _agentPresets = <_AgentPreset>[
  _AgentPreset('dev', 'claude-code', 'implementer', Icons.code),
  _AgentPreset('review', 'claude-code', 'reviewer', Icons.rate_review_outlined),
  _AgentPreset('security', 'claude-code', 'security', Icons.security_outlined),
  _AgentPreset('tests', 'claude-code', 'qa', Icons.checklist_outlined),
  _AgentPreset('docs', 'codex', 'docs', Icons.description_outlined),
  _AgentPreset('pr', 'gemini', 'release', Icons.merge_type),
];

// ── drafts ──

/// Mutable editor state for one step (controllers keep the text stable across
/// rebuilds; enums are plain fields). [x],[y] are the canvas position, persisted
/// in the step's config; [skillKeys] are Oracle skill keys picked from the
/// registered library; [extraConfig] preserves config keys the editor doesn't
/// own.
class StepDraft {
  final TextEditingController key;
  final TextEditingController name;
  FlowStepKind kind;
  String agent;
  final TextEditingController model;
  final TextEditingController role;
  final TextEditingController prompt;
  final TextEditingController command;
  final TextEditingController exit;
  List<String> skillKeys;
  final TextEditingController maxIter;
  final TextEditingController timeout;
  final TextEditingController tokenBudget;
  final TextEditingController verifierTimeout;
  final TextEditingController outputSchema;
  final TextEditingController permissions;
  final TextEditingController maxRounds;

  /// Comma-separated tags forwarded to the agent as `/tag` slash-command lines
  /// at the top of the prompt (e.g. "review" → Claude Code's /review).
  final TextEditingController tags;

  /// Target process KEY for a subflow step (config.flowKey).
  String subflowKey = '';

  /// Reasoning-effort level (config.reasoningEffort) — translated to each
  /// CLI's own flag by the launcher. Empty = the agent's default.
  String effort = '';
  String onFail;
  double x;
  double y;
  Map<String, dynamic> extraConfig;

  StepDraft._({
    required this.key,
    required this.name,
    required this.kind,
    required this.agent,
    required this.model,
    required this.role,
    required this.prompt,
    required this.command,
    required this.exit,
    required this.skillKeys,
    required this.maxIter,
    required this.timeout,
    required this.tokenBudget,
    required this.verifierTimeout,
    required this.outputSchema,
    required this.permissions,
    required this.maxRounds,
    required this.tags,
    required this.onFail,
    this.x = 0,
    this.y = 0,
    Map<String, dynamic>? extraConfig,
  }) : extraConfig = extraConfig ?? {};

  factory StepDraft.of({
    required String key,
    String name = '',
    FlowStepKind kind = FlowStepKind.agent,
    String agent = 'claude-code',
    String role = '',
    String prompt = '',
    String exit = '',
    String maxIter = '3',
    String timeout = '',
    String onFail = 'park',
    double x = 0,
    double y = 0,
  }) => StepDraft._(
    key: TextEditingController(text: key),
    name: TextEditingController(text: name),
    kind: kind,
    agent: agent,
    model: TextEditingController(),
    role: TextEditingController(text: role),
    prompt: TextEditingController(text: prompt),
    command: TextEditingController(),
    exit: TextEditingController(text: exit),
    skillKeys: [],
    maxIter: TextEditingController(text: maxIter),
    timeout: TextEditingController(text: timeout),
    tokenBudget: TextEditingController(),
    verifierTimeout: TextEditingController(text: '15'),
    outputSchema: TextEditingController(),
    permissions: TextEditingController(
      text: '{"workspace":"write","shell":true,"mcp":true}',
    ),
    maxRounds: TextEditingController(text: '3'),
    tags: TextEditingController(),
    onFail: onFail,
    x: x,
    y: y,
  );

  factory StepDraft.fromEntity(FlowStepEntity s) {
    final config = _configMap(s.config);
    final ui = config['ui'];
    final d = StepDraft.of(
      key: s.stepKey,
      name: s.name,
      kind: s.kind,
      agent: s.agent ?? 'claude-code',
      role: s.role ?? '',
      prompt: s.promptTemplate,
      exit: _exitCommands(s.exitCriteria).join(', '),
      maxIter: '${s.maxIterations}',
      timeout: s.timeoutMinutes <= 0 ? '' : '${s.timeoutMinutes}',
      onFail: s.onFail,
      x: ui is Map ? ((ui['x'] as num?)?.toDouble() ?? 0) : 0,
      y: ui is Map ? ((ui['y'] as num?)?.toDouble() ?? 0) : 0,
    );
    d.command.text = s.command ?? '';
    d.model.text = s.model ?? '';
    d.tokenBudget.text = s.tokenBudget == null ? '' : '${s.tokenBudget}';
    d.outputSchema.text = s.outputSchema ?? '';
    d.permissions.text = s.permissions;
    if (config['verifierTimeoutMinutes'] is num) {
      d.verifierTimeout.text =
          '${(config['verifierTimeoutMinutes'] as num).toInt()}';
    }
    final skills = config['skills'];
    if (skills is List) {
      d.skillKeys = skills
          .map((e) => e.toString().trim())
          .where((k) => k.isNotEmpty)
          .toList();
    }
    if (config['maxRounds'] is num) {
      d.maxRounds.text = '${(config['maxRounds'] as num).toInt()}';
    }
    final tags = config['tags'];
    if (tags is List) {
      d.tags.text = tags.map((e) => e.toString().trim()).join(', ');
    }
    if (config['flowKey'] is String) {
      d.subflowKey = (config['flowKey'] as String).trim();
    }
    if (config['reasoningEffort'] is String) {
      d.effort = (config['reasoningEffort'] as String).trim();
    }
    d.extraConfig = Map<String, dynamic>.from(config)
      ..remove('ui')
      ..remove('skills')
      ..remove('maxRounds')
      ..remove('tags')
      ..remove('flowKey')
      ..remove('reasoningEffort');
    d.extraConfig.remove('verifierTimeoutMinutes');
    return d;
  }

  /// A deep copy with a fresh [newKey] (used by "duplicate").
  StepDraft duplicate(String newKey) {
    final d = StepDraft.of(
      key: newKey,
      name: name.text,
      kind: kind,
      agent: agent,
      role: role.text,
      prompt: prompt.text,
      exit: exit.text,
      maxIter: maxIter.text,
      timeout: timeout.text,
      onFail: onFail,
    );
    d.command.text = command.text;
    d.model.text = model.text;
    d.maxRounds.text = maxRounds.text;
    d.tags.text = tags.text;
    d.subflowKey = subflowKey;
    d.effort = effort;
    d.tokenBudget.text = tokenBudget.text;
    d.verifierTimeout.text = verifierTimeout.text;
    d.outputSchema.text = outputSchema.text;
    d.permissions.text = permissions.text;
    d.skillKeys = [...skillKeys];
    d.extraConfig = Map<String, dynamic>.from(extraConfig);
    return d;
  }

  FlowStepEntity toEntity(int position) {
    final isAgent =
        kind == FlowStepKind.agent ||
        kind == FlowStepKind.orchestrator ||
        kind == FlowStepKind.decision ||
        kind == FlowStepKind.rfcCreate ||
        kind == FlowStepKind.rfcReview ||
        kind == FlowStepKind.rfcConsolidate;
    final tagList = tags.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final config = <String, dynamic>{
      ...extraConfig,
      'ui': {'x': x.round(), 'y': y.round()},
      if (skillKeys.isNotEmpty) 'skills': skillKeys,
      if (kind == FlowStepKind.rfcGate)
        'maxRounds': int.tryParse(maxRounds.text.trim()) ?? 3,
      if (isAgent && tagList.isNotEmpty) 'tags': tagList,
      if (isAgent && effort.trim().isNotEmpty) 'reasoningEffort': effort.trim(),
      if (kind == FlowStepKind.subflow && subflowKey.isNotEmpty)
        'flowKey': subflowKey,
      if (int.tryParse(verifierTimeout.text.trim()) != null)
        'verifierTimeoutMinutes': int.parse(verifierTimeout.text.trim()),
    };
    return FlowStepEntity(
      id: const IdVO.empty(),
      flowId: const IdVO.empty(),
      stepKey: key.text.trim(),
      name: name.text.trim(),
      kind: kind,
      agent: isAgent ? agent : null,
      model: model.text.trim().isEmpty ? null : model.text.trim(),
      role: role.text.trim().isEmpty ? null : role.text.trim(),
      promptTemplate: prompt.text.trim(),
      command: command.text.trim().isEmpty ? null : command.text.trim(),
      exitCriteria: _exitJson(exit.text),
      outputSchema: outputSchema.text.trim().isEmpty
          ? null
          : outputSchema.text.trim(),
      permissions: permissions.text.trim().isEmpty
          ? '{}'
          : permissions.text.trim(),
      maxIterations: int.tryParse(maxIter.text.trim()) ?? 3,
      tokenBudget: int.tryParse(tokenBudget.text.trim()),
      timeoutMinutes: int.tryParse(timeout.text.trim()) ?? 0,
      onFail: onFail,
      config: jsonEncode(config),
      position: position,
    );
  }

  static Map<String, dynamic> _configMap(String configJson) {
    try {
      final j = jsonDecode(configJson);
      if (j is Map<String, dynamic>) return j;
    } catch (_) {
      /* none */
    }
    return {};
  }

  static String _exitJson(String raw) {
    final commands = raw
        .split(',')
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();
    return commands.isEmpty ? '{}' : jsonEncode({'commands': commands});
  }

  static List<String> _exitCommands(String exitCriteriaJson) {
    try {
      final j = jsonDecode(exitCriteriaJson);
      if (j is Map && j['commands'] is List) {
        return (j['commands'] as List).map((e) => e.toString()).toList();
      }
    } catch (_) {
      /* none */
    }
    return const [];
  }
}

/// A connection between two step DRAFTS — by OBJECT reference, so renaming a
/// step's key never orphans its connections.
class EdgeDraft {
  StepDraft from;
  StepDraft to;
  String condition = 'success';
  final TextEditingController verdict = TextEditingController();

  /// WHEN to take this route (verdict edges) — rendered into the source
  /// node's agent prompt, so any node can decide between its connections.
  final TextEditingController instruction = TextEditingController();
  EdgeDraft({required this.from, required this.to});
}

// ── small shared controls ──

/// A labeled dropdown showing FRIENDLY labels while storing the raw value.
/// Styled to match [FieldRow] (label + optional description above the input).
class LabeledDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final String Function(String) labelOf;
  final ValueChanged<String> onChanged;
  final String? description;
  final bool dense;
  const LabeledDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
    this.description,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final items = options.contains(value) ? options : [value, ...options];
    return Padding(
      padding: EdgeInsets.only(bottom: dense ? 8 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: dense
                ? const TextStyle(fontSize: 11, color: OracleBrand.gray400)
                : Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          if (description != null && !dense) ...[
            const SizedBox(height: 2),
            Text(description!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: value,
            isDense: true,
            decoration: const InputDecoration(isDense: true),
            items: [
              for (final o in items)
                DropdownMenuItem(value: o, child: Text(labelOf(o))),
            ],
            onChanged: (v) => onChanged(v ?? value),
          ),
        ],
      ),
    );
  }
}

class MetaChipSmall extends StatelessWidget {
  final String label;
  const MetaChipSmall(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: OracleBrand.gray800,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: OracleBrand.gray700),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, color: OracleBrand.gray400),
      ),
    );
  }
}
