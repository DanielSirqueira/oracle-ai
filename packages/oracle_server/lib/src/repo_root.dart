import 'dart:io';

/// Canonicalizes an agent working directory to its **git repository root** so
/// that subdirectories and worktrees all map to one project (mirrors how Claude
/// Code's memdir scopes memory by canonical git root). Walks up from [cwd]
/// looking for a `.git` entry. A `.git` DIRECTORY is the main repo root; a
/// `.git` FILE marks a linked worktree — its `gitdir:` pointer
/// (`<main>/.git/worktrees/<name>`) is followed back to the MAIN repo, so a run
/// executing inside `.oracle-worktrees/<slug>` resolves to the project of the
/// original repository instead of registering the worktree as a new project.
/// Falls back to [cwd] unchanged when no repository is found.
String repoRootOf(String cwd) {
  if (cwd.trim().isEmpty) return cwd;
  try {
    var dir = Directory(cwd);
    while (true) {
      final sep = Platform.pathSeparator;
      final asDir = Directory('${dir.path}$sep.git');
      final asFile = File('${dir.path}$sep.git');
      if (asDir.existsSync()) return dir.path;
      if (asFile.existsSync()) {
        return _mainRepoOfWorktree(asFile, dir.path) ?? dir.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) return cwd; // reached filesystem root
      dir = parent;
    }
  } catch (_) {
    return cwd;
  }
}

/// Resolves a linked worktree's `.git` file (`gitdir: <path>`) to the MAIN
/// repository root. Only the `<main>/.git/worktrees/<name>` layout is mapped —
/// a submodule (`.git/modules/...`) is a different repository and keeps its own
/// root. Returns null when the pointer cannot be read or is not a worktree.
String? _mainRepoOfWorktree(File gitFile, String worktreeDir) {
  try {
    final match =
        RegExp(r'gitdir:\s*(.+)').firstMatch(gitFile.readAsStringSync());
    if (match == null) return null;
    var gitdir = match.group(1)!.trim().replaceAll(r'\', '/');
    final isAbsolute = RegExp(r'^([a-zA-Z]:/|/)').hasMatch(gitdir);
    if (!isAbsolute) {
      gitdir = '${worktreeDir.replaceAll(r'\', '/')}/$gitdir';
    }
    final idx = gitdir.lastIndexOf('/.git/worktrees/');
    if (idx <= 0) return null;
    final main = gitdir.substring(0, idx);
    return Directory(main).existsSync()
        ? main.replaceAll('/', Platform.pathSeparator)
        : null;
  } catch (_) {
    return null;
  }
}
