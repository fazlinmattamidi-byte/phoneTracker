import 'dart:math' as math;

import 'plate_types.dart';

const defaultSpecialSeriesPrefixes = <String>[
  'MALAYSIA',
  'MADANI',
  'GOLD',
  'PUTRAJAYA',
  'PERODUA',
  'PROTON',
  'LOTUS',
  'WWW',
  'VIP',
  'FF',
  'QV',
  'PATRIOT',
  'PETRA',
  'BAMBEE',
  'G1M',
  'PERFECT',
  'RIMAU',
  'NAVY',
  'AIRFORCE',
  'SUKMA',
  'JAGUH',
  'NAAM',
  'A1M',
  'M1M',
  'RAPID',
  'GTR',
  'GT',
  'YY',
  'UU',
  'UG',
  'UPM',
  'UTM',
  'UKM',
  'USM',
  'UUM',
  'UIM',
  'UITM',
  'UMT',
  'UMP',
  'UIA',
  'IIUM',
  'XXVIASEAN',
  'ASEAN',
];

const _ocrToAlpha = <String, String>{
  '0': 'O',
  '1': 'I',
  '2': 'Z',
  '4': 'A',
  '5': 'S',
  '6': 'G',
  '7': 'T',
  '8': 'B',
};

const _ocrToDigit = <String, String>{
  'O': '0',
  'Q': '0',
  'D': '0',
  'I': '1',
  'L': '1',
  'Z': '2',
  'A': '4',
  'S': '5',
  'G': '6',
  'T': '7',
  'B': '8',
};

List<String> _runtimeSpecialSeriesPrefixes = <String>[];

class SpecialPlateCorrectionResult {
  const SpecialPlateCorrectionResult({
    required this.normalized,
    required this.corrected,
    required this.reason,
    required this.alternatives,
  });

  final String normalized;
  final bool corrected;
  final String reason;
  final List<String> alternatives;
}

class SpecialPlateCorrectionOptions {
  const SpecialPlateCorrectionOptions({
    this.ocrConfidence,
    this.characterConfidences,
    this.minPrefixProbability,
  });

  final double? ocrConfidence;
  final List<CharacterConfidence>? characterConfidences;
  final double? minPrefixProbability;
}

class PrefixProbabilityCandidate {
  const PrefixProbabilityCandidate({
    required this.plate,
    required this.prefix,
    required this.observedPrefix,
    required this.observedSuffix,
    required this.numericSuffix,
    required this.editDistance,
    required this.prefixProbability,
    required this.suffixProbability,
    required this.confidenceEvidence,
    required this.score,
  });

  final String plate;
  final String prefix;
  final String observedPrefix;
  final String observedSuffix;
  final String numericSuffix;
  final int editDistance;
  final double prefixProbability;
  final double suffixProbability;
  final double confidenceEvidence;
  final double score;
}

String _sanitizePrefix(String prefix) {
  return prefix.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
}

List<String> _parsePrefixList(Iterable<String> prefixes) {
  return prefixes
      .map(_sanitizePrefix)
      .where((prefix) => RegExp(r'^[A-Z0-9]{2,15}$').hasMatch(prefix))
      .toList();
}

void setRuntimeSpecialSeriesPrefixes(List<String> prefixes) {
  _runtimeSpecialSeriesPrefixes = _parsePrefixList(prefixes);
}

void resetRuntimeSpecialSeriesPrefixes() {
  _runtimeSpecialSeriesPrefixes = <String>[];
}

List<String> getSpecialSeriesPrefixes() {
  final unique = <String>{
    ...defaultSpecialSeriesPrefixes.map(_sanitizePrefix),
    ..._runtimeSpecialSeriesPrefixes,
  }.where((prefix) => prefix.isNotEmpty).toList();
  unique.sort((a, b) =>
      b.length == a.length ? a.compareTo(b) : b.length.compareTo(a.length));
  return unique;
}

