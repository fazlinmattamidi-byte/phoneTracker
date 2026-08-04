import { ActiveTrack, BoundingBox } from './tracker';
import { assessCropQuality, CropQualityReport } from './qualityAssessor';
import { releaseCanvasMemory } from './imageProcessor';

type CanvasImageSource = HTMLCanvasElement | HTMLVideoElement;

export type EvidenceImageKind = 'PLATE' | 'VEHICLE_CONTEXT';

export interface EvidenceImageSample {
  id: string;
  kind: EvidenceImageKind;
  canvas: HTMLCanvasElement;
  bbox: BoundingBox;
  timestamp: number;
  score: number;
  scoreComponents: EvidenceFrameScoreComponents;
  qualityScore: number;
  sharpnessScore: number;
  plateSizeScore: number;
  motionBlurScore: number;
  detectorConfidence: number;
  ocrConfidence: number;
  trackConfidence: number;
  perspectiveScore: number;
  width: number;
  height: number;
}

export interface EvidenceFrameScoreComponents {
  sharpness: number;
  plateSize: number;
  ocrConfidence: number;
  motionBlur: number;
  perspective: number;
}

export interface EvidenceOcrCandidate {
  plate: string;
  confidence: number;
  score: number;
  timestamp: number;
}

export interface VehicleTrackEvidence {
  trackId: string;
  trackNumber: number;
  cameraId: string;
  cameraName: string;
  enteredTime: number;
  lastSeen: number;
  matched: boolean;
  vehicleImages: EvidenceImageSample[];
  plateImages: EvidenceImageSample[];
  ocrCandidates: EvidenceOcrCandidate[];
  bestOCR?: EvidenceOcrCandidate;
  confidence?: number;
  trackSnapshot?: ActiveTrack;
}

export interface FinishedVehicleEvidence extends VehicleTrackEvidence {
  bestVehicleImage?: EvidenceImageSample;
  bestPlateImage?: EvidenceImageSample;
}

export interface VehicleEvidenceBufferOptions {
  maxPlateImagesPerTrack?: number;
  maxVehicleImagesPerTrack?: number;
  maxTrackAgeMs?: number;
  maxTracks?: number;
}

export interface EvidenceTrackMetadata {
  cameraId: string;
  cameraName: string;
}

export interface EvidenceSampleOptions {
  qualityScore?: number;
  detectorConfidence?: number;
  ocrConfidence?: number;
  trackConfidence?: number;
  perspectiveScore?: number;
}

const DEFAULT_MAX_PLATE_IMAGES = 6;
const DEFAULT_MAX_VEHICLE_IMAGES = 4;
const DEFAULT_MAX_TRACK_AGE_MS = 15000;
const DEFAULT_MAX_TRACKS = 16;

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function getSourceDimensions(source: CanvasImageSource): { width: number; height: number } {
  if (typeof HTMLVideoElement !== 'undefined' && source instanceof HTMLVideoElement) {
    return {
      width: source.videoWidth || source.width || 0,
      height: source.videoHeight || source.height || 0,
    };
  }

  return {
    width: source.width || 0,
    height: source.height || 0,
  };
}

function createCanvas(width: number, height: number): HTMLCanvasElement | null {
  if (typeof document === 'undefined') return null;
  const canvas = document.createElement('canvas');
  canvas.width = Math.max(1, Math.round(width));
  canvas.height = Math.max(1, Math.round(height));
  return canvas;
}

function cloneCanvas(source: HTMLCanvasElement): HTMLCanvasElement | null {
  const canvas = createCanvas(source.width, source.height);
  const ctx = canvas?.getContext('2d', { willReadFrequently: true });
  if (!canvas || !ctx || source.width === 0 || source.height === 0) return null;

  ctx.drawImage(source, 0, 0);
  return canvas;
}

function cropCanvasSource(source: CanvasImageSource, bbox: BoundingBox, maxLongEdge = 720): HTMLCanvasElement | null {
  const sourceDimensions = getSourceDimensions(source);
  if (sourceDimensions.width <= 0 || sourceDimensions.height <= 0) return null;

  const x = clamp(Math.round(bbox.x), 0, Math.max(0, sourceDimensions.width - 1));
  const y = clamp(Math.round(bbox.y), 0, Math.max(0, sourceDimensions.height - 1));
  const right = clamp(Math.round(bbox.x + bbox.width), x + 1, sourceDimensions.width);
  const bottom = clamp(Math.round(bbox.y + bbox.height), y + 1, sourceDimensions.height);
  const cropWidth = Math.max(1, right - x);
  const cropHeight = Math.max(1, bottom - y);
  const scale = Math.min(1, maxLongEdge / Math.max(cropWidth, cropHeight));
  const canvas = createCanvas(cropWidth * scale, cropHeight * scale);
  const ctx = canvas?.getContext('2d', { willReadFrequently: true });
  if (!canvas || !ctx) return null;

  ctx.drawImage(source, x, y, cropWidth, cropHeight, 0, 0, canvas.width, canvas.height);
  return canvas;
}

