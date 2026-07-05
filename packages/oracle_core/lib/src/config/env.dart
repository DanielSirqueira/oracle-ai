import 'dart:io';

import 'secret_protector.dart';

/// Loads environment variables, merging a `.env` file (if present) with the
/// process environment.
///
/// Dart does not read `.env` files automatically, so this gives local runs the
/// same configuration surface as Docker (`env_file`). **Process environment
/// variables take precedence** over file values, so `ORACLE_DB_HOST=db dart
/// run ...` overrides whatever the file declares.
///
/// File format: `KEY=VALUE` per line. Blank lines and `#` comments are ignored.
/// Surrounding single/double quotes around the value are stripped.
Map<String, String> loadEnv({String path = '.env'}) {
  final merged = <String, String>{};

  final file = File(path);
  if (file.existsSync()) {
    for (final raw in file.readAsLinesSync()) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq).trim();
      var value = line.substring(eq + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      // Secrets are stored as `enc:v1:<base64>` (DPAPI). Decrypt transparently
      // on read so every consumer — CLI, MCP, installer — gets plaintext and
      // never has to know a value was protected. Non-encrypted values pass
      // through untouched.
      merged[key] = SecretProtector.unprotect(value);
    }
  }

  // Process environment overrides file values.
  merged.addAll(Platform.environment);
  return merged;
}
