import '../entities/rfc_comment_entity.dart';
import '../entities/rfc_entity.dart';
import '../entities/rfc_section_entity.dart';
import '../entities/rfc_version_entity.dart';

/// A fully assembled RFC view: the header, its latest version, that version's
/// sections and its open comments. Backs the single-fetch read used to render
/// or review an RFC in one round-trip.
class RfcBundle {
  final RfcEntity rfc;
  final RfcVersionEntity? version;
  final List<RfcSectionEntity> sections;
  final List<RfcCommentEntity> comments;

  const RfcBundle({
    required this.rfc,
    this.version,
    this.sections = const [],
    this.comments = const [],
  });
}
