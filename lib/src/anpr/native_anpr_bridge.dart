import 'dart:async';

import 'package:flutter/services.dart';

class NativeAnprBridge {
  static const MethodChannel _methods = MethodChannel('plateq.anpr/methods');
  static const EventChannel _events = EventChannel('plateq.anpr/events');
  static const MethodChannel _modelStaging = MethodChannel('plateq.app/models');
  static const Map<String, String> modelAssetPaths = <String, String>{
    'detector': 'public/models/plate-detector.onnx',
    'ocr': 'public/models/ppocr-rec.onnx',
    'ocrDictionary': 'public/models/ppocr-dict.txt',
    'environment': 'public/models/environment-classifier.onnx',
    'environmentMetadata': 'public/models/environment-classifier.metadata.json',
    'plateQuality': 'public/models/plate-quality-classifier.onnx',
    'plateQualityMetadata':
        'public/models/plate-quality-classifier.metadata.json',
  };

  static const Set<String> requiredModelAssetIds = <String>{
    'detector',
    'ocr',
    'ocrDictionary',
    'environment',
    'environmentMetadata',
  };

  Stream<AnprEvent> get events {
    return _events.receiveBroadcastStream().map(AnprEvent.fromDynamic);
  }

  Future<NativeRuntimeStatus> initialize() async {
    final modelAssets = await verifyModelAssets();
    final stagedModelAssets = await stageModelAssets(modelAssets);
    final stagedModelAssetPaths = <String, String>{
      for (final asset in stagedModelAssets)
        if (asset.nativePath != null && asset.nativePath!.isNotEmpty)
          asset.id: asset.nativePath!,
    };
    final result = await _methods.invokeMethod<Map<dynamic, dynamic>>(
      'initialize',
      <String, Object?>{
        'modelAssets': modelAssetPaths,
        'modelAssetStatus': stagedModelAssets
            .map((asset) => asset.toMap())
            .toList(growable: false),
        'stagedModelAssets': stagedModelAssetPaths,
        'deviceTier': 'AUTO',
        'enableHardwareAcceleration': true,
      },
    );
    return NativeRuntimeStatus.fromMap(
      Map<String, dynamic>.from(result ?? const <String, dynamic>{}),
    ).copyWith(
      modelAssets: stagedModelAssets,
      extraWarnings: _modelAssetWarnings(stagedModelAssets),
    );
  }

  static Future<List<NativeModelAssetStatus>> verifyModelAssets({
    AssetBundle? bundle,
  }) async {
    final assetBundle = bundle ?? rootBundle;
    final statuses = <NativeModelAssetStatus>[];
    for (final entry in modelAssetPaths.entries) {
      final required = requiredModelAssetIds.contains(entry.key);
      try {
        final data = await assetBundle.load(entry.value);
        statuses.add(NativeModelAssetStatus(
          id: entry.key,
          path: entry.value,
          required: required,
          available: true,
          sizeBytes: data.lengthInBytes,
        ));
      } on Object catch (error) {
        statuses.add(NativeModelAssetStatus(
          id: entry.key,
          path: entry.value,
          required: required,
          available: false,
          sizeBytes: 0,
          error: error.toString(),
        ));
      }
    }
    return statuses;
  }

  static Future<List<NativeModelAssetStatus>> stageModelAssets(
    List<NativeModelAssetStatus> assets, {
    AssetBundle? bundle,
  }) async {
    final assetBundle = bundle ?? rootBundle;
    final staged = <NativeModelAssetStatus>[];
    for (final asset in assets) {
      if (!asset.available) {
        staged.add(asset);
        continue;
      }
      try {
        final data = await assetBundle.load(asset.path);
        final bytes = _byteDataToUint8List(data);
        final result = await _modelStaging.invokeMethod<Map<dynamic, dynamic>>(
          'stageModelAsset',
          <String, Object?>{
            'id': asset.id,
            'path': asset.path,
            'required': asset.required,
            'bytes': bytes,
          },
        );
        staged.add(NativeModelAssetStatus.fromMap(
          Map<String, dynamic>.from(result ?? const <String, dynamic>{}),
        ));
      } on MissingPluginException catch (error) {
        staged.add(asset.copyWith(error: error.message ?? error.toString()));
      } on PlatformException catch (error) {
        staged.add(asset.copyWith(error: error.message ?? error.code));
      }
    }
    return staged;
  }

