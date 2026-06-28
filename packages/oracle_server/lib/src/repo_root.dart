import 'dart:io';

/// Canonicalizes an agent working directory to its **git repository root** so
/// that subdirectories and worktrees all map to one project (mirrors how Claude
/// Code's memdir scopes memory by canonical git root). Walks up from [cwd]
/// looking for a `.git` entry (a directory in a normal repo, a file in a
/// worktree). Falls back to [cwd] unchanged when no repository is found.
String repoRootOf(String cwd) {
  if (cwd.trim().isEmpty) return cwd;
  try {
    var dir = Directory(cwd);
    while (true) {
      final sep = Platform.pathSeparator;
      final asDir = Directory('${dir.path}$sep.git');
      final asFile = File('${dir.path}$sep.git');
      if (asDir.existsSync() || asFile.existsSync()) return dir.path;
      final parent = dir.parent;
      if (parent.path == dir.path) return cwd; // reached filesystem root
      dir = parent;
    }
  } catch (_) {
    return cwd;
  }
}