String? findSpecialSeriesPrefix(String normalizedPlate) {
  final normalized = _normalizeAlnum(normalizedPlate);
  for (final prefix in getSpecialSeriesPrefixes()) {
    if (normalized.startsWith(prefix)) return prefix;
  }
  return null;
}

bool isConfiguredSpecialSeriesCandidate(String normalizedPlate) {
  final normalized = _normalizeAlnum(normalizedPlate);
  final prefix = findSpecialSeriesPrefix(normalized);
  if (prefix == null) return false;
  final suffix = normalized.substring(prefix.length);
  return RegExp(r'^[0-9]{1,5}[A-Z]?$').hasMatch(suffix);
}

bool isFutureSpecialSeriesCandidate(String normalizedPlate) {
  final normalized = _normalizeAlnum(normalizedPlate);
  if (isConfiguredSpecialSeriesCandidate(normalized)) {
    return false;
  }
  final match =
      RegExp(r'^([A-Z]{4,12})([0-9]{1,5}[A-Z]?)$').firstMatch(normalized);
  if (match == null) {
    return false;
  }
  final prefix = match.group(1)!;
  if (RegExp(r'^(POLIS|KASTAM|PRISON|JKR|PUTRAJAYA)$').hasMatch(prefix)) {
    return false;
  }
  return true;
}

bool isPotentialSpecialSeriesCandidate(String normalizedPlate) {
  final normalized = _normalizeAlnum(normalizedPlate);
  if (normalized.isEmpty) {
    return false;
  }
  if (isConfiguredSpecialSeriesCandidate(normalized) ||
      isFutureSpecialSeriesCandidate(normalized)) {
    return true;
  }
  return RegExp(r'^[A-Z0-9]{4,15}$').hasMatch(normalized) &&
      rankSpecialSeriesPrefixCandidates(
        normalized,
        options:
            const SpecialPlateCorrectionOptions(minPrefixProbability: 0.64),
      ).isNotEmpty;
}

SpecialPlateCorrectionResult correctMalaysianPlateOcr(
  String raw, {
  SpecialPlateCorrectionOptions options = const SpecialPlateCorrectionOptions(),
}) {
  final normalized = _normalizeAlnum(raw);
  if (normalized.isEmpty) {
    return const SpecialPlateCorrectionResult(
      normalized: '',
      corrected: false,
      reason: 'NONE',
      alternatives: <String>[],
    );
  }

  if (_isProtectedStandardPlateShape(normalized)) {
    return SpecialPlateCorrectionResult(
      normalized: normalized,
      corrected: false,
      reason: 'NONE',
      alternatives: const <String>[],
    );
  }

  final prefixCandidates =
      rankSpecialSeriesPrefixCandidates(normalized, options: options);
  final futureCorrection = _buildFutureSpecialCorrection(normalized, options);
  final alternatives = <String>{
    for (final candidate in prefixCandidates) candidate.plate,
    if (futureCorrection != null) futureCorrection.plate,
  }.where((item) => item.isNotEmpty).toList();

  final ranked = <_CorrectionCandidate>[
    for (final candidate in prefixCandidates)
      _CorrectionCandidate(
          candidate.plate, candidate.score, 'PREFIX_PROBABILITY'),
    if (futureCorrection != null) futureCorrection,
  ]..sort((a, b) => b.score.compareTo(a.score));

  if (ranked.isEmpty) {
    return SpecialPlateCorrectionResult(
      normalized: normalized,
      corrected: false,
      reason: 'NONE',
      alternatives: alternatives,
    );
  }

  final best = ranked.first;
  return SpecialPlateCorrectionResult(
    normalized: best.plate,
    corrected: best.plate != normalized,
    reason: best.reason,
    alternatives: alternatives,
  );
}

