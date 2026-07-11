import 'dart:io';

import 'package:oracle_core/oracle_core.dart';
import 'package:oracle_memory/oracle_memory.dart';

/// Materializes the central skill library to `<dir>/<key>/SKILL.md` so agents
/// with native skill discovery (e.g. Claude Code scanning ~/.claude/skills)
/// pick them up without per-agent duplication — the database stays the single
/// source of truth; this just projects it onto disk.
///
/// Safe by ownership: every file written carries a `managed-by: oracle-ai`
/// frontmatter marker, and only folders bearing that marker are pruned when
/// their skill disappears — hand-written skills are never touched.
///
/// Shared by the CLI (`oracle_ai sync-skills`) and the Studio's sync button.
class SkillSyncService {
  const SkillSyncService();

  /// Default target: the user-level Claude skills folder (shared across all
  /// projects, which matches the library's "one copy for every agent" intent).
  static String defaultDir() {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
    return '$home/.claude/skills';
  }

  Future<SkillSyncReport> sync({String? dir, IdVO? projectId, IdVO? organizationId}) async {
    final target = dir ?? defaultDir();
    final result = await injector.get<ListSkillsUsecase>()(
        projectId: projectId, organizationId: organizationId, limit: 500);
    if (result.isError()) {
      throw result.exceptionOrNull()!;
    }
    final skills = result.getOrDefault(const []);
    final root = Directory(target);
    await root.create(recursive: true);

    // Write/update every current skill.
    final current = <String>{};
    for (final s in skills) {
      current.add(s.key);
      final folder = Directory('${root.path}/${s.key}');
      await folder.create(recursive: true);
      final md = StringBuffer()
        ..writeln('---')
        ..writeln('name: ${s.key}')
        ..writeln('description: ${s.description.value.replaceAll('\n', ' ')}')
        ..writeln('managed-by: oracle-ai')
        ..writeln('---')
        ..writeln()
        ..writeln(s.content.value);
      await File('${folder.path}/SKILL.md').writeAsString(md.toString(), flush: true);
    }

    // Prune folders we own whose skill no longer exists (retired/renamed).
    var pruned = 0;
    await for (final entry in root.list()) {
      if (entry is! Directory) continue;
      final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (current.contains(name)) continue;
      final md = File('${entry.path}/SKILL.md');
      if (!await md.exists()) continue;
      final head = await md.readAsString();
      if (head.contains('managed-by: oracle-ai')) {
        await entry.delete(recursive: true);
        pruned++;
      }
    }

    return SkillSyncReport(dir: root.absolute.path, synced: skills.length, pruned: pruned);
  }
}

/// Summary of a [SkillSyncService.sync].
class SkillSyncReport {
  final String dir;
  final int synced;
  final int pruned;
  const SkillSyncReport({required this.dir, required this.synced, required this.pruned});
}