function createVehicleContextBox(plateBbox: BoundingBox, sourceWidth: number, sourceHeight: number): BoundingBox {
  const targetWidth = clamp(Math.max(plateBbox.width * 5.6, 280), plateBbox.width, sourceWidth);
  const targetHeight = clamp(Math.max(plateBbox.height * 6.2, 190), plateBbox.height, sourceHeight);
  const centerX = plateBbox.x + plateBbox.width / 2;
  const centerY = plateBbox.y + plateBbox.height / 2 - targetHeight * 0.18;
  const x = clamp(centerX - targetWidth / 2, 0, Math.max(0, sourceWidth - targetWidth));
  const y = clamp(centerY - targetHeight / 2, 0, Math.max(0, sourceHeight - targetHeight));

  return {
    x,
    y,
    width: targetWidth,
    height: targetHeight,
    confidence: plateBbox.confidence,
  };
}

function getEvidenceScoreComponents(
  kind: EvidenceImageKind,
  qualityReport: CropQualityReport,
  bbox: BoundingBox,
  options: Required<EvidenceSampleOptions>
): EvidenceFrameScoreComponents {
  const plateSize = clamp((bbox.width * bbox.height) / (kind === 'PLATE' ? 170 * 46 : 640 * 360), 0, 1);

  return {
    sharpness: clamp(qualityReport.sharpnessScore, 0, 1),
    plateSize,
    ocrConfidence: clamp(options.ocrConfidence, 0, 1),
    motionBlur: clamp(1 - qualityReport.motionBlurScore, 0, 1),
    perspective: clamp(options.perspectiveScore, 0, 1),
  };
}

export function scoreEvidenceFrameQuality(components: EvidenceFrameScoreComponents): number {
  return (
    components.sharpness * 0.35 +
    components.plateSize * 0.25 +
    components.ocrConfidence * 0.20 +
    components.motionBlur * 0.10 +
    components.perspective * 0.10
  );
}

function releaseSamples(samples: EvidenceImageSample[]): void {
  samples.forEach((sample) => releaseCanvasMemory(sample.canvas));
}

function getBestSample(samples: EvidenceImageSample[]): EvidenceImageSample | undefined {
  return [...samples].sort((a, b) => b.score - a.score)[0];
}

function normalizeSampleOptions(track: ActiveTrack, options: EvidenceSampleOptions): Required<EvidenceSampleOptions> {
  return {
    qualityScore: clamp(options.qualityScore ?? track.qualityScore ?? 0, 0, 1),
    detectorConfidence: clamp(options.detectorConfidence ?? track.bbox.confidence ?? 0, 0, 1),
    ocrConfidence: clamp(options.ocrConfidence ?? track.stabilizedConfidence ?? 0, 0, 1),
    trackConfidence: clamp(options.trackConfidence ?? track.trackConfidence ?? 0.55, 0, 1),
    perspectiveScore: clamp(options.perspectiveScore ?? 0.75, 0, 1),
  };
}

export class VehicleEvidenceBuffer {
  private tracks: Map<string, VehicleTrackEvidence> = new Map();
  private maxPlateImagesPerTrack = DEFAULT_MAX_PLATE_IMAGES;
  private maxVehicleImagesPerTrack = DEFAULT_MAX_VEHICLE_IMAGES;
  private maxTrackAgeMs = DEFAULT_MAX_TRACK_AGE_MS;
  private maxTracks = DEFAULT_MAX_TRACKS;

  constructor(options: VehicleEvidenceBufferOptions = {}) {
    this.configure(options);
  }

