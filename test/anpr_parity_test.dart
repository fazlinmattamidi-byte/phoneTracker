import 'package:flutter_test/flutter_test.dart';
import 'package:plateq_mobile/src/anpr/consensus.dart';
import 'package:plateq_mobile/src/anpr/evidence_scoring.dart';
import 'package:plateq_mobile/src/anpr/malaysian_patterns.dart';
import 'package:plateq_mobile/src/anpr/matching_engine.dart';
import 'package:plateq_mobile/src/anpr/normaliser.dart';
import 'package:plateq_mobile/src/anpr/plate_types.dart';
import 'package:plateq_mobile/src/anpr/special_series.dart';
import 'package:plateq_mobile/src/core/domain.dart';

void main() {
  tearDown(resetRuntimeSpecialSeriesPrefixes);

  test('scores evidence frames using the weighted quality formula', () {
    final score = scoreEvidenceFrameQuality(
      const EvidenceFrameScoreComponents(
        sharpness: 0.8,
        plateSize: 0.6,
        ocrConfidence: 0.9,
        motionBlur: 0.7,
        perspective: 0.5,
      ),
    );

    expect(score, closeTo(0.73, 0.00001));
  });

  test('normalizes plate strings preserving suffixes and long words', () {
    expect(normalizePlate('  jSd-8888  '), 'JSD8888');
    expect(normalizePlate('kv 1234 e'), 'KV1234E');
    expect(normalizePlate('w 1234 a'), 'W1234A');
    expect(normalizePlate('ev-1234'), 'EV1234');
    expect(normalizePlate('putrajaya 1234'), 'PUTRAJAYA1234');
  });

  test('formats display plates with clear spacing', () {
    expect(formatDisplayPlate('JSD8888'), 'JSD 8888');
    expect(formatDisplayPlate('EV1234'), 'EV 1234');
    expect(formatDisplayPlate('KV1234E'), 'KV 1234 E');
    expect(formatDisplayPlate('W1234A'), 'W 1234 A');
    expect(formatDisplayPlate('MALAYSIA200'), 'MALAYSIA 200');
    expect(formatDisplayPlate('PUTRAJAYA1'), 'PUTRAJAYA 1');
    expect(formatDisplayPlate('WXY77B8'), 'WXY 77 B8');
  });

  test('validates Malaysian plate pattern categories', () {
    expect(
        validateMalaysianPattern('EV1234').category, PlateCategory.evSpecial);
    expect(
        validateMalaysianPattern('EVA12345').category, PlateCategory.evSpecial);
    expect(
        validateMalaysianPattern('KV1234E').category, PlateCategory.langkawi);
    expect(validateMalaysianPattern('W1234A').category,
        PlateCategory.letterNumberSuffix);
    expect(validateMalaysianPattern('SAB1234').category, PlateCategory.sabah);
    expect(validateMalaysianPattern('QAB1234').category, PlateCategory.sarawak);
    expect(validateMalaysianPattern('QAA1234').category, PlateCategory.sarawak);
    expect(validateMalaysianPattern('PUTRAJAYA1234').category,
        PlateCategory.putrajaya);
    expect(
        validateMalaysianPattern('1122DP').category, PlateCategory.diplomatic);
    expect(
        validateMalaysianPattern('Z1234').category, PlateCategory.government);
    expect(validateMalaysianPattern('PATRIOT123').category,
        PlateCategory.specialSeries);
    expect(validateMalaysianPattern('MALAYSIA200').category,
        PlateCategory.specialSeries);
    expect(validateMalaysianPattern('MADANI888').category,
        PlateCategory.specialSeries);
    expect(validateMalaysianPattern('VIP88').category,
        PlateCategory.specialSeries);
    expect(
        validateMalaysianPattern('FF99').category, PlateCategory.specialSeries);
    expect(validateMalaysianPattern('QV999').category,
        PlateCategory.specialSeries);
    expect(validateMalaysianPattern('VEP1234').category,
        PlateCategory.institutional);
    expect(
        validateMalaysianPattern('JSD8888').category, PlateCategory.standard);
    expect(validateMalaysianPattern('ABC123').category, PlateCategory.standard);
    expect(validateMalaysianPattern('WWW888').category,
        PlateCategory.specialSeries);
    expect(validateMalaysianPattern('A1').category, PlateCategory.standard);
    expect(validateMalaysianPattern('JQ1234').category, PlateCategory.standard);
  });

  test('generates OCR confusion candidates', () {
    expect(generateCandidatePlates('WXY77B8'), contains('WXY7788'));
    expect(generateCandidatePlates('G0LD88'), contains('GOLD88'));
    expect(generateCandidatePlates('SRM3028'), contains('SAM3028'));
  });

  test('corrects special series OCR using Malaysian context', () {
    expect(correctMalaysianPlateOcr('MALAYS1A200').normalized, 'MALAYSIA200');
    expect(
      correctMalaysianPlateOcr(
        'MALAYSA200',
        options: const SpecialPlateCorrectionOptions(ocrConfidence: 0.96),
      ).normalized,
      'MALAYSIA200',
    );
    expect(
      correctMalaysianPlateOcr(
        'MALRYSIA2020',
        options: const SpecialPlateCorrectionOptions(ocrConfidence: 0.93),
      ).normalized,
      'MALAYSIA2020',
    );
    expect(correctMalaysianPlateOcr('MADA N1888').normalized, 'MADANI888');
    expect(correctMalaysianPlateOcr('PUTRAJAYA I').normalized, 'PUTRAJAYA1');
    expect(correctMalaysianPlateOcr('WWWI').normalized, 'WWW1');
    expect(correctMalaysianPlateOcr('G0LD88').normalized, 'GOLD88');
    expect(
      correctMalaysianPlateOcr(
        'JSD8888',
        options: const SpecialPlateCorrectionOptions(ocrConfidence: 0.99),
      ).normalized,
      'JSD8888',
    );
  });

  test('corrects conservative Malaysian typography confusions', () {
    expect(
      correctMalaysianTypographyOcr(
        'SRM3028',
        options: const TypographyCorrectionOptions(ocrConfidence: 0.97),
      ).normalized,
      'SAM3028',
    );
    expect(
      correctMalaysianTypographyOcr(
        'JRD8888',
        options: const TypographyCorrectionOptions(ocrConfidence: 0.97),
      ).normalized,
      'JRD8888',
    );
    expect(isPossibleMatch('SRM3028', 'SAM3028'), isTrue);
  });

  test('ranks registered special prefixes by probability evidence', () {
    final topMalaysia = rankSpecialSeriesPrefixCandidates(
      'MALAYSA200',
      options: const SpecialPlateCorrectionOptions(ocrConfidence: 0.96),
    ).first;
    expect(topMalaysia.plate, 'MALAYSIA200');
    expect(topMalaysia.editDistance, 1);
    expect(topMalaysia.score, greaterThan(0.8));

    final topPutrajaya = rankSpecialSeriesPrefixCandidates(
      'PUTRAJYA88',
      options: const SpecialPlateCorrectionOptions(ocrConfidence: 0.94),
    ).first;
    expect(topPutrajaya.plate, 'PUTRAJAYA88');
    expect(topPutrajaya.prefixProbability, greaterThan(0.75));
  });

  test('accepts runtime special prefixes', () {
    setRuntimeSpecialSeriesPrefixes(['RX']);
    expect(
        validateMalaysianPattern('RX1').category, PlateCategory.specialSeries);
    expect(formatDisplayPlate('RX1'), 'RX 1');
  });

  test('detects possible matches and repeated-character omissions', () {
    expect(isPossibleMatch('WXY77B8', 'WXY7788'), isTrue);
    expect(isPossibleMatch('JSD8888', 'ABC9999'), isFalse);
    expect(isRepeatedCharacterOmission('AN7569', 'ANN7569'), isTrue);
    expect(isRepeatedCharacterOmission('AB7569', 'ANN7569'), isFalse);
  });

  test('evaluates database matching with the mobile seed repository', () {
    final exact = evaluateDatabaseMatch('ANN7569', 0.95, seedVehicles);
    expect(exact.matchType, MatchType.exact);
    expect(exact.matchedVehicle?.customerName, 'Ahmad');

    final repeated = evaluateDatabaseMatch('AN7569', 0.95, seedVehicles);
    expect(repeated.matchType, MatchType.exact);
    expect(repeated.normalizedPlate, 'ANN7569');

    final possible = evaluateDatabaseMatch('W8821B', 0.85, seedVehicles);
    expect(possible.matchType, MatchType.possible);
    expect(possible.possibleMatches, isNotEmpty);

    final none = evaluateDatabaseMatch('ABC9999', 0.90, seedVehicles);
    expect(none.matchType, MatchType.none);

    final low = evaluateDatabaseMatch('ANN7569', 0.40, seedVehicles);
    expect(low.matchType, MatchType.insufficientConfidence);
  });

  test('evaluates multi-frame consensus voting', () {
    final consensus = evaluateConsensus(
      const <String, OcrVote>{
        'VAB1234': OcrVote(count: 3, totalConfidence: 2.7),
        'VAB123A': OcrVote(count: 1, totalConfidence: 0.7),
      },
      requiredVotes: 3,
      minConfidence: 0.65,
    );

    expect(consensus.isStabilized, isTrue);
    expect(consensus.normalizedPlate, 'VAB1234');
    expect(consensus.displayPlate, 'VAB 1234');
  });

  test('promotes database-corrected OCR votes', () {
    final promoted = promoteCorrectedOcrVote(
      const <String, OcrVote>{
        'AN7569': OcrVote(count: 2, totalConfidence: 1.3),
      },
      'AN7569',
      'ANN7569',
      confidence: 0.62,
    );

    expect(promoted.containsKey('AN7569'), isFalse);
    expect(promoted['ANN7569']?.count, 2);
  });
}
