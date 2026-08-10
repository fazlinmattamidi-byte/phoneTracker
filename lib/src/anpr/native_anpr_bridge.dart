import 'dart:async';

import 'package:flutter/services.dart';

class NativeAnprBridge {
  static const MethodChannel _methods = MethodChannel('plateq.anpr/methods');
  static const EventChannel _events = EventChannel('plateq.anpr/events');

  Stream<AnprEvent> get events {
    return _events.receiveBroadcastStream().map(AnprEvent.fromDynamic);
  }

  Future<NativeRuntimeStatus> initialize() async {
    final result = await _methods.invokeMethod<Map<dynamic, dynamic>>(
      'initialize',
      <String, Object?>{
        'modelAssets': const <String, String>{
          'detector': 'assets/public/models/plate-detector.onnx',
          'ocr': 'assets/public/models/ppocr-rec.onnx',
          'ocrDictionary': 'assets/public/models/ppocr-dict.txt',
          'environment': 'assets/public/models/environment-classifier.onnx',
          'environmentMetadata':
              'assets/public/models/environment-classifier.metadata.json',
          'plateQuality': 'assets/public/models/plate-quality-classifier.onnx',
          'plateQualityMetadata':
              'assets/public/models/plate-quality-classifier.metadata.json',
        },
        'deviceTier': 'AUTO',
        'enableHardwareAcceleration': true,
      },
    );
    return NativeRuntimeStatus.fromMap(
        Map<String, dynamic>.from(result ?? const <String, dynamic>{}));
  }

  Future<List<NativeCameraDevice>> listCameras() async {
    final result = await _methods.invokeMethod<List<dynamic>>('listCameras');
    return (result ?? const <dynamic>[])
        .map((item) => NativeCameraDevice.fromMap(_asMap(item)))
        .toList();
  }

  Future<void> selectCamera(String cameraId) {
    return _methods.invokeMethod<void>(
        'selectCamera', <String, Object?>{'cameraId': cameraId});
  }

  Future<void> startScanning({
    required String cameraId,
    required double detectionThreshold,
    required double recognitionThreshold,
    required int consensusVotes,
    required int maxTracks,
    required int maxOcrConcurrency,
    required bool enableSpecialSeries,
  }) {
    return _methods.invokeMethod<void>(
      'startScanning',
      <String, Object?>{
        'cameraId': cameraId,
        'settings': <String, Object?>{
          'detectionThreshold': detectionThreshold,
          'recognitionThreshold': recognitionThreshold,
          'consensusVotes': consensusVotes,
          'maxTracks': maxTracks,
          'maxOcrConcurrency': maxOcrConcurrency,
          'enableSpecialSeries': enableSpecialSeries,
          'scannerMode': 'MULTI_VEHICLE',
        },
      },
    );
  }

  Future<void> updateSettings({
    required double detectionThreshold,
    required double recognitionThreshold,
    required int consensusVotes,
    required int maxTracks,
    required int maxOcrConcurrency,
    required bool enableSpecialSeries,
  }) {
    return _methods.invokeMethod<void>(
      'updateSettings',
      <String, Object?>{
        'settings': <String, Object?>{
          'detectionThreshold': detectionThreshold,
          'recognitionThreshold': recognitionThreshold,
          'consensusVotes': consensusVotes,
          'maxTracks': maxTracks,
          'maxOcrConcurrency': maxOcrConcurrency,
          'enableSpecialSeries': enableSpecialSeries,
          'scannerMode': 'MULTI_VEHICLE',
        },
      },
    );
  }

  Future<void> stopScanning() {
    return _methods.invokeMethod<void>('stopScanning');
  }

  Future<void> setFacing(String facing) {
    return _methods
        .invokeMethod<void>('setFacing', <String, Object?>{'facing': facing});
  }

  Future<void> dispose() {
    return _methods.invokeMethod<void>('dispose');
  }
}

class NativeRuntimeStatus {
  const NativeRuntimeStatus({
    required this.runtimeState,
    required this.deviceTier,
    required this.detectorProvider,
    required this.ocrProvider,
    required this.environmentProvider,
    required this.plateQualityProvider,
    required this.warnings,
  });

  final String runtimeState;
  final String deviceTier;
  final String detectorProvider;
  final String ocrProvider;
  final String environmentProvider;
  final String plateQualityProvider;
  final List<String> warnings;