  static List<String> _modelAssetWarnings(List<NativeModelAssetStatus> assets) {
    final warnings = <String>[];
    for (final asset in assets.where((asset) => asset.required)) {
      if (!asset.available) {
        warnings.add('Required model asset missing: ${asset.path}');
      } else if (!asset.nativeReady) {
        warnings.add(
            'Required model asset not staged for native ONNX: ${asset.path}');
      }
    }
    return warnings;
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
    required this.modelAssets,
  });

  final String runtimeState;
  final String deviceTier;
  final String detectorProvider;
  final String ocrProvider;
  final String environmentProvider;
  final String plateQualityProvider;
  final List<String> warnings;
  final List<NativeModelAssetStatus> modelAssets;

  bool get requiredModelAssetsReady => modelAssets
      .where((asset) => asset.required)
      .every((asset) => asset.nativeReady);

  int get requiredModelAssetCount =>
      modelAssets.where((asset) => asset.required).length;

  int get readyRequiredModelAssetCount =>
      modelAssets.where((asset) => asset.required && asset.nativeReady).length;

  List<NativeModelAssetStatus> get missingRequiredModelAssets => modelAssets
      .where((asset) => asset.required && !asset.available)
      .toList(growable: false);

  List<NativeModelAssetStatus> get missingOptionalModelAssets => modelAssets
      .where((asset) => !asset.required && !asset.available)
      .toList(growable: false);

  factory NativeRuntimeStatus.fromMap(Map<String, dynamic> map) {
    final platformWarnings =
        ((map['warnings'] as List<dynamic>?) ?? const <dynamic>[])
            .map(Stringify.value)
            .toList();
    return NativeRuntimeStatus(
      runtimeState: (map['runtimeState'] as String?) ?? 'UNINITIALIZED',
      deviceTier: (map['deviceTier'] as String?) ?? 'AUTO',
      detectorProvider: (map['detectorProvider'] as String?) ?? 'NONE',
      ocrProvider: (map['ocrProvider'] as String?) ?? 'NONE',
      environmentProvider: (map['environmentProvider'] as String?) ?? 'NONE',
      plateQualityProvider: (map['plateQualityProvider'] as String?) ?? 'NONE',
      warnings: platformWarnings,
      modelAssets:
          ((map['modelAssetStatus'] as List<dynamic>?) ?? const <dynamic>[])
              .map((item) => NativeModelAssetStatus.fromMap(_asMap(item)))
              .toList(),
    );
  }

  NativeRuntimeStatus copyWith({
    List<NativeModelAssetStatus>? modelAssets,
    List<String> extraWarnings = const <String>[],
  }) {
    return NativeRuntimeStatus(
      runtimeState: runtimeState,
      deviceTier: deviceTier,
      detectorProvider: detectorProvider,
      ocrProvider: ocrProvider,
      environmentProvider: environmentProvider,
      plateQualityProvider: plateQualityProvider,
      warnings: <String>{
        ...warnings,
        ...extraWarnings,
      }.toList(growable: false),
      modelAssets: modelAssets ?? this.modelAssets,
    );
  }
}

class NativeModelAssetStatus {
  const NativeModelAssetStatus({
    required this.id,
    required this.path,
    required this.required,
    required this.available,
    required this.sizeBytes,
    this.nativePath,
    this.error,
  });

  final String id;
  final String path;
  final bool required;
  final bool available;
  final int sizeBytes;
  final String? nativePath;
  final String? error;

  bool get nativeReady => available && (nativePath?.isNotEmpty ?? false);

  String get sizeLabel {
    if (sizeBytes <= 0) return '0 B';
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (sizeBytes >= 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$sizeBytes B';
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'path': path,
      'required': required,
      'available': available,
      'sizeBytes': sizeBytes,
      'nativePath': nativePath,
      'error': error,
    };
  }

  NativeModelAssetStatus copyWith({
    bool? available,
    int? sizeBytes,
    String? nativePath,
    String? error,
  }) {
    return NativeModelAssetStatus(
      id: id,
      path: path,
      required: required,
      available: available ?? this.available,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      nativePath: nativePath ?? this.nativePath,
      error: error ?? this.error,
    );
  }

