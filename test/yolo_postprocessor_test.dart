import 'package:flutter_test/flutter_test.dart';
import 'package:plateq_mobile/src/anpr/yolo_postprocessor.dart';

void main() {
  test('decodes transposed YOLO output and reverses 640 letterbox mapping', () {
    final output = <double>[
      ..._anchorNoObjectness(
        cx: 125,
        cy: 260,
        width: 150,
        height: 40,
        classConfidence: 0.91,
      ),
      ..._anchorNoObjectness(
        cx: 128,
        cy: 262,
        width: 148,
        height: 42,
        classConfidence: 0.74,
      ),
      ..._anchorNoObjectness(
        cx: 400,
        cy: 250,
        width: 10,
        height: 2,
        classConfidence: 0.95,
      ),
    ];

    final detections = decodeYoloDetections(
      output: output,
      dims: const <int>[1, 3, 5],
      imageWidth: 1280,
      imageHeight: 720,
      minConfidence: 0.35,
    );

    expect(detections, hasLength(1));
    final detection = detections.single;
    expect(detection.confidence, 0.91);
    expect(detection.bbox.x, 100);
    expect(detection.bbox.y, 200);
    expect(detection.bbox.width, 300);
    expect(detection.bbox.height, 80);
  });

  test('decodes channel-first YOLO output with objectness scores', () {
    final anchors = <List<double>>[
      _anchor(
        cx: 320,
        cy: 320,
        width: 120,
        height: 36,
        objectness: 0.8,
        classConfidence: 0.75,
      ),
      _anchor(
        cx: 130,
        cy: 120,
        width: 90,
        height: 24,
        objectness: 0.4,
        classConfidence: 0.6,
      ),
    ];

    final detections = decodeYoloDetections(
      output: _channelFirst(anchors),
      dims: const <int>[1, 6, 2],
      imageWidth: 640,
      imageHeight: 640,
      minConfidence: 0.35,
    );

    expect(detections, hasLength(1));
    expect(detections.single.confidence, 0.6);
    expect(detections.single.bbox.width, 120);
  });

  test('keeps multiple non-overlapping plate detections for tracker fanout', () {
    final output = <double>[
      ..._anchorNoObjectness(
        cx: 125,
        cy: 260,
        width: 150,
        height: 40,
        classConfidence: 0.91,
      ),
      ..._anchorNoObjectness(
        cx: 500,
        cy: 305,
        width: 170,
        height: 42,
        classConfidence: 0.88,
      ),
      ..._anchorNoObjectness(
        cx: 128,
        cy: 262,
        width: 148,
        height: 42,
        classConfidence: 0.74,
      ),
    ];

    final detections = decodeYoloDetections(
      output: output,
      dims: const <int>[1, 3, 5],
      imageWidth: 1280,
      imageHeight: 720,
      minConfidence: 0.35,
    );

    expect(detections, hasLength(2));
    expect(detections.map((item) => item.confidence), containsAll(<double>[
      0.91,
      0.88,
    ]));
  });

  test('filters unrealistic aspect ratios and keeps strongest NMS boxes', () {
    final detections = applyYoloFiltersAndNms(
      const <YoloDetection>[
        YoloDetection(
          bbox: YoloBbox(x: 10, y: 10, width: 220, height: 44),
          confidence: 0.82,
        ),
        YoloDetection(
          bbox: YoloBbox(x: 18, y: 14, width: 205, height: 42),
          confidence: 0.79,
        ),
        YoloDetection(
          bbox: YoloBbox(x: 400, y: 100, width: 40, height: 90),
          confidence: 0.95,
        ),
      ],
      imageWidth: 640,
      imageHeight: 360,
    );

    expect(detections, hasLength(1));
    expect(detections.single.confidence, 0.82);
  });
}

List<double> _anchor({
  required double cx,
  required double cy,
  required double width,
  required double height,
  double objectness = 1,
  required double classConfidence,
}) {
  return <double>[cx, cy, width, height, objectness, classConfidence];
}

List<double> _anchorNoObjectness({
  required double cx,
  required double cy,
  required double width,
  required double height,
  required double classConfidence,
}) {
  return <double>[cx, cy, width, height, classConfidence];
}

List<double> _channelFirst(List<List<double>> anchors) {
  final channelCount = anchors.first.length;
  return <double>[
    for (var channel = 0; channel < channelCount; channel += 1)
      for (final anchor in anchors) anchor[channel],
  ];
}
