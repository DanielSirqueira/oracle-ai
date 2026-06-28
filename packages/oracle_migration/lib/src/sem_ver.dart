/// Semantic version (major.minor.patch) with **numeric** comparison.
///
/// WARNING: lexicographic string ordering does NOT work for semver — `'1.10.0'`
/// sorts before `'1.2.0'` as a string but is greater semantically. Always use
/// [SemVer] to order versions; never `ORDER BY` raw version strings in SQL.
class SemVer implements Comparable<SemVer> {
  final int major;
  final int minor;
  final int patch;

  const SemVer(this.major, this.minor, this.patch);

  /// Parses `major.minor.patch` (without a leading `v`).
  factory SemVer.parse(String value) {
    final parts = value.split('.');
    if (parts.length != 3) {
      throw FormatException('Invalid semver (expected X.Y.Z): $value');
    }
    final major = int.tryParse(parts[0]);
    final minor = int.tryParse(parts[1]);
    final patch = int.tryParse(parts[2]);
    if (major == null || minor == null || patch == null) {
      throw FormatException('Invalid semver (non-numeric components): $value');
    }
    return SemVer(major, minor, patch);
  }

  @override
  int compareTo(SemVer other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SemVer &&
          other.major == major &&
          other.minor == minor &&
          other.patch == patch);

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
