import 'dart:io';

/// Structured .env editing: updates known keys IN PLACE (preserving comments,
/// blank lines and any key the form doesn't manage) and appends new keys at
/// the end. The file stays hand-editable — the form is just a safer pen.
class EnvEditor {
  const EnvEditor._();

  static Future<void> apply(String path, Map<String, String?> changes) async {
    final file = File(path);
    final lines = file.existsSync() ? await file.readAsLines() : <String>[];
    final pending = Map<String, String?>.from(changes);

    final out = <String>[];
    for (final raw in lines) {
      final line = raw.trimLeft();
      if (line.isEmpty || line.startsWith('#')) {
        out.add(raw);
        continue;
      }
      final eq = line.indexOf('=');
      if (eq <= 0) {
        out.add(raw);
        continue;
      }
      final key = line.substring(0, eq).trim();
      if (!pending.containsKey(key)) {
        out.add(raw);
        continue;
      }
      final value = pending.remove(key);
      if (value == null || value.isEmpty) continue; // clearing removes the line
      out.add('$key=$value');
    }
    for (final e in pending.entries) {
      final v = e.value;
      if (v == null || v.isEmpty) continue;
      out.add('${e.key}=$v');
    }

    // Backup the previous file once per save, then write atomically.
    if (file.existsSync()) await file.copy('$path.bak');
    final tmp = File('$path.tmp');
    await tmp.writeAsString('${out.join('\n')}\n', flush: true);
    if (file.existsSync()) await file.delete();
    await tmp.rename(path);
  }
}
