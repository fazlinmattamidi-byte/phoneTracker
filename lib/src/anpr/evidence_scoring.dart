class EvidenceFrameScoreComponents {
  const EvidenceFrameScoreComponents({
    required this.sharpness,
    required this.plateSize,
    required this.ocrConfidence,
    required this.motionBlur,
    required this.perspective,
  });

  final double sharpness;
  final double plateSize;
  final double ocrConfidence;
  final double motionBlur;
  final double perspective;
}

double scoreEvidenceFrameQuality(EvidenceFrameScoreComponents components) {
  return components.sharpness * 0.35 +
      components.plateSize * 0.25 +
      components.ocrConfidence * 0.20 +
      components.motionBlur * 0.10 +
      components.perspective * 0.10;
}