  public configure(options: VehicleEvidenceBufferOptions): void {
    if (typeof options.maxPlateImagesPerTrack === 'number') {
      this.maxPlateImagesPerTrack = Math.max(1, Math.min(12, Math.round(options.maxPlateImagesPerTrack)));
    }
    if (typeof options.maxVehicleImagesPerTrack === 'number') {
      this.maxVehicleImagesPerTrack = Math.max(1, Math.min(8, Math.round(options.maxVehicleImagesPerTrack)));
    }
    if (typeof options.maxTrackAgeMs === 'number') {
      this.maxTrackAgeMs = Math.max(1000, Math.min(60000, Math.round(options.maxTrackAgeMs)));
    }
    if (typeof options.maxTracks === 'number') {
      this.maxTracks = Math.max(1, Math.min(32, Math.round(options.maxTracks)));
    }
  }

  public upsertTrack(track: ActiveTrack, metadata: EvidenceTrackMetadata, now: number = Date.now()): VehicleTrackEvidence {
    const existing = this.tracks.get(track.trackId);
    if (existing) {
      existing.lastSeen = Math.max(existing.lastSeen, track.lastSeenTimestamp || now);
      existing.cameraId = metadata.cameraId;
      existing.cameraName = metadata.cameraName;
      existing.trackSnapshot = track;
      existing.confidence = Math.max(existing.confidence ?? 0, track.trackConfidence ?? 0);
      return existing;
    }

    const evidence: VehicleTrackEvidence = {
      trackId: track.trackId,
      trackNumber: track.trackNumber,
      cameraId: metadata.cameraId,
      cameraName: metadata.cameraName,
      enteredTime: track.firstSeenTimestamp || now,
      lastSeen: track.lastSeenTimestamp || now,
      matched: false,
      vehicleImages: [],
      plateImages: [],
      ocrCandidates: [],
      confidence: track.trackConfidence,
      trackSnapshot: track,
    };

    this.tracks.set(track.trackId, evidence);
    this.pruneOverflow();
    return evidence;
  }

  public addPlateSample(
    track: ActiveTrack,
    plateCanvas: HTMLCanvasElement,
    bbox: BoundingBox,
    metadata: EvidenceTrackMetadata,
    options: EvidenceSampleOptions = {}
  ): EvidenceImageSample | null {
    const sampleCanvas = cloneCanvas(plateCanvas);
    if (!sampleCanvas) return null;

    const evidence = this.upsertTrack(track, metadata);
    const normalizedOptions = normalizeSampleOptions(track, options);
    const qualityReport = assessCropQuality(sampleCanvas);
    const sample = this.createSample('PLATE', sampleCanvas, bbox, qualityReport, normalizedOptions);
    evidence.plateImages.push(sample);
    evidence.lastSeen = Math.max(evidence.lastSeen, track.lastSeenTimestamp || sample.timestamp);
    this.rankAndTrim(evidence.plateImages, this.maxPlateImagesPerTrack);
    return sample;
  }

  public addVehicleContextSample(
    track: ActiveTrack,
    source: CanvasImageSource,
    plateBbox: BoundingBox,
    metadata: EvidenceTrackMetadata,
    options: EvidenceSampleOptions = {}
  ): EvidenceImageSample | null {
    const sourceDimensions = getSourceDimensions(source);
    if (sourceDimensions.width <= 0 || sourceDimensions.height <= 0) return null;

    const contextBox = createVehicleContextBox(plateBbox, sourceDimensions.width, sourceDimensions.height);
    const vehicleCanvas = cropCanvasSource(source, contextBox, 720);
    if (!vehicleCanvas) return null;

    const evidence = this.upsertTrack(track, metadata);
    const normalizedOptions = normalizeSampleOptions(track, options);
    const qualityReport = assessCropQuality(vehicleCanvas);
    const sample = this.createSample('VEHICLE_CONTEXT', vehicleCanvas, contextBox, qualityReport, normalizedOptions);
    evidence.vehicleImages.push(sample);
    evidence.lastSeen = Math.max(evidence.lastSeen, track.lastSeenTimestamp || sample.timestamp);
    this.rankAndTrim(evidence.vehicleImages, this.maxVehicleImagesPerTrack);
    return sample;
  }

