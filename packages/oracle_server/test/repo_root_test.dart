import 'dart:io';

import 'package:oracle_server/src/repo_root.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String repo;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('oracle_repo_root_');
    repo = '${tmp.path}${Platform.pathSeparator}main-repo';
    await Directory(repo).create(recursive: true);
    Future<void> git(List<String> args, [String? cwd]) async {
      final r = await Process.run('git', args, workingDirectory: cwd ?? repo);
      if (r.exitCode != 0) throw StateError('git $args: ${r.stderr}');
    }

    await git(['init']);
    await git(['-c', 'user.email=t@t', '-c', 'user.name=t', 'commit',
        '--allow-empty', '-m', 'init']);
    await File('$repo${Platform.pathSeparator}README.md').writeAsString('x');
  });

  tearDownAll(() async {
    await tmp.delete(recursive: true);
  });

  test('main repo root resolves to itself', () {
    expect(repoRootOf(repo), repo);
  });

  test('subdirectory resolves to the repo root', () async {
    final sub = Directory('$repo${Platform.pathSeparator}a'
        '${Platform.pathSeparator}b');
    await sub.create(recursive: true);
    expect(repoRootOf(sub.path), repo);
  });

  test('linked worktree resolves to the MAIN repo root (not itself)', () async {
    final wt = '$repo${Platform.pathSeparator}.oracle-worktrees'
        '${Platform.pathSeparator}run-1234';
    final r = await Process.run(
        'git', ['worktree', 'add', '-b', 'flow/test-1234', wt, 'HEAD'],
        workingDirectory: repo);
    expect(r.exitCode, 0, reason: '${r.stderr}');

    expect(repoRootOf(wt), repo);

    // A subdirectory INSIDE the worktree also maps back to the main repo.
    final inner = Directory('$wt${Platform.pathSeparator}lib');
    await inner.create(recursive: true);
    expect(repoRootOf(inner.path), repo);
  });

  test('non-repo directory falls back to itself', () async {
    final plain = Directory('${tmp.path}${Platform.pathSeparator}plain');
    await plain.create(recursive: true);
    expect(repoRootOf(plain.path), plain.path);
  });
}
