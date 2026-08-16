import 'dart:math' as math;

class YoloBbox {
  const YoloBbox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  double get area => width * height;

  double iou(YoloBbox other) {
    final left = math.max(x, other.x);
    final top = math.max(y, other.y);
    final right = math.min(x + width, other.x + other.width);
    final bottom = math.min(y + height, other.y + other.height);
    final intersection =
        math.max(0.0, right - left) * math.max(0.0, bottom - top);
    final union = area + other.area - intersection;
    return union <= 0 ? 0 : intersection / union;
  }
}

class YoloDetection {
  const YoloDetection({
    required this.bbox,
    required this.confidence,
    this.label = 'License-Plate',
    this.sourceEngine = 'LOCAL_ONNX',
  });

  final YoloBbox bbox;
  final double confidence;
  final String label;
  final String sourceEngine;
}

class YoloOutputShape {
  const YoloOutputShape({
    required this.sequenceLength,
    required this.channelCount,
    required this.transposed,
  });

  final int sequenceLength;
  final int channelCount;
  final bool transposed;
}

class YoloLetterbox {
  const YoloLetterbox({
    required this.sourceWidth,
    required this.sourceHeight,
    this.targetSize = 640,
  });

  final int sourceWidth;
  final int sourceHeight;
  final int targetSize;

  double get scale =>
      math.min(targetSize / sourceWidth, targetSize / sourceHeight);
  int get drawWidth => (sourceWidth * scale).round();
  int get drawHeight => (sourceHeight * scale).round();
  int get padX => ((targetSize - drawWidth) / 2).round();
  int get padY => ((targetSize - drawHeight) / 2).round();
}

List<YoloDetection> decodeYoloDetections({
  required List<double> output,
  required List<int> dims,
  required int imageWidth,
  required int imageHeight,
  double minConfidence = 0.35,
  double iouThreshold = 0.35,
  int targetSize = 640,
}) {
  if (output.isEmpty || imageWidth <= 0 || imageHeight <= 0) {
    return const <YoloDetection>[];
  }

  final shape = inferYoloOutputShape(dims);
  final hasObjectness = shape.channelCount == 6 || shape.channelCount == 85;
  final letterbox = YoloLetterbox(
    sourceWidth: imageWidth,
    sourceHeight: imageHeight,
    targetSize: targetSize,
  );
  final minBoxWidth = math.max(32.0, imageWidth * 0.022);
  final minBoxHeight = math.max(9.0, imageHeight * 0.008);
  final detections = <YoloDetection>[];

  for (var index = 0; index < shape.sequenceLength; index += 1) {
    final values = _readAnchor(output, shape, index);
    if (values == null) continue;

    final confidence =
        (hasObjectness ? values.objectness : 1.0) * values.classConfidence;
    if (!_finiteAll(<double>[
          values.cx,
          values.cy,
          values.width,
          values.height,
          confidence,
        ]) ||
        confidence < minConfidence) {
      continue;
    }

    final realCx = (values.cx - letterbox.padX) / letterbox.scale;
    final realCy = (values.cy - letterbox.padY) / letterbox.scale;
    final realWidth = values.width / letterbox.scale;
    final realHeight = values.height / letterbox.scale;

    final left = (realCx - realWidth / 2).clamp(0.0, imageWidth.toDouble());
    final top = (realCy - realHeight / 2).clamp(0.0, imageHeight.toDouble());
    final right = (realCx + realWidth / 2).clamp(0.0, imageWidth.toDouble());
    final bottom = (realCy + realHeight / 2).clamp(0.0, imageHeight.toDouble());
    final width = (right - left).roundToDouble();
    final height = (bottom - top).roundToDouble();

    if (width >= minBoxWidth && height >= minBoxHeight) {
      detections.add(YoloDetection(
        bbox: YoloBbox(
          x: left.roundToDouble(),
          y: top.roundToDouble(),
          width: width,
          height: height,
        ),
        confidence: _roundMetric(confidence),
      ));
    }
  }

  return applyYoloFiltersAndNms(
    detections,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    iouThreshold: iouThreshold,
  );
}