  public addOcrCandidate(trackId: string, candidate: EvidenceOcrCandidate): void {
    const evidence = this.tracks.get(trackId);
    if (!evidence) return;

    evidence.ocrCandidates.push(candidate);
    evidence.ocrCandidates.sort((a, b) => b.score - a.score);
    evidence.ocrCandidates.splice(8);
    evidence.bestOCR = evidence.ocrCandidates[0];
    evidence.confidence = Math.max(evidence.confidence ?? 0, candidate.confidence);
    evidence.plateImages.forEach((sample) => {
      sample.ocrConfidence = Math.max(sample.ocrConfidence, candidate.confidence);
      sample.scoreComponents.ocrConfidence = sample.ocrConfidence;
      sample.score = Math.round(scoreEvidenceFrameQuality(sample.scoreComponents) * 1000) / 1000;
    });
    evidence.plateImages.sort((a, b) => b.score - a.score);
  }

  public finishTrack(track: ActiveTrack, metadata?: Partial<EvidenceTrackMetadata>): FinishedVehicleEvidence | null {
    const evidence = this.tracks.get(track.trackId);
    if (!evidence) return null;

    if (metadata?.cameraId) evidence.cameraId = metadata.cameraId;
    if (metadata?.cameraName) evidence.cameraName = metadata.cameraName;
    evidence.trackSnapshot = track;
    evidence.lastSeen = Math.max(evidence.lastSeen, track.lastSeenTimestamp || Date.now());
    evidence.confidence = Math.max(evidence.confidence ?? 0, track.stabilizedConfidence ?? track.trackConfidence ?? 0);
    this.tracks.delete(track.trackId);

    return {
      ...evidence,
      vehicleImages: [...evidence.vehicleImages].sort((a, b) => b.score - a.score),
      plateImages: [...evidence.plateImages].sort((a, b) => b.score - a.score),
      bestVehicleImage: getBestSample(evidence.vehicleImages),
      bestPlateImage: getBestSample(evidence.plateImages),
    };
  }

  public getTrack(trackId: string): VehicleTrackEvidence | undefined {
    return this.tracks.get(trackId);
  }

  public pruneStale(now: number = Date.now()): void {
    for (const evidence of Array.from(this.tracks.values())) {
      if (now - evidence.lastSeen > this.maxTrackAgeMs) {
        this.discardTrack(evidence.trackId);
      }
    }
  }

  public discardTrack(trackId: string): void {
    const evidence = this.tracks.get(trackId);
    if (!evidence) return;
    releaseSamples(evidence.plateImages);
    releaseSamples(evidence.vehicleImages);
    this.tracks.delete(trackId);
  }

  public clear(): void {
    for (const evidence of this.tracks.values()) {
      releaseSamples(evidence.plateImages);
      releaseSamples(evidence.vehicleImages);
    }
    this.tracks.clear();
  }

  public releaseFinishedEvidence(evidence: FinishedVehicleEvidence): void {
    releaseSamples(evidence.plateImages);
    releaseSamples(evidence.vehicleImages);
  }

  private createSample(
    kind: EvidenceImageKind,
    canvas: HTMLCanvasElement,
    bbox: BoundingBox,
    qualityReport: CropQualityReport,
    options: Required<EvidenceSampleOptions>
  ): EvidenceImageSample {
    const timestamp = Date.now();
    const scoreComponents = getEvidenceScoreComponents(kind, qualityReport, bbox, options);
    return {
      id: `${kind.toLowerCase()}-${timestamp}-${Math.random().toString(36).slice(2, 7)}`,
      kind,
      canvas,
      bbox: { ...bbox },
      timestamp,
      score: Math.round(scoreEvidenceFrameQuality(scoreComponents) * 1000) / 1000,
      scoreComponents,
      qualityScore: qualityReport.overallScore,
      sharpnessScore: qualityReport.sharpnessScore,
      plateSizeScore: scoreComponents.plateSize,
      motionBlurScore: qualityReport.motionBlurScore,
      detectorConfidence: options.detectorConfidence,
      ocrConfidence: options.ocrConfidence,
      trackConfidence: options.trackConfidence,
      perspectiveScore: options.perspectiveScore,
      width: canvas.width,
      height: canvas.height,
    };
  }

  private rankAndTrim(samples: EvidenceImageSample[], maxCount: number): void {
    samples.sort((a, b) => b.score - a.score);
    while (samples.length > maxCount) {
      const removed = samples.pop();
      if (removed) releaseCanvasMemory(removed.canvas);
    }
  }

  private pruneOverflow(): void {
    if (this.tracks.size <= this.maxTracks) return;

    const ranked = Array.from(this.tracks.values()).sort((a, b) => b.lastSeen - a.lastSeen);
    ranked.slice(this.maxTracks).forEach((evidence) => this.discardTrack(evidence.trackId));
  }
}