List<String> generateSpecialPlateCandidates(
  String raw, {
  int maxCandidates = 12,
  SpecialPlateCorrectionOptions options = const SpecialPlateCorrectionOptions(),
}) {
  final correction = correctMalaysianPlateOcr(raw, options: options);
  return <String>{correction.normalized, ...correction.alternatives}
      .where((item) => item.isNotEmpty)
      .take(maxCandidates)
      .toList();
}

List<PrefixProbabilityCandidate> rankSpecialSeriesPrefixCandidates(
  String raw, {
  SpecialPlateCorrectionOptions options = const SpecialPlateCorrectionOptions(),
}) {
  final normalized = _normalizeAlnum(raw);
  if (normalized.isEmpty) return const <PrefixProbabilityCandidate>[];

  final minScore = options.minPrefixProbability ?? 0.70;
  final byPlate = <String, PrefixProbabilityCandidate>{};

  for (final prefix in getSpecialSeriesPrefixes()) {
    final takeLengths =
        _buildPrefixTakeLengths(prefix.length, normalized.length);
    for (final takeLength in takeLengths) {
      final observedRawPrefix = normalized.substring(0, takeLength);
      final observedPrefix = _toAlphaEquivalent(observedRawPrefix);
      if (observedPrefix.isEmpty) continue;

      final observedSuffix = normalized.substring(takeLength);
      final numericSuffix = _toDigitString(observedSuffix);
      if (!RegExp(r'^[0-9]{1,5}$').hasMatch(numericSuffix)) continue;
      if (numericSuffix.length != observedSuffix.length) continue;

      final editDistance = _levenshteinDistance(observedPrefix, prefix);
      if (editDistance > _getMaxPrefixDistance(prefix, options.ocrConfidence)) {
        continue;
      }

      final prefixProbability = _scorePrefixProbability(
          prefix, observedRawPrefix, observedPrefix, editDistance);
      final suffixProbability =
          _scoreSuffixProbability(observedSuffix, numericSuffix);
      final confidenceEvidence =
          _getConfidenceEvidence(options, takeLength, observedSuffix.length);
      final numberLengthPrior = math.min(1.0, numericSuffix.length / 4);
      final score = prefixProbability * 0.58 +
          suffixProbability * 0.22 +
          confidenceEvidence * 0.15 +
          numberLengthPrior * 0.05;
      if (score < minScore) continue;

      final plate = '$prefix$numericSuffix';
      final candidate = PrefixProbabilityCandidate(
        plate: plate,
        prefix: prefix,
        observedPrefix: observedPrefix,
        observedSuffix: observedSuffix,
        numericSuffix: numericSuffix,
        editDistance: editDistance,
        prefixProbability: prefixProbability,
        suffixProbability: suffixProbability,
        confidenceEvidence: confidenceEvidence,
        score: score,
      );

      final existing = byPlate[plate];
      if (existing == null || candidate.score > existing.score) {
        byPlate[plate] = candidate;
      }
    }
  }

  final values = byPlate.values.toList()
    ..sort((a, b) => b.score.compareTo(a.score));
  return values;
}

bool _isProtectedStandardPlateShape(String normalized) {
  if (isConfiguredSpecialSeriesCandidate(normalized)) {
    return false;
  }
  if (RegExp(r'^[A-Z]{1,3}[0-9]{1,5}[A-Z]{0,2}$').hasMatch(normalized)) {
    return true;
  }
  if (RegExp(r'^EV[A-Z]{0,2}[0-9]{1,5}[A-Z]?$').hasMatch(normalized)) {
    return true;
  }
  if (RegExp(r'^KV[0-9]{1,5}[A-Z]?$').hasMatch(normalized)) {
    return true;
  }
  if (RegExp(r'^(SA|SB|SD|SK|SS|ST|SU|SW|S)[A-Z]{0,2}[0-9]{1,5}[A-Z]?$')
      .hasMatch(normalized)) {
    return true;
  }
  if (RegExp(r'^(QA|QB|QC|QD|QK|QL|QP|QR|QS|QT|Q)[A-Z]{0,2}[0-9]{1,5}[A-Z]?$')
      .hasMatch(normalized)) {
    return true;
  }
  return false;
}

