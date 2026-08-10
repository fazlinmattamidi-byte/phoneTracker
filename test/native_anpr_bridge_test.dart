import 'package:flutter_test/flutter_test.dart';
import 'package:plateq_mobile/src/anpr/native_anpr_bridge.dart';

void main() {
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
      'ocrProvider': 'PENDING_PHASE_11',
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
    expect(runtime.ocrProvider, 'PENDING_PHASE_11');
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
}
