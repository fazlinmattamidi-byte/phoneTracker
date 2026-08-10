import 'plate_types.dart';
import 'special_series.dart';

class PlatePatternDefinition {
  const PlatePatternDefinition({
    required this.id,
    required this.category,
    required this.description,
    required this.regex,
    required this.minLen,
    required this.maxLen,
    required this.priority,
    required this.isStrict,
    this.hasTrailingSuffix = false,
    this.expectedLayout,
  });

  final String id;
  final PlateCategory category;
  final String description;
  final RegExp regex;
  final int minLen;
  final int maxLen;
  final bool hasTrailingSuffix;
  final PlateLayout? expectedLayout;
  final int priority;
  final bool isStrict;
}

class PatternValidationResult {
  const PatternValidationResult({
    required this.isValid,
    required this.category,
    required this.score,
    required this.hasTrailingSuffix,
    this.pattern,
  });

  final bool isValid;
  final PlatePatternDefinition? pattern;
  final PlateCategory category;
  final double score;
  final bool hasTrailingSuffix;
}

final malaysianPatterns = <PlatePatternDefinition>[
  PlatePatternDefinition(
    id: 'EV_SPECIAL',
    category: PlateCategory.evSpecial,
    description: 'Electric Vehicle EV Special Series',
    regex: RegExp(r'^EV[A-Z]{0,2}[0-9]{1,5}[A-Z]?$'),
    minLen: 3,
    maxLen: 9,
    priority: 100,
    isStrict: true,
  ),
  PlatePatternDefinition(
    id: 'LANGKAWI_SUFFIX',
    category: PlateCategory.langkawi,
    description: 'Langkawi Series with Alphabetic Suffix',
    regex: RegExp(r'^KV[0-9]{1,5}[A-Z]$'),
    minLen: 4,
    maxLen: 8,
    hasTrailingSuffix: true,
    priority: 95,
    isStrict: true,
  ),
  PlatePatternDefinition(
    id: 'LANGKAWI_STANDARD',
    category: PlateCategory.langkawi,
    description: 'Langkawi Standard Series',
    regex: RegExp(r'^KV[0-9]{1,5}$'),
    minLen: 3,
    maxLen: 7,
    priority: 90,
    isStrict: true,
  ),
  PlatePatternDefinition(
    id: 'LETTER_NUMBER_SUFFIX',
    category: PlateCategory.letterNumberSuffix,
    description: 'KL/Peninsular Letter-Number-Letter Series',
    regex: RegExp(r'^[A-Z]{1,3}[0-9]{1,5}[A-Z]{1,2}$'),
    minLen: 3,
    maxLen: 10,
    hasTrailingSuffix: true,
    priority: 85,
    isStrict: true,
  ),
  PlatePatternDefinition(
    id: 'SABAH_SUFFIX',
    category: PlateCategory.sabah,
    description: 'Sabah Series with Suffix',
    regex: RegExp(r'^(SA|SB|SD|SK|SS|ST|SU|SW|S)[A-Z]{0,2}[0-9]{1,5}[A-Z]$'),
    minLen: 3,
    maxLen: 9,
    hasTrailingSuffix: true,
    priority: 88,
    isStrict: true,
  ),
  PlatePatternDefinition(
    id: 'SABAH_STANDARD',
    category: PlateCategory.sabah,
    description: 'Sabah Standard Series',
    regex: RegExp(r'^(SA|SB|SD|SK|SS|ST|SU|SW|S)[A-Z]{0,2}[0-9]{1,5}$'),
    minLen: 2,
    maxLen: 9,
    priority: 85,
    isStrict: true,
  ),
  PlatePatternDefinition(
    id: 'SARAWAK_SUFFIX',
    category: PlateCategory.sarawak,
    description: 'Sarawak Series with Suffix',
    regex:
        RegExp(r'^(QA|QB|QC|QD|QK|QL|QP|QR|QS|QT|Q)[A-Z]{0,2}[0-9]{1,5}[A-Z]$'),
    minLen: 3,
    maxLen: 9,
    hasTrailingSuffix: true,
    priority: 88,
    isStrict: true,
  ),
  PlatePatternDefinition(
    id: 'SARAWAK_STANDARD',
    category: PlateCategory.sarawak,
    description: 'Sarawak Standard Series',
    regex: RegExp(r'^(QA|QB|QC|QD|QK|QL|QP|QR|QS|QT|Q)[A-Z]{0,2}[0-9]{1,5}$'),
    minLen: 2,
    maxLen: 8,
    priority: 85,
    isStrict: true,
  ),
  PlatePatternDefinition(
    id: 'PUTRAJAYA',
    category: PlateCategory.putrajaya,
    description: 'Putrajaya Series',
    regex: RegExp(r'^PUTRAJAYA[0-9]{1,5}$'),
    minLen: 10,
    maxLen: 14,
    priority: 85,
    isStrict: true,
  ),
  PlatePatternDefinition(
    id: 'DIPLOMATIC',
    category: PlateCategory.diplomatic,
    description: 'Diplomatic / Consular Series',
    regex: RegExp(r'^([0-9]{1,6}(DP|DC|CC|UN)|(DP|DC|CC|UN)[0-9]{1,5})$'),
    minLen: 3,
    maxLen: 8,
    priority: 90,
    isStrict: true,
  ),
  PlatePatternDefinition(
    id: 'GOVERNMENT',
    category: PlateCategory.government,
    description: 'Government and enforcement series',
    regex: RegExp(
        r'^(Z|JKR|POLIS|TDM|TLDM|TUDM|APMM|PRISON|KASTAM)[0-9]{1,5}[A-Z]?$'),
    minLen: 2,
    maxLen: 11,
    priority: 82,
    isStrict: true,
  ),
  PlatePatternDefinition(
    id: 'INSTITUTIONAL_PREFIX',
    category: PlateCategory.institutional,
    description: 'Institutional or permit-style prefix series',
    regex: RegExp(r'^(VEP|JPJ|MOT|SPAD|LPT|PLUS|PRASARANA)[0-9]{1,5}[A-Z]?$'),
    minLen: 4,
    maxLen: 11,
    priority: 83,
    isStrict: false,
  ),
  PlatePatternDefinition(
    id: 'SPECIAL_SERIES',
    category: PlateCategory.specialSeries,
    description: 'Configurable special, premium and commemorative series',
    regex: RegExp(r'a^'),
    minLen: 3,
    maxLen: 15,
    priority: 80,
    isStrict: false,
  ),
  PlatePatternDefinition(
    id: 'FUTURE_SPECIAL_SERIES',
    category: PlateCategory.specialSeries,
    description: 'Future configurable JPJ special series fallback',
    regex: RegExp(r'^[A-Z]{4,12}[0-9]{1,5}[A-Z]?$'),
    minLen: 5,
    maxLen: 17,
    priority: 62,
    isStrict: false,
  ),
  PlatePatternDefinition(
    id: 'STANDARD_PENINSULAR',
    category: PlateCategory.standard,
    description: 'Standard Peninsular Series',
    regex: RegExp(r'^[A-Z]{1,3}[0-9]{1,5}$'),
    minLen: 2,
    maxLen: 8,
    priority: 70,
    isStrict: false,
  ),
  PlatePatternDefinition(
    id: 'GENERIC_MALAYSIAN',
    category: PlateCategory.unknownValidCandidate,
    description: 'Generic valid alphanumeric sequence',
    regex: RegExp(r'^(?=.*[A-Z])(?=.*[0-9])[A-Z0-9]{2,15}$'),
    minLen: 2,
    maxLen: 15,
    priority: 10,
    isStrict: false,
  ),
];