_CorrectionCandidate? _buildFutureSpecialCorrection(
    String normalized, SpecialPlateCorrectionOptions options) {
  for (var prefixLength = math.min(12, normalized.length - 1);
      prefixLength >= 4;
      prefixLength--) {
    final rawPrefix = normalized.substring(0, prefixLength);
    final rawDigitCount = RegExp(r'[0-9]').allMatches(rawPrefix).length;
    if (rawDigitCount > 1) continue;

    final prefix = _toAlphaEquivalent(normalized.substring(0, prefixLength));
    final observedSuffix = normalized.substring(prefixLength);
    final numericSuffix = _toDigitString(observedSuffix);
    if (numericSuffix.length != observedSuffix.length) continue;

    if (RegExp(r'^[A-Z]{4,12}$').hasMatch(prefix) &&
        RegExp(r'^[0-9]{1,5}$').hasMatch(numericSuffix)) {
      final confidenceEvidence =
          _getConfidenceEvidence(options, prefixLength, numericSuffix.length);
      return _CorrectionCandidate(
        '$prefix$numericSuffix',
        0.62 +
            confidenceEvidence * 0.08 +
            math.min(0.08, numericSuffix.length * 0.01),
        'FUTURE_SPECIAL_PREFIX',
      );
    }
  }
  return null;
}

List<int> _buildPrefixTakeLengths(int prefixLength, int normalizedLength) {
  final minLength = math.max(1, prefixLength - 2);
  final maxLength = math.min(normalizedLength - 1, prefixLength + 2);
  final preferred = <int>[
    prefixLength,
    prefixLength - 1,
    prefixLength + 1,
    prefixLength - 2,
    prefixLength + 2
  ];
  final values = <int>{...preferred}
      .where((length) => length >= minLength && length <= maxLength)
      .toList();
  values.sort(
      (a, b) => (a - prefixLength).abs().compareTo((b - prefixLength).abs()));
  return values;
}

int _getMaxPrefixDistance(String prefix, double? ocrConfidence) {
  final confidence = ocrConfidence ?? 0.86;
  if (prefix.length >= 7) return confidence >= 0.78 ? 2 : 1;
  if (prefix.length >= 4) return 1;
  if (prefix.length >= 3) return confidence >= 0.88 ? 1 : 0;
  return 0;
}

double _scorePrefixProbability(String prefix, String observedRawPrefix,
    String observedPrefix, int editDistance) {
  final maxLen = math.max(math.max(prefix.length, observedPrefix.length), 1);
  final editSimilarity = 1 - editDistance / maxLen;
  final positionalSimilarity =
      _scorePositionalPrefixSimilarity(prefix, observedRawPrefix);
  final lengthSkew = (prefix.length - observedPrefix.length).abs();
  final prefixLengthPrior = math.min(1.0, prefix.length / 8);
  final digitConfusionDensity =
      RegExp(r'[0-9]').allMatches(observedRawPrefix).length /
          math.max(1, observedRawPrefix.length);

  return _clampNumber(
    editSimilarity * 0.58 +
        positionalSimilarity * 0.32 +
        prefixLengthPrior * 0.10 +
        math.min(0.04, digitConfusionDensity * 0.08) -
        lengthSkew * 0.03,
    0,
    1,
  );
}

double _scorePositionalPrefixSimilarity(
    String prefix, String observedRawPrefix) {
  final comparedLength =
      math.max(math.max(prefix.length, observedRawPrefix.length), 1);
  var score = 0.0;

  for (var index = 0; index < comparedLength; index++) {
    final target = index < prefix.length ? prefix[index] : '';
    final observedRaw =
        index < observedRawPrefix.length ? observedRawPrefix[index] : '';
    if (target.isEmpty || observedRaw.isEmpty) {
      score += 0.18;
    } else {
      score += _scoreObservedPrefixChar(observedRaw, target);
    }
  }

  return _clampNumber(score / comparedLength, 0, 1);
}

