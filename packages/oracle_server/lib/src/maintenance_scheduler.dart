import 'dart:async';
import 'dart:io';

import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';

/// Periodically runs the deterministic maintenance sweep (decay + dedup) while
/// the process is alive. Opt-in via a positive [interval].
///
/// In multi-agent stdio mode each process would schedule its own sweep; the
/// sweep is idempotent and bounded, but for a shared deployment prefer running
/// this in a single daemon. Default (interval <= 0) is off.
class MaintenanceScheduler {
  final Duration interval;
  final DecayPolicy policy;
  Timer? _timer;

  MaintenanceScheduler({required this.interval, this.policy = const DecayPolicy()});

  bool get enabled => interval > Duration.zero;

  void start() {
    if (!enabled || _timer != null) return;
    stderr.writeln('[oracle] maintenance scheduler every ${interval.inMinutes}min');
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  Future<void> _tick() async {
    final result = await injector.get<RunMaintenanceUsecase>()(policy);
    result.fold(
      (r) => stderr.writeln(
        '[oracle] scheduled maintenance: decayed=${r.decayedCount} deduped=${r.dedupedCount}',
      ),
      (f) => stderr.writeln('[oracle] scheduled maintenance FAILED: ${f.errorMessage}'),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
