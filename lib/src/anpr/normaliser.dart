import 'special_series.dart';
import 'plate_types.dart';

class TypographyCorrectionResult {
  const TypographyCorrectionResult({
    required this.normalized,
    required this.corrected,
    required this.alternatives,
    required this.reason,
  });

  final String normalized;
  final bool corrected;
  final List<String> alternatives;
  final String reason;
}

class TypographyCorrectionOptions {
  const TypographyCorrectionOptions({
    this.ocrConfidence,
    this.characterConfidences,
  });

  final double? ocrConfidence;
  final List<CharacterConfidence>? characterConfidences;
}

const confusionMap = <String, List<String>>{
  'O': ['0'],
  '0': ['O', 'Q', 'D'],
  'I': ['1', 'L'],
  '1': ['I', 'L'],
  'L': ['1', 'I'],
  'B': ['8'],
  '8': ['B'],
  'S': ['5'],
  '5': ['S'],
  'Z': ['2'],
  '2': ['Z'],
  'G': ['6'],
  '6': ['G'],
  'A': ['4'],
  '4': ['A'],
  'T': ['7'],
  '7': ['T'],
  'D': ['0', 'O'],
  'Q': ['0', 'O'],
};

const _stylizedPrefixConfusions = <String, List<String>>{
  'A': ['R'],
  'R': ['A'],
};

String normalizePlate(String raw) {
  if (raw.isEmpty) return '';
  return raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
}

String formatDisplayPlate(String normalized, {PlateCategory? category}) {
  if (normalized.isEmpty) return '';

  final specialPrefix = findSpecialSeriesPrefix(normalized);
  if (specialPrefix != null) {
    final suffix = normalized.substring(specialPrefix.length);
    if (RegExp(r'^[0-9]{1,5}[A-Z]?$').hasMatch(suffix)) {
      return '$specialPrefix $suffix';
    }
  }

  final evMatch =
      RegExp(r'^(EV[A-Z]{0,2})([0-9]{1,5})([A-Z]?)$').firstMatch(normalized);
  if (evMatch != null) {
    return _joinGroups([evMatch.group(1), evMatch.group(2), evMatch.group(3)]);
  }

  final langkawiMatch =
      RegExp(r'^(KV)([0-9]{1,5})([A-Z]?)$').firstMatch(normalized);
  if (langkawiMatch != null) {
    return _joinGroups([
      langkawiMatch.group(1),
      langkawiMatch.group(2),
      langkawiMatch.group(3)
    ]);
  }

  final suffixMatch =
      RegExp(r'^([A-Z]{1,3})([0-9]{1,5})([A-Z]{1,2})$').firstMatch(normalized);
  if (suffixMatch != null) {
    return '${suffixMatch.group(1)} ${suffixMatch.group(2)} ${suffixMatch.group(3)}';
  }

  final standardMatch =
      RegExp(r'^([A-Z]{1,4})([0-9]{1,5})$').firstMatch(normalized);
  if (standardMatch != null) {
    return '${standardMatch.group(1)} ${standardMatch.group(2)}';
  }

  final mixedTail =
      RegExp(r'^([A-Z]{1,3})([0-9]{1,5})([A-Z][0-9])$').firstMatch(normalized);
  if (mixedTail != null) {
    return '${mixedTail.group(1)} ${mixedTail.group(2)} ${mixedTail.group(3)}';
  }

  final alternatingGroups = RegExp(r'[A-Z]+|[0-9]+')
      .allMatches(normalized)
      .map((match) => match.group(0)!)
      .toList();
  if (alternatingGroups.length > 1) {
    return alternatingGroups.join(' ');
  }

  return normalized;
}

List<String> generateCandidatePlates(
  String normalized, {
  List<CharacterConfidence>? charConfidences,
  int maxPermutations = 10,
}) {
  if (normalized.isEmpty) return const <String>[];
  final candidates = <String>{};

  for (final candidate in generateSpecialPlateCandidates(normalized,
      maxCandidates: maxPermutations)) {
    if (candidate != normalized && candidates.length < maxPermutations) {
      candidates.add(candidate);
    }
  }

  for (final candidate in _generateStylizedPrefixCandidates(normalized)) {
    if (candidate != normalized && candidates.length < maxPermutations) {
      candidates.add(candidate);
    }
  }

  final candidateIndices = <int>[];
  if (charConfidences != null && charConfidences.length == normalized.length) {
    for (var index = 0; index < charConfidences.length; index++) {
      final item = charConfidences[index];
      if (item.confidence < 0.85 && confusionMap.containsKey(item.char)) {
        candidateIndices.add(index);
      }
    }
  }

  if (candidateIndices.isEmpty) {
    for (var index = 0; index < normalized.length; index++) {
      if (confusionMap.containsKey(normalized[index])) {
        candidateIndices.add(index);
      }
    }
  }

  for (final index in candidateIndices) {
    if (candidates.length >= maxPermutations) break;
    final char = normalized[index];
    final replacements = confusionMap[char];
    if (replacements == null) continue;
    for (final replacement in replacements) {
      if (candidates.length >= maxPermutations) break;
      final alternative = normalized.substring(0, index) +
          replacement +
          normalized.substring(index + 1);
      if (alternative != normalized) {
        candidates.add(alternative);
      }
    }
  }

  return candidates.toList();
}