double _scoreObservedPrefixChar(String observedRaw, String target) {
  final alpha = _ocrToAlpha[observedRaw] ?? observedRaw;
  if (alpha == target) return RegExp(r'[0-9]').hasMatch(observedRaw) ? 0.9 : 1;
  if (_isLikelyAlphaConfusion(alpha, target)) return 0.72;
  return 0.18;
}

bool _isLikelyAlphaConfusion(String observed, String target) {
  const confusions = <String, List<String>>{
    'A': ['R'],
    'B': ['R'],
    'D': ['O', 'Q'],
    'I': ['L'],
    'L': ['I'],
    'O': ['D', 'Q'],
    'Q': ['O', 'D'],
    'R': ['A', 'B'],
    'S': ['Z'],
    'U': ['V'],
    'V': ['U', 'Y'],
    'Y': ['V'],
    'Z': ['S'],
  };

  return confusions[target]?.contains(observed) ?? false;
}

double _scoreSuffixProbability(String observedSuffix, String numericSuffix) {
  if (observedSuffix.isEmpty || observedSuffix.length != numericSuffix.length) {
    return 0;
  }
  var converted = 0;

  for (var index = 0; index < observedSuffix.length; index++) {
    final observed = observedSuffix[index];
    if (observed == numericSuffix[index]) continue;
    if (_ocrToDigit[observed] == numericSuffix[index]) {
      converted++;
      continue;
    }
    return 0;
  }

  final conversionRatio = converted / math.max(1, observedSuffix.length);
  final lengthPrior = math.min(0.04, numericSuffix.length * 0.01);
  return _clampNumber(0.97 - conversionRatio * 0.12 + lengthPrior, 0, 1);
}

double _getConfidenceEvidence(
    SpecialPlateCorrectionOptions options, int prefixLength, int suffixLength) {
  final confidences = options.characterConfidences?.toList();
  confidences?.sort((a, b) => a.position.compareTo(b.position));
  final values = confidences
      ?.map((item) => _clampNumber(item.confidence, 0, 1))
      .where((confidence) => confidence.isFinite)
      .toList();

  if (values != null && values.isNotEmpty) {
    final relevant =
        values.take(math.max(1, prefixLength + suffixLength)).toList();
    return relevant.reduce((sum, value) => sum + value) / relevant.length;
  }

  if (options.ocrConfidence != null) {
    return _clampNumber(options.ocrConfidence!, 0, 1);
  }

  return 0.86;
}

String _normalizeAlnum(String raw) {
  return raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
}

double _clampNumber(double value, double min, double max) {
  return math.min(max, math.max(min, value));
}

String _toAlphaEquivalent(String value) {
  return value
      .split('')
      .map((char) => _ocrToAlpha[char] ?? char)
      .join()
      .replaceAll(RegExp(r'[^A-Z]'), '');
}

String _toDigitString(String value) {
  return value.split('').map((char) {
    if (RegExp(r'[0-9]').hasMatch(char)) return char;
    return _ocrToDigit[char] ?? '';
  }).join();
}

int _levenshteinDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  final row = List<int>.generate(b.length + 1, (index) => index);
  for (var i = 1; i <= a.length; i++) {
    var previous = row[0];
    row[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final temp = row[j];
      row[j] = a[i - 1] == b[j - 1]
          ? previous
          : math.min(math.min(previous + 1, row[j] + 1), row[j - 1] + 1);
      previous = temp;
    }
  }

  return row[b.length];
}

class _CorrectionCandidate {
  const _CorrectionCandidate(this.plate, this.score, this.reason);

  final String plate;
  final double score;
  final String reason;
}
