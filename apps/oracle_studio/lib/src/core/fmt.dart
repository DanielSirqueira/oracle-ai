/// Small formatting helpers (no intl dependency).
library;

String two(int n) => n.toString().padLeft(2, '0');

/// `04/07/2026 13:45` (or `—` when null).
String fmtDateTime(DateTime? dt) {
  if (dt == null) return '—';
  final l = dt.toLocal();
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}

/// `12,3k` / `4,5M` style compact numbers.
String fmtCompact(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1).replaceAll('.', ',')}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1).replaceAll('.', ',')}k';
  return '$n';
}

/// `2,1 MB` style byte sizes.
String fmtBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1).replaceAll('.', ',')} kB';
  return '$bytes B';
}