  factory NativeRuntimeStatus.fromMap(Map<String, dynamic> map) {
    return NativeRuntimeStatus(
      runtimeState: (map['runtimeState'] as String?) ?? 'UNINITIALIZED',
      deviceTier: (map['deviceTier'] as String?) ?? 'AUTO',
      detectorProvider: (map['detectorProvider'] as String?) ?? 'NONE',
      ocrProvider: (map['ocrProvider'] as String?) ?? 'NONE',
      environmentProvider: (map['environmentProvider'] as String?) ?? 'NONE',
      plateQualityProvider: (map['plateQualityProvider'] as String?) ?? 'NONE',
      warnings: ((map['warnings'] as List<dynamic>?) ?? const <dynamic>[])
          .map(Stringify.value)
          .toList(),
    );
  }
}

class NativeCameraDevice {
  const NativeCameraDevice({
    required this.id,
    required this.label,
    required this.facing,
    required this.isDefault,
  });

  final String id;
  final String label;
  final String facing;
  final bool isDefault;

  factory NativeCameraDevice.fromMap(Map<String, dynamic> map) {
    return NativeCameraDevice(
      id: (map['id'] as String?) ?? '',
      label: (map['label'] as String?) ?? 'Camera',
      facing: (map['facing'] as String?) ?? 'BACK',
      isDefault: (map['isDefault'] as bool?) ?? false,
    );
  }
}

sealed class AnprEvent {
  const AnprEvent({required this.type, required this.timestamp});

  final String type;
  final DateTime timestamp;

  factory AnprEvent.fromDynamic(dynamic raw) {
    final map = _asMap(raw);
    final type = (map['type'] as String?) ?? 'unknown';
    switch (type) {
      case 'runtime':
        return RuntimeAnprEvent.fromMap(map);
      case 'trackUpdate':
        return TrackUpdateAnprEvent.fromMap(map);
      case 'matchAlert':
        return MatchAlertAnprEvent.fromMap(map);
      case 'error':
        return ErrorAnprEvent.fromMap(map);
      default:
        return UnknownAnprEvent(
          type: type,
          timestamp: _readTimestamp(map),
          payload: map,
        );
    }
  }
}

class RuntimeAnprEvent extends AnprEvent {
  const RuntimeAnprEvent({
    required super.timestamp,
    required this.runtimeState,
    required this.deviceTier,
    required this.cameraFps,
    required this.detectorFps,
    required this.ocrQueueDepth,
    required this.detectorProvider,
    required this.ocrProvider,
    required this.environmentProvider,
    required this.plateQualityProvider,
    required this.environmentLabel,
    required this.environmentConfidence,
    required this.plateQualityScore,
    required this.plateQualityClass,
  }) : super(type: 'runtime');

  final String runtimeState;
  final String deviceTier;
  final double cameraFps;
  final double detectorFps;
  final int ocrQueueDepth;
  final String detectorProvider;
  final String ocrProvider;
  final String environmentProvider;
  final String plateQualityProvider;
  final String environmentLabel;
  final double environmentConfidence;
  final double plateQualityScore;
  final String plateQualityClass;

  factory RuntimeAnprEvent.fromMap(Map<String, dynamic> map) {
    return RuntimeAnprEvent(
      timestamp: _readTimestamp(map),
      runtimeState: (map['runtimeState'] as String?) ?? 'UNKNOWN',
      deviceTier: (map['deviceTier'] as String?) ?? 'AUTO',
      cameraFps: _readDouble(map['cameraFps']),
      detectorFps: _readDouble(map['detectorFps']),
      ocrQueueDepth: _readInt(map['ocrQueueDepth']),
      detectorProvider: (map['detectorProvider'] as String?) ?? 'NONE',
      ocrProvider: (map['ocrProvider'] as String?) ?? 'NONE',
      environmentProvider: (map['environmentProvider'] as String?) ?? 'NONE',
      plateQualityProvider: (map['plateQualityProvider'] as String?) ?? 'NONE',
      environmentLabel:
          (map['environmentLabel'] as String?) ?? 'GOOD_CONDITION',
      environmentConfidence: _readDouble(map['environmentConfidence']),
      plateQualityScore: _readDouble(map['plateQualityScore']),
      plateQualityClass: (map['plateQualityClass'] as String?) ?? 'UNKNOWN',
    );
  }
}

class TrackUpdateAnprEvent extends AnprEvent {
  const TrackUpdateAnprEvent({
    required super.timestamp,
    required this.tracks,
  }) : super(type: 'trackUpdate');

  final List<AnprTrack> tracks;

  factory TrackUpdateAnprEvent.fromMap(Map<String, dynamic> map) {
    return TrackUpdateAnprEvent(
      timestamp: _readTimestamp(map),
      tracks: ((map['tracks'] as List<dynamic>?) ?? const <dynamic>[])
          .map((item) => AnprTrack.fromMap(_asMap(item)))
          .toList(),
    );
  }
}

