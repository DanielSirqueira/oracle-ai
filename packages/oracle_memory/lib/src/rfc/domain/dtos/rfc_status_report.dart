/// A completion snapshot of an RFC: how many open findings gate it, and whether
/// every required section of the current version is covered. Drives the "can
/// this be approved?" gate without loading the full comment/section set.
class RfcStatusReport {
  final int openCriticals;

  /// Open criticals that are VERIFIED (carry at least one resolved evidence).
  /// Only these gate completion — an unverified critical does not, by design.
  final int blockingCriticals;
  final int openMajors;
  final int totalComments;
  final int requiredSections;
  final int coveredRequired;
  final bool checklistComplete;

  const RfcStatusReport({
    this.openCriticals = 0,
    this.blockingCriticals = 0,
    this.openMajors = 0,
    this.totalComments = 0,
    this.requiredSections = 0,
    this.coveredRequired = 0,
    this.checklistComplete = false,
  });
}
