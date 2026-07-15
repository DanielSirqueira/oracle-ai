import '../entities/rfc_comment_entity.dart';

/// A latest comment found near a query embedding, with its cosine [distance]
/// (lower = more similar). Powers the add-time "you already have a finding like
/// this" signal that dedups near-twin comments instead of piling them up.
class RfcCommentNeighbor {
  final RfcCommentEntity comment;
  final double distance;

  const RfcCommentNeighbor({required this.comment, required this.distance});
}
