import 'normaliser.dart';

class OcrVote {
  const OcrVote({
    required this.count,
    required this.totalConfidence,
  });

  final int count;
  final double totalConfidence;

  double get averageConfidence => count <= 0 ? 0 : totalConfidence / count;
}

class ConsensusResult {
  const ConsensusResult({
    required this.isStabilized,
    required this.normalizedPlate,
    required this.displayPlate,
    required this.confidence,
    required this.voteCount,
  });

  final bool isStabilized;
  final String normalizedPlate;
  final String displayPlate;
  final double confidence;
  final int voteCount;
}

ConsensusResult evaluateConsensus(
  Map<String, OcrVote> votes, {
  int requiredVotes = 3,
  double minConfidence = 0.65,
}) {
  if (votes.isEmpty) {
    return const ConsensusResult(
      isStabilized: false,
      normalizedPlate: '',
      displayPlate: '',
      confidence: 0,
      voteCount: 0,
    );
  }

  final ranked = votes.entries.toList()
    ..sort((a, b) {
      final countCompare = b.value.count.compareTo(a.value.count);
      if (countCompare != 0) return countCompare;
      return b.value.averageConfidence.compareTo(a.value.averageConfidence);
    });

  final top = ranked.first;
  final normalized = normalizePlate(top.key);
  final confidence = top.value.averageConfidence;
  return ConsensusResult(
    isStabilized:
        top.value.count >= requiredVotes && confidence >= minConfidence,
    normalizedPlate: normalized,
    displayPlate: formatDisplayPlate(normalized),
    confidence: confidence,
    voteCount: top.value.count,
  );
}

Map<String, OcrVote> promoteCorrectedOcrVote(
  Map<String, OcrVote> votes,
  String originalPlate,
  String correctedPlate, {
  double confidence = 0.65,
}) {
  final original = normalizePlate(originalPlate);
  final corrected = normalizePlate(correctedPlate);
  if (original.isEmpty || corrected.isEmpty || original == corrected) {
    return Map<String, OcrVote>.from(votes);
  }

  final next = Map<String, OcrVote>.from(votes);
  final originalVote = next.remove(original);
  if (originalVote == null) return next;

  final existing = next[corrected];
  next[corrected] = OcrVote(
    count: (existing?.count ?? 0) + originalVote.count,
    totalConfidence: (existing?.totalConfidence ?? 0) +
        originalVote.totalConfidence +
        confidence,
  );
  return next;
}