class MatchAlertAnprEvent extends AnprEvent {
  const MatchAlertAnprEvent({
    required super.timestamp,
    required this.alert,
  }) : super(type: 'matchAlert');

  final AnprAlert alert;

  factory MatchAlertAnprEvent.fromMap(Map<String, dynamic> map) {
    return MatchAlertAnprEvent(
      timestamp: _readTimestamp(map),
      alert: AnprAlert.fromMap(map),
    );
  }
}

class ErrorAnprEvent extends AnprEvent {
  const ErrorAnprEvent({
    required super.timestamp,
    required this.code,
    required this.message,
    required this.recoverable,
  }) : super(type: 'error');

  final String code;
  final String message;
  final bool recoverable;

  factory ErrorAnprEvent.fromMap(Map<String, dynamic> map) {
    return ErrorAnprEvent(
      timestamp: _readTimestamp(map),
      code: (map['code'] as String?) ?? 'UNKNOWN',
      message: (map['message'] as String?) ?? 'Unknown scanner error',
      recoverable: (map['recoverable'] as bool?) ?? false,
    );
  }
}

class UnknownAnprEvent extends AnprEvent {
  const UnknownAnprEvent({
    required super.type,
    required super.timestamp,
    required this.payload,
  });

  final Map<String, dynamic> payload;
}

class AnprTrack {
  const AnprTrack({
    required this.trackId,
    required this.state,
    required this.pipelineState,
    required this.plate,
    required this.confidence,
    required this.detectorConfidence,
    required this.motionScore,
    required this.qualityScore,
    required this.qualityClass,
    required this.bbox,
    required this.matchType,
  });

  final String trackId;
  final String state;
  final String pipelineState;
  final String plate;
  final double confidence;
  final double detectorConfidence;
  final double motionScore;
  final double qualityScore;
  final String qualityClass;
  final NormalizedBbox bbox;
  final String matchType;

  factory AnprTrack.fromMap(Map<String, dynamic> map) {
    return AnprTrack(
      trackId: (map['trackId'] as String?) ?? '',
      state: (map['state'] as String?) ?? 'VISIBLE',
      pipelineState: (map['pipelineState'] as String?) ?? 'DETECTED',
      plate: (map['currentPlate'] as String?) ?? '',
      confidence: _readDouble(map['confidence']),
      detectorConfidence: _readDouble(map['detectorConfidence']),
      motionScore: _readDouble(map['motionScore']),
      qualityScore: _readDouble(map['qualityScore']),
      qualityClass: (map['qualityClass'] as String?) ?? 'UNKNOWN',
      bbox: NormalizedBbox.fromMap(_asMap(map['bbox'])),
      matchType: (map['matchType'] as String?) ?? 'NONE',
    );
  }
}

class NormalizedBbox {
  const NormalizedBbox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  factory NormalizedBbox.fromMap(Map<String, dynamic> map) {
    return NormalizedBbox(
      x: _readDouble(map['x']),
      y: _readDouble(map['y']),
      width: _readDouble(map['width']),
      height: _readDouble(map['height']),
    );
  }
}

class AnprAlert {
  const AnprAlert({
    required this.trackId,
    required this.plate,
    required this.confidence,
    required this.matchType,
    required this.cameraLabel,
    required this.reason,
    required this.vehicle,
    required this.evidence,
  });

  final String trackId;
  final String plate;
  final double confidence;
  final String matchType;
  final String cameraLabel;
  final String reason;
  final Map<String, dynamic> vehicle;
  final Map<String, dynamic> evidence;

  factory AnprAlert.fromMap(Map<String, dynamic> map) {
    return AnprAlert(
      trackId: (map['trackId'] as String?) ?? '',
      plate: (map['plate'] as String?) ?? '',
      confidence: _readDouble(map['confidence']),
      matchType: (map['matchType'] as String?) ?? 'NONE',
      cameraLabel: (map['cameraLabel'] as String?) ?? 'Camera',
      reason: (map['reason'] as String?) ?? '',
      vehicle: _asMap(map['vehicle']),
      evidence: _asMap(map['evidence']),
    );
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return <String, dynamic>{};
}

DateTime _readTimestamp(Map<String, dynamic> map) {
  final raw = map['timestamp'];
  if (raw is String) {
    return DateTime.tryParse(raw) ?? DateTime.now().toUtc();
  }
  return DateTime.now().toUtc();
}

double _readDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _readInt(dynamic value) {
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

class Stringify {
  const Stringify._();

  static String value(dynamic input) => input?.toString() ?? '';
}