  factory NativeModelAssetStatus.fromMap(Map<String, dynamic> map) {
    return NativeModelAssetStatus(
      id: (map['id'] as String?) ?? '',
      path: (map['path'] as String?) ?? '',
      required: (map['required'] as bool?) ?? false,
      available: (map['available'] as bool?) ?? false,
      sizeBytes: _readInt(map['sizeBytes']),
      nativePath: map['nativePath'] as String?,
      error: map['error'] as String?,
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
      case 'ocr':
        return OcrAnprEvent.fromMap(map);
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

class OcrAnprEvent extends AnprEvent {
  const OcrAnprEvent({
    required super.timestamp,
    required this.trackId,
    required this.rawText,
    required this.normalizedPlate,
    required this.displayPlate,
    required this.confidence,
    required this.layout,
    required this.category,
    required this.patternScore,
    required this.provider,
    required this.vehicleImagePath,
    required this.plateImagePath,
    required this.plateEnhancedImagePath,
    required this.plateBinaryImagePath,
    required this.plateTopLineImagePath,
    required this.plateBottomLineImagePath,
    required this.plateInnerTextImagePath,
    required this.plateCropWidth,
    required this.plateCropHeight,
    required this.preprocessingVariant,
    required this.preprocessingVariants,
    required this.characterConfidences,
  }) : super(type: 'ocr');

  final String trackId;
  final String rawText;
  final String normalizedPlate;
  final String displayPlate;
  final double confidence;
  final String layout;
  final String category;
  final double patternScore;
  final String provider;
  final String vehicleImagePath;
  final String plateImagePath;
  final String plateEnhancedImagePath;
  final String plateBinaryImagePath;
  final String plateTopLineImagePath;
  final String plateBottomLineImagePath;
  final String plateInnerTextImagePath;
  final int plateCropWidth;
  final int plateCropHeight;
  final String preprocessingVariant;
  final List<String> preprocessingVariants;
  final List<NativeCharacterConfidence> characterConfidences;

  factory OcrAnprEvent.fromMap(Map<String, dynamic> map) {
    return OcrAnprEvent(
      timestamp: _readTimestamp(map),
      trackId: (map['trackId'] as String?) ?? '',
      rawText: (map['rawText'] as String?) ?? '',
      normalizedPlate: (map['normalizedPlate'] as String?) ?? '',
      displayPlate: (map['displayPlate'] as String?) ?? '',
      confidence: _readDouble(map['confidence']),
      layout: (map['layout'] as String?) ?? 'SINGLE_LINE',
      category: (map['category'] as String?) ?? 'UNKNOWN_VALID_CANDIDATE',
      patternScore: _readDouble(map['patternScore']),
      provider: (map['provider'] as String?) ?? '',
      vehicleImagePath: (map['vehicleImagePath'] as String?) ?? '',
      plateImagePath: (map['plateImagePath'] as String?) ?? '',
      plateEnhancedImagePath: (map['plateEnhancedImagePath'] as String?) ?? '',
      plateBinaryImagePath: (map['plateBinaryImagePath'] as String?) ?? '',
      plateTopLineImagePath: (map['plateTopLineImagePath'] as String?) ?? '',
      plateBottomLineImagePath:
          (map['plateBottomLineImagePath'] as String?) ?? '',
      plateInnerTextImagePath:
          (map['plateInnerTextImagePath'] as String?) ?? '',
      plateCropWidth: _readInt(map['plateCropWidth']),
      plateCropHeight: _readInt(map['plateCropHeight']),
      preprocessingVariant:
          (map['preprocessingVariant'] as String?) ?? 'RAW_CROP',
      preprocessingVariants:
          ((map['preprocessingVariants'] as List<dynamic>?) ??
                  const <dynamic>[])
              .map(Stringify.value)
              .toList(),
      characterConfidences:
          ((map['characterConfidences'] as List<dynamic>?) ?? const <dynamic>[])
              .map((item) => NativeCharacterConfidence.fromMap(_asMap(item)))
              .toList(),
    );
  }
}

class NativeCharacterConfidence {
  const NativeCharacterConfidence({
    required this.char,
    required this.confidence,
    required this.position,
  });

  final String char;
  final double confidence;
  final int position;

  factory NativeCharacterConfidence.fromMap(Map<String, dynamic> map) {
    return NativeCharacterConfidence(
      char: (map['char'] as String?) ?? '',
      confidence: _readDouble(map['confidence']),
      position: _readInt(map['position']),
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

Uint8List _byteDataToUint8List(ByteData data) {
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

class Stringify {
  const Stringify._();

  static String value(dynamic input) => input?.toString() ?? '';
}
