import '../core/domain.dart';
import 'malaysian_patterns.dart';
import 'normaliser.dart';
import 'plate_types.dart';
import 'special_series.dart';

class MatchEvaluationResult {
  const MatchEvaluationResult({
    required this.matchType,
    required this.matchedVehicle,
    required this.possibleMatches,
    required this.confidence,
    required this.normalizedPlate,
    required this.category,
    required this.reason,
  });

  final MatchType matchType;
  final Vehicle? matchedVehicle;
  final List<Vehicle> possibleMatches;
  final double confidence;
  final String normalizedPlate;
  final PlateCategory category;
  final String reason;
}

MatchEvaluationResult evaluateDatabaseMatch(
  String ocrReading,
  double ocrConfidence,
  List<Vehicle> allVehicles, {
  List<CharacterConfidence>? characterConfidences,
  double minConfidenceThreshold = 0.65,
}) {
  final correction = correctMalaysianPlateOcr(
    ocrReading,
    options: SpecialPlateCorrectionOptions(
      ocrConfidence: ocrConfidence,
      characterConfidences: characterConfidences,
    ),
  );
  final normalized = correction.normalized.isNotEmpty
      ? correction.normalized
      : normalizePlate(ocrReading);
  final pattern = validateMalaysianPattern(normalized);

  if (normalized.isEmpty || normalized.length < 2) {
    return MatchEvaluationResult(
      matchType: MatchType.insufficientConfidence,
      matchedVehicle: null,
      possibleMatches: const <Vehicle>[],
      confidence: ocrConfidence,
      normalizedPlate: normalized,
      category: pattern.category,
      reason: 'Reading too short or empty',
    );
  }

  if (ocrConfidence < minConfidenceThreshold) {
    return MatchEvaluationResult(
      matchType: MatchType.insufficientConfidence,
      matchedVehicle: null,
      possibleMatches: const <Vehicle>[],
      confidence: ocrConfidence,
      normalizedPlate: normalized,
      category: pattern.category,
      reason:
          'Confidence (${(ocrConfidence * 100).round()}%) below threshold (${(minConfidenceThreshold * 100).round()}%)',
    );
  }

  final exactVehicle = _firstWhereOrNull(
    allVehicles,
    (vehicle) =>
        _isOpenCase(vehicle) && normalizePlate(vehicle.plate) == normalized,
  );

  if (exactVehicle != null) {
    return MatchEvaluationResult(
      matchType: MatchType.exact,
      matchedVehicle: exactVehicle,
      possibleMatches: const <Vehicle>[],
      confidence: ocrConfidence,
      normalizedPlate: normalized,
      category: pattern.category,
      reason: 'Exact normalized plate equality',
    );
  }

  final closedVehicle = _firstWhereOrNull(
    allVehicles,
    (vehicle) =>
        !_isOpenCase(vehicle) && normalizePlate(vehicle.plate) == normalized,
  );

  if (closedVehicle != null) {
    return MatchEvaluationResult(
      matchType: MatchType.none,
      matchedVehicle: null,
      possibleMatches: const <Vehicle>[],
      confidence: ocrConfidence,
      normalizedPlate: normalized,
      category: pattern.category,
      reason: 'Case is closed',
    );
  }

  final repeatedOmissionMatches = allVehicles
      .where((vehicle) =>
          _isOpenCase(vehicle) &&
          isRepeatedCharacterOmission(
              normalized, normalizePlate(vehicle.plate)))
      .toList();

  if (repeatedOmissionMatches.length == 1 &&
      ocrConfidence >= _max(minConfidenceThreshold, 0.58)) {
    final correctedVehicle = repeatedOmissionMatches.first;
    final correctedPlate = normalizePlate(correctedVehicle.plate);
    final correctedPattern = validateMalaysianPattern(correctedPlate);
    return MatchEvaluationResult(
      matchType: MatchType.exact,
      matchedVehicle: correctedVehicle,
      possibleMatches: const <Vehicle>[],
      confidence: _min(1, ocrConfidence * 0.94),
      normalizedPlate: correctedPlate,
      category: correctedPattern.category,
      reason: 'Recovered repeated-character OCR omission',
    );
  }

  final candidates = generateCandidatePlates(
    normalized,
    charConfidences: characterConfidences,
    maxPermutations: 10,
  );
  final possibleVehicles = <Vehicle>[];

  for (final candidate in candidates) {
    final vehicle = _firstWhereOrNull(
      allVehicles,
      (item) => _isOpenCase(item) && normalizePlate(item.plate) == candidate,
    );
    if (vehicle != null &&
        !possibleVehicles.any((item) => item.id == vehicle.id)) {
      possibleVehicles.add(vehicle);
    }
  }

  if (possibleVehicles.isEmpty) {
    for (final vehicle in allVehicles) {
      if (!_isOpenCase(vehicle)) continue;
      if (isPossibleMatch(normalized, normalizePlate(vehicle.plate))) {
        possibleVehicles.add(vehicle);
      }
    }
  }

  if (possibleVehicles.isNotEmpty) {
    return MatchEvaluationResult(
      matchType: MatchType.possible,
      matchedVehicle: null,
      possibleMatches: possibleVehicles,
      confidence: ocrConfidence * 0.90,
      normalizedPlate: normalized,
      category: pattern.category,
      reason:
          'Possible match with ${possibleVehicles.length} registered active case(s)',
    );
  }

  return MatchEvaluationResult(
    matchType: MatchType.none,
    matchedVehicle: null,
    possibleMatches: const <Vehicle>[],
    confidence: ocrConfidence,
    normalizedPlate: normalized,
    category: pattern.category,
    reason: 'Valid Malaysian plate pattern, no active case in repository',
  );
}

bool _isOpenCase(Vehicle vehicle) {
  return vehicle.status != VehicleStatus.cleared;
}

double _min(double a, double b) => a < b ? a : b;
double _max(double a, double b) => a > b ? a : b;

T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T value) test) {
  for (final value in values) {
    if (test(value)) return value;
  }
  return null;
}
