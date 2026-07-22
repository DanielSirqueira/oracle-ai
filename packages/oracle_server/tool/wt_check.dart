import 'dart:io';

import 'package:oracle_server/src/repo_root.dart';

/// Sanity-checks worktree→main-repo resolution against real dirs (dev tool).
void main(List<String> args) {
  for (final p in args) {
    stderr.writeln('$p  ->  ${repoRootOf(p)}');
  }
  if (args.isEmpty) stderr.writeln('usage: dart run tool/wt_check.dart <dir>…');
}
