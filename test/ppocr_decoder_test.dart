import 'package:flutter_test/flutter_test.dart';
import 'package:plateq_mobile/src/anpr/native_anpr_bridge.dart';
import 'package:plateq_mobile/src/anpr/ppocr_decoder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('decodes PP-OCR CTC timesteps with blanks and repeated classes', () {
    const dictionary =
        PpOcrDictionary(<String>['A', 'N', '7', '5', '6', '9', ' ']);
    final decoded = decodePpOcrCtcTimesteps(
      <List<double>>[
        _scores(1, 0.91, dictionary.classCount),
        _scores(1, 0.87, dictionary.classCount),
        _scores(0, 0.99, dictionary.classCount),
        _scores(2, 0.88, dictionary.classCount),
        _scores(2, 0.80, dictionary.classCount),
        _scores(3, 0.82, dictionary.classCount),
        _scores(4, 0.81, dictionary.classCount),
        _scores(5, 0.80, dictionary.classCount),
        _scores(6, 0.79, dictionary.classCount),
        _scores(7, 0.77, dictionary.classCount),
      ],
      dictionary,
    );

    expect(decoded.rawText, 'AN7569');
    expect(decoded.characterConfidences.map((item) => item.char), <String>[
      'A',
      'N',
      '7',
      '5',
      '6',
      '9',
    ]);
    expect(decoded.characterConfidences.last.position, 5);
    expect(decoded.confidence, closeTo(0.835, 0.0001));
  });

  test('decodes flattened PP-OCR output tensors', () {
    const dictionary = PpOcrDictionary(<String>['A', 'B']);
    final flat = <double>[
      ..._scores(1, 0.90, dictionary.classCount),
      ..._scores(0, 0.99, dictionary.classCount),
      ..._scores(2, 0.86, dictionary.classCount),
      ..._scores(2, 0.81, dictionary.classCount),
      ..._scores(1, 0.82, dictionary.classCount),
    ];

    final decoded = decodePpOcrCtcFlat(
      flat,
      dictionary,
      sequenceLength: 5,
      classCount: dictionary.classCount,
    );

    expect(decoded.rawText, 'ABA');
    expect(decoded.characterConfidences.map((item) => item.position), <int>[
      0,
      1,
      2,
    ]);
  });

  test('loads the packaged PP-OCR dictionary asset', () async {
    final dictionary = await PpOcrDictionary.fromAsset(
      NativeAnprBridge.modelAssetPaths['ocrDictionary']!,
    );

    expect(dictionary.entries.length, greaterThan(6000));
    expect(dictionary.entries, contains('A'));
    expect(dictionary.entries, contains('N'));
    expect(dictionary.entries, contains('9'));
    expect(dictionary.entries.last, ' ');
  });
}

List<double> _scores(int winner, double confidence, int classCount) {
  return List<double>.generate(
    classCount,
    (index) => index == winner ? confidence : 0.01,
  );
}