YoloOutputShape inferYoloOutputShape(List<int> dims) {
  if (dims.length >= 2) {
    final d1 = dims[dims.length - 2];
    final d2 = dims[dims.length - 1];
    if (_isYoloChannelCount(d2) && !_isYoloChannelCount(d1)) {
      return YoloOutputShape(
        sequenceLength: d1,
        channelCount: d2,
        transposed: true,
      );
    }
    if (_isYoloChannelCount(d1) && !_isYoloChannelCount(d2)) {
      return YoloOutputShape(
        sequenceLength: d2,
        channelCount: d1,
        transposed: false,
      );
    }
    if (d1 > d2) {
      return YoloOutputShape(
        sequenceLength: d1,
        channelCount: d2,
        transposed: true,
      );
    }
    return YoloOutputShape(
      sequenceLength: d2,
      channelCount: d1,
      transposed: false,
    );
  }
  return const YoloOutputShape(
    sequenceLength: 8400,
    channelCount: 5,
    transposed: false,
  );
}

bool _isYoloChannelCount(int value) => value == 5 || value == 6 || value == 85;

List<YoloDetection> applyYoloFiltersAndNms(
  List<YoloDetection> detections, {
  required int imageWidth,
  required int imageHeight,
  double iouThreshold = 0.35,
}) {
  final minWidth = math.max(28.0, imageWidth * 0.018);
  final minHeight = math.max(8.0, imageHeight * 0.007);
  final filtered = detections.where((detection) {
    final width = detection.bbox.width;
    final height = detection.bbox.height;
    if (width < minWidth || height < minHeight || height <= 0) return false;
    final aspectRatio = width / height;
    return aspectRatio >= 0.65 && aspectRatio <= 7.2;
  }).toList();

  final effectiveThreshold = math.min(iouThreshold, 0.35);
  return applyYoloNms(
    filtered,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    iouThreshold: effectiveThreshold,
  ).take(12).toList(growable: false);
}

List<YoloDetection> applyYoloNms(
  List<YoloDetection> detections, {
  required int imageWidth,
  required int imageHeight,
  double iouThreshold = 0.35,
}) {
  final frameArea = imageWidth * imageHeight;
  final sorted = detections.toList()
    ..sort((a, b) => _boxRank(b, frameArea).compareTo(_boxRank(a, frameArea)));
  final selected = <YoloDetection>[];

  for (final detection in sorted) {
    var keep = true;
    for (final existing in selected) {
      if (detection.bbox.iou(existing.bbox) > iouThreshold ||
          _isMostlyContained(detection.bbox, existing.bbox)) {
        keep = false;
        break;
      }
    }
    if (keep) selected.add(detection);
  }
  return selected;
}

({
  double cx,
  double cy,
  double width,
  double height,
  double objectness,
  double classConfidence
})? _readAnchor(List<double> output, YoloOutputShape shape, int anchor) {
  double read(int channel) {
    final offset = shape.transposed
        ? anchor * shape.channelCount + channel
        : channel * shape.sequenceLength + anchor;
    if (offset < 0 || offset >= output.length) return double.nan;
    return output[offset];
  }

  final classChannel =
      shape.channelCount == 6 || shape.channelCount == 85 ? 5 : 4;
  return (
    cx: read(0),
    cy: read(1),
    width: read(2),
    height: read(3),
    objectness: shape.channelCount > 4 ? read(4) : 1.0,
    classConfidence:
        shape.channelCount > classChannel ? read(classChannel) : double.nan,
  );
}

bool _finiteAll(List<double> values) => values.every((value) => value.isFinite);

double _roundMetric(double value) => (value * 1000).roundToDouble() / 1000;

double _boxRank(YoloDetection detection, int frameArea) {
  final areaScore =
      math.min(1.0, detection.bbox.area / math.max(1, frameArea * 0.08));
  return detection.confidence * 0.68 + areaScore * 0.32;
}

bool _isMostlyContained(YoloBbox inner, YoloBbox outer) {
  final centerX = inner.x + inner.width / 2;
  final centerY = inner.y + inner.height / 2;
  final centerInside = centerX >= outer.x &&
      centerX <= outer.x + outer.width &&
      centerY >= outer.y &&
      centerY <= outer.y + outer.height;
  return centerInside && inner.area < outer.area * 0.65;
}
