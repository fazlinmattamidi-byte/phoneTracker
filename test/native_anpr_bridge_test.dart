import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plateq_mobile/src/anpr/native_anpr_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const modelChannel = MethodChannel('plateq.app/models');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(modelChannel, null);
  });

  test('parses native runtime environment and quality fields', () {
    final event = AnprEvent.fromDynamic(const <String, Object?>{
      'type': 'runtime',
      'timestamp': '2026-08-10T04:00:00.000Z',
      'runtimeState': 'SCANNING',
      'deviceTier': 'AUTO',
      'cameraFps': 29.8,
      'detectorFps': 9.6,
      'ocrQueueDepth': 0,
      'detectorProvider': 'NATIVE_HEURISTIC',
      'ocrProvider': 'NATIVE_FALLBACK_OCR',
      'environmentProvider': 'NATIVE_HEURISTIC',
      'plateQualityProvider': 'NATIVE_HEURISTIC',
      'environmentLabel': 'GLARE',
      'environmentConfidence': 0.88,
      'plateQualityScore': 0.61,
      'plateQualityClass': 'GLARE_REFLECTION',
    });

    expect(event, isA<RuntimeAnprEvent>());
    final runtime = event as RuntimeAnprEvent;
    expect(runtime.detectorProvider, 'NATIVE_HEURISTIC');
    expect(runtime.ocrProvider, 'NATIVE_FALLBACK_OCR');
    expect(runtime.environmentLabel, 'GLARE');
    expect(runtime.environmentConfidence, 0.88);
    expect(runtime.plateQualityClass, 'GLARE_REFLECTION');
    expect(runtime.plateQualityScore, 0.61);
  });

  test('parses native track quality fields', () {
    final event = AnprEvent.fromDynamic(const <String, Object?>{
      'type': 'trackUpdate',
      'timestamp': '2026-08-10T04:00:00.000Z',
      'tracks': <Object?>[
        <String, Object?>{
          'trackId': 'track-7',
          'state': 'VISIBLE',
          'pipelineState': 'READY_FOR_OCR',
          'currentPlate': '',
          'confidence': 0.72,
          'detectorConfidence': 0.81,
          'motionScore': 0.12,
          'qualityScore': 0.68,
          'qualityClass': 'STANDARD_RECTANGLE',
          'matchType': 'NONE',
          'bbox': <String, Object?>{
            'x': 0.28,
            'y': 0.62,
            'width': 0.32,
            'height': 0.09,
          },
        },
      ],
    });

    expect(event, isA<TrackUpdateAnprEvent>());
    final track = (event as TrackUpdateAnprEvent).tracks.single;
    expect(track.trackId, 'track-7');
    expect(track.detectorConfidence, 0.81);
    expect(track.motionScore, 0.12);
    expect(track.qualityScore, 0.68);
    expect(track.qualityClass, 'STANDARD_RECTANGLE');
    expect(track.bbox.width, 0.32);
  });

  test('parses native OCR events', () {
    final event = AnprEvent.fromDynamic(const <String, Object?>{
      'type': 'ocr',
      'timestamp': '2026-08-10T04:00:00.000Z',
      'trackId': 'track-7',
      'rawText': 'ANN7569',
      'normalizedPlate': 'ANN7569',
      'displayPlate': 'ANN 7569',
      'confidence': 0.86,
      'layout': 'SINGLE_LINE',
      'category': 'STANDARD',
      'patternScore': 0.84,
      'provider': 'CPU_ONNX_PP_OCR',
      'vehicleImagePath': '/tmp/vehicle.jpg',
      'plateImagePath': '/tmp/plate.jpg',
      'plateEnhancedImagePath': '/tmp/plate-enhanced.jpg',
      'plateBinaryImagePath': '/tmp/plate-binary.jpg',
      'plateTopLineImagePath': '/tmp/plate-top-line.jpg',
      'plateBottomLineImagePath': '/tmp/plate-bottom-line.jpg',
      'plateInnerTextImagePath': '/tmp/plate-inner-text.jpg',
      'plateCropWidth': 180,
      'plateCropHeight': 42,
      'preprocessingVariant': 'ADAPTIVE_CONTRAST',
      'preprocessingVariants': <Object?>[
        'RAW_CROP',
        'ADAPTIVE_CONTRAST',
        'BINARY_THRESHOLD',
        'TOP_LINE',
        'BOTTOM_LINE',
        'INNER_TEXT',
      ],
      'characterConfidences': <Object?>[
        <String, Object?>{
          'char': 'A',
          'confidence': 0.91,
          'position': 0,
        },
      ],
    });

    expect(event, isA<OcrAnprEvent>());
    final ocr = event as OcrAnprEvent;
    expect(ocr.trackId, 'track-7');
    expect(ocr.normalizedPlate, 'ANN7569');
    expect(ocr.displayPlate, 'ANN 7569');
    expect(ocr.confidence, 0.86);
    expect(ocr.provider, 'CPU_ONNX_PP_OCR');
    expect(ocr.vehicleImagePath, '/tmp/vehicle.jpg');
    expect(ocr.plateImagePath, '/tmp/plate.jpg');
    expect(ocr.plateEnhancedImagePath, '/tmp/plate-enhanced.jpg');
    expect(ocr.plateBinaryImagePath, '/tmp/plate-binary.jpg');
    expect(ocr.plateTopLineImagePath, '/tmp/plate-top-line.jpg');
    expect(ocr.plateBottomLineImagePath, '/tmp/plate-bottom-line.jpg');
    expect(ocr.plateInnerTextImagePath, '/tmp/plate-inner-text.jpg');
    expect(ocr.plateCropWidth, 180);
    expect(ocr.plateCropHeight, 42);
    expect(ocr.preprocessingVariant, 'ADAPTIVE_CONTRAST');
    expect(ocr.preprocessingVariants, contains('BINARY_THRESHOLD'));
    expect(ocr.preprocessingVariants, contains('INNER_TEXT'));
    expect(ocr.characterConfidences.single.char, 'A');
  });

  test('verifies packaged model assets using Flutter asset keys', () async {
    expect(
      NativeAnprBridge.modelAssetPaths['detector'],
      'public/models/plate-detector.onnx',
    );

    final assets = await NativeAnprBridge.verifyModelAssets();
    final requiredAssets = assets.where((asset) => asset.required).toList();
    final missingRequired =
        requiredAssets.where((asset) => !asset.available).toList();

    expect(requiredAssets, hasLength(5));
    expect(missingRequired, isEmpty);
    expect(
      assets.firstWhere((asset) => asset.id == 'detector').sizeBytes,
      greaterThan(0),
    );
    expect(
      assets.firstWhere((asset) => asset.id == 'plateQuality').required,
      isFalse,
    );
  });

  test('stages available model assets onto native paths', () async {
    final stagedIds = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(modelChannel, (MethodCall call) async {
      expect(call.method, 'stageModelAsset');
      final args = Map<String, Object?>.from(call.arguments as Map);
      final id = args['id']! as String;
      final path = args['path']! as String;
      final required = args['required']! as bool;
      final bytes = args['bytes']! as Uint8List;
      expect(bytes.length, greaterThan(0));
      stagedIds.add(id);
      return <String, Object?>{
        'id': id,
        'path': path,
        'required': required,
        'available': true,
        'sizeBytes': bytes.length,
        'nativePath': '/native/plateq-models/$id',
      };
    });

    final assets = await NativeAnprBridge.verifyModelAssets();
    final staged = await NativeAnprBridge.stageModelAssets(assets);
    final detector = staged.firstWhere((asset) => asset.id == 'detector');
    final plateQuality =
        staged.firstWhere((asset) => asset.id == 'plateQuality');

    expect(detector.nativeReady, isTrue);
    expect(detector.nativePath, '/native/plateq-models/detector');
    expect(stagedIds, containsAll(NativeAnprBridge.requiredModelAssetIds));
    expect(plateQuality.available, isFalse);
    expect(plateQuality.nativePath, isNull);
  });
}
