import 'dart:io';

/// Creates an isolated git worktree + branch per run, so parallel runs never
/// collide and the run's work is a reviewable branch. One writer per branch is
/// the whole conflict-prevention story (git is also the rollback).
class FlowWorkspace {
  /// A dedicated worktree under `<repoRoot>/.oracle-worktrees/`. Best-effort:
  /// throws [FlowWorkspaceException] when git is unavailable so the caller can
  /// fall back to running in place.
  Future<({String branch, String path})> create({
    required String repoRoot,
    required String runId,
    required String slug,
  }) async {
    final short = runId.length >= 8 ? runId.substring(0, 8) : runId;
    final branch = 'flow/$slug-$short';
    final path =
        '$repoRoot${Platform.pathSeparator}.oracle-worktrees'
        '${Platform.pathSeparator}$slug-$short';

    final result = await Process.run('git', [
      'worktree',
      'add',
      '-b',
      branch,
      path,
      'HEAD',
    ], workingDirectory: repoRoot);
    if (result.exitCode != 0) {
      throw FlowWorkspaceException(
        'git worktree add failed: ${result.stderr}'.trim(),
      );
    }
    _copyAgentConfigs(repoRoot, path);
    return (branch: branch, path: path);
  }

  /// Per-repo agent MCP configs the step CLIs auto-discover from their cwd.
  /// When gitignored they exist only in the main checkout — a fresh worktree
  /// would silently lack them and the step agent could never reach Oracle
  /// (the exact "PROTOCOLO NÃO CUMPRIDO" failure). Copied best-effort; a file
  /// already present in the worktree (tracked) is never overwritten.
  static const _agentConfigFiles = [
    '.mcp.json',
    '.gemini/settings.json',
    '.cursor/mcp.json',
    '.vscode/mcp.json',
  ];

  static void _copyAgentConfigs(String repoRoot, String worktreePath) {
    final sep = Platform.pathSeparator;
    for (final rel in _agentConfigFiles) {
      try {
        final relNative = rel.replaceAll('/', sep);
        final src = File('$repoRoot$sep$relNative');
        final dst = File('$worktreePath$sep$relNative');
        if (!src.existsSync() || dst.existsSync()) continue;
        dst.parent.createSync(recursive: true);
        src.copySync(dst.path);
      } catch (_) {
        /* best-effort — a broken copy must not fail the workspace */
      }
    }
  }

  /// Removes the worktree (used when a run is torn down). Best-effort.
  Future<void> remove({required String repoRoot, required String path}) async {
    await Process.run('git', [
      'worktree',
      'remove',
      '--force',
      path,
    ], workingDirectory: repoRoot);
  }
}

class FlowWorkspaceException implements Exception {
  final String message;
  FlowWorkspaceException(this.message);
  @override
  String toString() => 'FlowWorkspaceException: $message';
}