TypographyCorrectionResult correctMalaysianTypographyOcr(
  String raw, {
  TypographyCorrectionOptions options = const TypographyCorrectionOptions(),
}) {
  final normalized = normalizePlate(raw);
  if (normalized.isEmpty) {
    return const TypographyCorrectionResult(
      normalized: '',
      corrected: false,
      alternatives: <String>[],
      reason: 'NONE',
    );
  }

  final alternatives = _generateStylizedPrefixCandidates(normalized);
  final sabahStylizedA =
      RegExp(r'^SR([A-Z][0-9]{3,5}[A-Z]?)$').firstMatch(normalized);
  if (sabahStylizedA == null) {
    return TypographyCorrectionResult(
      normalized: normalized,
      corrected: false,
      alternatives: alternatives,
      reason: 'NONE',
    );
  }

  final positionOne = options.characterConfidences == null
      ? null
      : _firstWhereOrNull(
          options.characterConfidences!, (item) => item.position == 1);
  final confidenceEvidence = [
    options.ocrConfidence ?? 0.85,
    positionOne?.confidence ?? 0.85,
  ].reduce((a, b) => a > b ? a : b);
  final corrected = 'SA${sabahStylizedA.group(1)}';

  if (confidenceEvidence >= 0.45) {
    return TypographyCorrectionResult(
      normalized: corrected,
      corrected: corrected != normalized,
      alternatives: <String>{corrected, ...alternatives}.toList(),
      reason: 'SABAH_STYLIZED_A',
    );
  }

  return TypographyCorrectionResult(
    normalized: normalized,
    corrected: false,
    alternatives: alternatives,
    reason: 'NONE',
  );
}

int getLevenshteinDistance(String a, String b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  final matrix = List<List<int>>.generate(
    b.length + 1,
    (_) => List<int>.filled(a.length + 1, 0),
  );

  for (var i = 0; i <= b.length; i++) {
    matrix[i][0] = i;
  }
  for (var j = 0; j <= a.length; j++) {
    matrix[0][j] = j;
  }

  for (var i = 1; i <= b.length; i++) {
    for (var j = 1; j <= a.length; j++) {
      if (b[i - 1] == a[j - 1]) {
        matrix[i][j] = matrix[i - 1][j - 1];
      } else {
        final substitution = matrix[i - 1][j - 1] + 1;
        final insertion = matrix[i][j - 1] + 1;
        final deletion = matrix[i - 1][j] + 1;
        matrix[i][j] =
            [substitution, insertion, deletion].reduce((x, y) => x < y ? x : y);
      }
    }
  }

  return matrix[b.length][a.length];
}

bool isRepeatedCharacterOmission(String ocrReading, String candidatePlate) {
  final normOcr = normalizePlate(ocrReading);
  final normCandidate = normalizePlate(candidatePlate);
  if (normOcr.isEmpty || normCandidate.length != normOcr.length + 1) {
    return false;
  }

  for (var index = 0; index < normCandidate.length; index++) {
    final leftSame =
        index > 0 && normCandidate[index] == normCandidate[index - 1];
    final rightSame = index < normCandidate.length - 1 &&
        normCandidate[index] == normCandidate[index + 1];
    if (!leftSame && !rightSame) continue;

    final withoutChar =
        normCandidate.substring(0, index) + normCandidate.substring(index + 1);
    if (withoutChar == normOcr) return true;
  }

  return false;
}

bool isPossibleMatch(String plateA, String plateB) {
  final normA = normalizePlate(plateA);
  final normB = normalizePlate(plateB);
  if (normA == normB) return false;

  if ((normA.length - normB.length).abs() <= 1 &&
      getLevenshteinDistance(normA, normB) == 1) {
    return true;
  }

  return generateCandidatePlates(normA).contains(normB);
}

String _joinGroups(List<String?> groups) {
  return groups.where((group) => group != null && group.isNotEmpty).join(' ');
}

List<String> _generateStylizedPrefixCandidates(String normalized) {
  final match =
      RegExp(r'^([A-Z]{1,3})([0-9]{1,5}[A-Z]{0,2})$').firstMatch(normalized);
  if (match == null) return const <String>[];

  final prefix = match.group(1)!;
  final suffix = match.group(2)!;
  final candidates = <String>{};

  for (var index = 0; index < prefix.length; index++) {
    final replacements = _stylizedPrefixConfusions[prefix[index]];
    if (replacements == null) continue;
    for (final replacement in replacements) {
      candidates.add(
          '${prefix.substring(0, index)}$replacement${prefix.substring(index + 1)}$suffix');
    }
  }

  return candidates.toList();
}

T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T value) test) {
  for (final value in values) {
    if (test(value)) {
      return value;
    }
  }
  return null;
}