PatternValidationResult validateMalaysianPattern(String normalizedPlate) {
  if (normalizedPlate.isEmpty || normalizedPlate.length < 2) {
    return const PatternValidationResult(
      isValid: false,
      category: PlateCategory.unknownValidCandidate,
      score: 0,
      hasTrailingSuffix: false,
    );
  }

  if (isConfiguredSpecialSeriesCandidate(normalizedPlate) &&
      !RegExp(r'^PUTRAJAYA[0-9]').hasMatch(normalizedPlate)) {
    final pattern =
        malaysianPatterns.firstWhere((item) => item.id == 'SPECIAL_SERIES');
    return PatternValidationResult(
      isValid: true,
      pattern: pattern,
      category: pattern.category,
      score: _scoreFromPriority(pattern.priority),
      hasTrailingSuffix: RegExp(r'[A-Z]$').hasMatch(normalizedPlate) &&
          RegExp(r'[0-9]').hasMatch(normalizedPlate),
    );
  }

  for (final pattern in malaysianPatterns) {
    if (pattern.id == 'SPECIAL_SERIES' &&
        isConfiguredSpecialSeriesCandidate(normalizedPlate)) {
      return PatternValidationResult(
        isValid: true,
        pattern: pattern,
        category: pattern.category,
        score: _scoreFromPriority(pattern.priority),
        hasTrailingSuffix: RegExp(r'[A-Z]$').hasMatch(normalizedPlate) &&
            RegExp(r'[0-9]').hasMatch(normalizedPlate),
      );
    }

    if (pattern.id == 'FUTURE_SPECIAL_SERIES' &&
        isFutureSpecialSeriesCandidate(normalizedPlate)) {
      return PatternValidationResult(
        isValid: true,
        pattern: pattern,
        category: pattern.category,
        score: _scoreFromPriority(pattern.priority),
        hasTrailingSuffix: RegExp(r'[A-Z]$').hasMatch(normalizedPlate) &&
            RegExp(r'[0-9]').hasMatch(normalizedPlate),
      );
    }

    if (pattern.regex.hasMatch(normalizedPlate)) {
      return PatternValidationResult(
        isValid: true,
        pattern: pattern,
        category: pattern.category,
        score: _scoreFromPriority(pattern.priority),
        hasTrailingSuffix: pattern.hasTrailingSuffix,
      );
    }
  }

  return PatternValidationResult(
    isValid: false,
    category: PlateCategory.unknownValidCandidate,
    score: 0.1,
    hasTrailingSuffix: RegExp(r'[A-Z]$').hasMatch(normalizedPlate) &&
        RegExp(r'[0-9]').hasMatch(normalizedPlate),
  );
}

double _scoreFromPriority(int priority) {
  final value = priority / 100;
  return value > 1 ? 1 : value;
}
