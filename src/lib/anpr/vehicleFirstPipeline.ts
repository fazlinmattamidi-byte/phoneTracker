import { clampCropBox, releaseCanvasMemory } from './imageProcessor';
import { assessCropQuality } from './qualityAssessor';
import { calculateIoU, type BoundingBox } from './tracker';
import type { DetectedPlateBox } from './yoloDetector';

export type VehicleDetectionSource = 'MOTION' | 'PLATE_SEED';

export interface VehicleDetectionBox {
  bbox: BoundingBox;
  confidence: number;
  label: 'vehicle';
  source: VehicleDetectionSource;
  motionScore?: number;
}

export interface VehicleFrameEntry {
  id: string;
  canvas: HTMLCanvasElement;
  timestamp: number;
  bbox: BoundingBox;
  detectorConfidence: number;
  trackStability: number;
  motionScore: number;
  qualityScore: number;
  sharpnessScore: number;
  contrastScore: number;
  sizeScore: number;
  plateSearchCount: number;
  lastPlateSearchAt?: number;
}

export const VEHICLE_FIRST_DEFAULTS = {
  maxFramesPerVehicle: 10,
  maxEntryAgeMs: 3500,
  maxVehicleBuffers: 12,
  plateSearchIntervalMs: 260,
  maxPlateSearchesPerEntry: 3,
  maxPlateSearchFrames: 3,
  sampleWidth: 96,
  sampleHeight: 54,
  motionThreshold: 26,
} as const;

type MotionCellComponent = {
  minX: number;
  minY: number;
  maxX: number;
  maxY: number;
  count: number;
  diffTotal: number;
};

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function getBoxArea(box: BoundingBox): number {
  return Math.max(0, box.width) * Math.max(0, box.height);
}

function clampBoxToFrame(box: BoundingBox, frameWidth: number, frameHeight: number): BoundingBox {
  const x = clamp(Math.round(box.x), 0, Math.max(0, frameWidth - 1));
  const y = clamp(Math.round(box.y), 0, Math.max(0, frameHeight - 1));
  const right = clamp(Math.round(box.x + box.width), x + 1, frameWidth);
  const bottom = clamp(Math.round(box.y + box.height), y + 1, frameHeight);

  return {
    x,
    y,
    width: Math.max(1, right - x),
    height: Math.max(1, bottom - y),
    confidence: box.confidence,
  };
}

function expandBox(
  box: BoundingBox,
  frameWidth: number,
  frameHeight: number,
  padXRatio: number,
  padYRatio: number
): BoundingBox {
  const padX = box.width * padXRatio;
  const padY = box.height * padYRatio;

  return clampBoxToFrame(
    {
      x: box.x - padX,
      y: box.y - padY,
      width: box.width + padX * 2,
      height: box.height + padY * 2,
      confidence: box.confidence,
    },
    frameWidth,
    frameHeight
  );
}

function isVehicleLikeBox(box: BoundingBox, frameWidth: number, frameHeight: number): boolean {
  const area = getBoxArea(box);
  const frameArea = Math.max(1, frameWidth * frameHeight);
  const aspect = box.width / Math.max(1, box.height);

  if (box.width < Math.max(42, frameWidth * 0.055)) return false;
  if (box.height < Math.max(28, frameHeight * 0.055)) return false;
  if (area < frameArea * 0.006 || area > frameArea * 0.78) return false;
  if (aspect < 0.42 || aspect > 5.8) return false;

  return true;
}

function mergeVehicleDetections(detections: VehicleDetectionBox[], frameWidth: number, frameHeight: number): VehicleDetectionBox[] {
  const sorted = [...detections]
    .filter((item) => isVehicleLikeBox(item.bbox, frameWidth, frameHeight))
    .sort((a, b) => b.confidence - a.confidence);
  const selected: VehicleDetectionBox[] = [];

  for (const detection of sorted) {
    const overlapsSelected = selected.some((existing) => {
      const iou = calculateIoU(existing.bbox, detection.bbox);
      const smallerArea = Math.min(getBoxArea(existing.bbox), getBoxArea(detection.bbox));
      const intersectionArea = getIntersectionArea(existing.bbox, detection.bbox);
      return iou > 0.42 || (smallerArea > 0 && intersectionArea / smallerArea > 0.72);
    });

    if (!overlapsSelected) {
      selected.push(detection);
    }
  }

  return selected.slice(0, 12);
}

function getIntersectionArea(boxA: BoundingBox, boxB: BoundingBox): number {
  const xA = Math.max(boxA.x, boxB.x);
  const yA = Math.max(boxA.y, boxB.y);
  const xB = Math.min(boxA.x + boxA.width, boxB.x + boxB.width);
  const yB = Math.min(boxA.y + boxA.height, boxB.y + boxB.height);
  return Math.max(0, xB - xA) * Math.max(0, yB - yA);
}

function getFrameCrop(sourceCanvas: HTMLCanvasElement, bbox: BoundingBox): { canvas: HTMLCanvasElement; bbox: BoundingBox } | null {
  const cropBox = clampCropBox(bbox, sourceCanvas.width, sourceCanvas.height, 0.04, 0.06);
  if (cropBox.width <= 1 || cropBox.height <= 1) return null;

  const canvas = document.createElement('canvas');
  canvas.width = cropBox.width;
  canvas.height = cropBox.height;
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  if (!ctx) return null;

  ctx.drawImage(sourceCanvas, cropBox.x, cropBox.y, cropBox.width, cropBox.height, 0, 0, canvas.width, canvas.height);
  return { canvas, bbox: cropBox };
}

function scoreVehicleFrame(
  cropCanvas: HTMLCanvasElement,
  bbox: BoundingBox,
  frameWidth: number,
  frameHeight: number,
  detectorConfidence: number,
  trackStability: number,
  motionScore: number,
  now: number,
  timestamp: number,
  maxEntryAgeMs: number
): Pick<VehicleFrameEntry, 'qualityScore' | 'sharpnessScore' | 'contrastScore' | 'sizeScore'> {
  const quality = assessCropQuality(cropCanvas);
  const frameArea = Math.max(1, frameWidth * frameHeight);
  const sizeScore = Math.min(1, getBoxArea(bbox) / (frameArea * 0.28));
  const ageScore = Math.max(0, 1 - (now - timestamp) / maxEntryAgeMs);
  const boundedMotionScore = clamp(motionScore, 0, 1);
  const qualityScore = clamp(
    quality.sharpnessScore * 0.28 +
      quality.contrastScore * 0.22 +
      detectorConfidence * 0.18 +
      trackStability * 0.12 +
      sizeScore * 0.12 +
      (1 - boundedMotionScore) * 0.04 +
      ageScore * 0.04,
    0,
    1
  );

  return {
    qualityScore: Math.round(qualityScore * 100) / 100,
    sharpnessScore: quality.sharpnessScore,
    contrastScore: quality.contrastScore,
    sizeScore: Math.round(sizeScore * 100) / 100,
  };
}

export class VehicleMotionDetector {
  private previousLuma: Uint8ClampedArray | null = null;
  private sampleCanvas: HTMLCanvasElement | null = null;
  private sampleCtx: CanvasRenderingContext2D | null = null;
  private readonly sampleWidth: number;
  private readonly sampleHeight: number;
  private readonly motionThreshold: number;

  constructor(
    options: {
      sampleWidth?: number;
      sampleHeight?: number;
      motionThreshold?: number;
    } = {}
  ) {
    this.sampleWidth = Math.max(32, Math.round(options.sampleWidth ?? VEHICLE_FIRST_DEFAULTS.sampleWidth));
    this.sampleHeight = Math.max(18, Math.round(options.sampleHeight ?? VEHICLE_FIRST_DEFAULTS.sampleHeight));
    this.motionThreshold = clamp(
      Math.round(options.motionThreshold ?? VEHICLE_FIRST_DEFAULTS.motionThreshold),
      12,
      70
    );
  }

  public reset(): void {
    this.previousLuma = null;
    if (this.sampleCanvas) {
      this.sampleCanvas.width = 0;
      this.sampleCanvas.height = 0;
    }
    this.sampleCanvas = null;
    this.sampleCtx = null;
  }

  public detect(canvas: HTMLCanvasElement): VehicleDetectionBox[] {
    if (!canvas.width || !canvas.height || typeof document === 'undefined') return [];

    if (!this.sampleCanvas) {
      this.sampleCanvas = document.createElement('canvas');
      this.sampleCanvas.width = this.sampleWidth;
      this.sampleCanvas.height = this.sampleHeight;
      this.sampleCtx = this.sampleCanvas.getContext('2d', { willReadFrequently: true });
    }

    if (!this.sampleCtx || !this.sampleCanvas) return [];

    this.sampleCtx.drawImage(canvas, 0, 0, this.sampleWidth, this.sampleHeight);
    const imageData = this.sampleCtx.getImageData(0, 0, this.sampleWidth, this.sampleHeight);
    const currentLuma = new Uint8ClampedArray(this.sampleWidth * this.sampleHeight);
    const motionMask = new Uint8Array(this.sampleWidth * this.sampleHeight);
    const diffValues = new Uint8ClampedArray(this.sampleWidth * this.sampleHeight);

    for (let i = 0; i < currentLuma.length; i++) {
      const p = i * 4;
      currentLuma[i] = Math.round(
        imageData.data[p] * 0.299 + imageData.data[p + 1] * 0.587 + imageData.data[p + 2] * 0.114
      );
    }

    if (!this.previousLuma || this.previousLuma.length !== currentLuma.length) {
      this.previousLuma = currentLuma;
      return [];
    }

    for (let i = 0; i < currentLuma.length; i++) {
      const diff = Math.abs(currentLuma[i] - this.previousLuma[i]);
      diffValues[i] = diff;
      motionMask[i] = diff >= this.motionThreshold ? 1 : 0;
    }

    this.previousLuma = currentLuma;
    const components = this.extractMotionComponents(motionMask, diffValues);
    const frameArea = canvas.width * canvas.height;
    const detections = components.map((component) => {
      const rawBox = this.componentToFrameBox(component, canvas.width, canvas.height);
      const expandedBox = expandBox(rawBox, canvas.width, canvas.height, 0.34, 0.44);
      const areaScore = Math.min(1, getBoxArea(expandedBox) / Math.max(1, frameArea * 0.18));
      const density = component.count / Math.max(1, (component.maxX - component.minX + 1) * (component.maxY - component.minY + 1));
      const meanDiff = component.diffTotal / Math.max(1, component.count);
      const confidence = clamp(0.35 + areaScore * 0.24 + density * 0.18 + (meanDiff / 255) * 0.18, 0.30, 0.92);

      return {
        bbox: { ...expandedBox, confidence: Math.round(confidence * 1000) / 1000 },
        confidence: Math.round(confidence * 1000) / 1000,
        label: 'vehicle' as const,
        source: 'MOTION' as const,
        motionScore: Math.round((meanDiff / 255) * 100) / 100,
      };
    });

    return mergeVehicleDetections(detections, canvas.width, canvas.height);
  }

  private extractMotionComponents(mask: Uint8Array, diffValues: Uint8ClampedArray): MotionCellComponent[] {
    const visited = new Uint8Array(mask.length);
    const components: MotionCellComponent[] = [];
    const minCellCount = Math.max(8, Math.round((this.sampleWidth * this.sampleHeight) * 0.002));

    for (let i = 0; i < mask.length; i++) {
      if (!mask[i] || visited[i]) continue;

      const queue = [i];
      visited[i] = 1;
      let head = 0;
      let minX = this.sampleWidth;
      let minY = this.sampleHeight;
      let maxX = 0;
      let maxY = 0;
      let count = 0;
      let diffTotal = 0;

      while (head < queue.length) {
        const idx = queue[head++];
        const x = idx % this.sampleWidth;
        const y = Math.floor(idx / this.sampleWidth);
        count++;
        diffTotal += diffValues[idx];
        minX = Math.min(minX, x);
        minY = Math.min(minY, y);
        maxX = Math.max(maxX, x);
        maxY = Math.max(maxY, y);

        for (let dy = -1; dy <= 1; dy++) {
          for (let dx = -1; dx <= 1; dx++) {
            if (dx === 0 && dy === 0) continue;
            const nx = x + dx;
            const ny = y + dy;
            if (nx < 0 || nx >= this.sampleWidth || ny < 0 || ny >= this.sampleHeight) continue;
            const nextIdx = ny * this.sampleWidth + nx;
            if (!mask[nextIdx] || visited[nextIdx]) continue;
            visited[nextIdx] = 1;
            queue.push(nextIdx);
          }
        }
      }

      if (count >= minCellCount) {
        components.push({ minX, minY, maxX, maxY, count, diffTotal });
      }
    }

    return components;
  }

  private componentToFrameBox(component: MotionCellComponent, frameWidth: number, frameHeight: number): BoundingBox {
    const x = (component.minX / this.sampleWidth) * frameWidth;
    const y = (component.minY / this.sampleHeight) * frameHeight;
    const right = ((component.maxX + 1) / this.sampleWidth) * frameWidth;
    const bottom = ((component.maxY + 1) / this.sampleHeight) * frameHeight;

    return {
      x,
      y,
      width: Math.max(1, right - x),
      height: Math.max(1, bottom - y),
      confidence: 0.5,
    };
  }
}

export class VehicleFrameBuffer {
  private buffers: Map<number, VehicleFrameEntry[]> = new Map();
  private maxFramesPerVehicle: number = VEHICLE_FIRST_DEFAULTS.maxFramesPerVehicle;
  private maxEntryAgeMs: number = VEHICLE_FIRST_DEFAULTS.maxEntryAgeMs;
  private maxVehicleBuffers: number = VEHICLE_FIRST_DEFAULTS.maxVehicleBuffers;
  private plateSearchIntervalMs: number = VEHICLE_FIRST_DEFAULTS.plateSearchIntervalMs;
  private maxPlateSearchesPerEntry: number = VEHICLE_FIRST_DEFAULTS.maxPlateSearchesPerEntry;

  public configure(
    options: {
      maxFramesPerVehicle?: number;
      maxEntryAgeMs?: number;
      maxVehicleBuffers?: number;
      plateSearchIntervalMs?: number;
      maxPlateSearchesPerEntry?: number;
    } = {}
  ): void {
    if (typeof options.maxFramesPerVehicle === 'number') {
      this.maxFramesPerVehicle = clamp(Math.round(options.maxFramesPerVehicle), 3, 20);
    }
    if (typeof options.maxEntryAgeMs === 'number') {
      this.maxEntryAgeMs = clamp(Math.round(options.maxEntryAgeMs), 1000, 10000);
    }
    if (typeof options.maxVehicleBuffers === 'number') {
      this.maxVehicleBuffers = clamp(Math.round(options.maxVehicleBuffers), 1, 24);
    }
    if (typeof options.plateSearchIntervalMs === 'number') {
      this.plateSearchIntervalMs = clamp(Math.round(options.plateSearchIntervalMs), 100, 1500);
    }
    if (typeof options.maxPlateSearchesPerEntry === 'number') {
      this.maxPlateSearchesPerEntry = clamp(Math.round(options.maxPlateSearchesPerEntry), 1, 8);
    }
  }

  public addFrameCandidate(
    vehicleTrackNumber: number,
    sourceCanvas: HTMLCanvasElement,
    bbox: BoundingBox,
    options: {
      trackStability?: number;
      motionScore?: number;
      detectorConfidence?: number;
      now?: number;
    } = {}
  ): VehicleFrameEntry | null {
    const now = options.now ?? Date.now();
    this.pruneStale(undefined, now);

    const crop = getFrameCrop(sourceCanvas, bbox);
    if (!crop) return null;

    const detectorConfidence = clamp(options.detectorConfidence ?? bbox.confidence ?? 0.55, 0, 1);
    const trackStability = clamp(options.trackStability ?? 0.55, 0, 1);
    const motionScore = clamp(options.motionScore ?? 0, 0, 1);
    const frameScore = scoreVehicleFrame(
      crop.canvas,
      crop.bbox,
      sourceCanvas.width,
      sourceCanvas.height,
      detectorConfidence,
      trackStability,
      motionScore,
      now,
      now,
      this.maxEntryAgeMs
    );

    const entry: VehicleFrameEntry = {
      id: `${vehicleTrackNumber}_${now}_${Math.random().toString(36).slice(2, 7)}`,
      canvas: crop.canvas,
      timestamp: now,
      bbox: crop.bbox,
      detectorConfidence,
      trackStability,
      motionScore,
      ...frameScore,
      plateSearchCount: 0,
    };

    if (!this.buffers.has(vehicleTrackNumber)) {
      this.buffers.set(vehicleTrackNumber, []);
    }

    const buffer = this.buffers.get(vehicleTrackNumber)!;
    buffer.push(entry);
    this.rankAndTrim(vehicleTrackNumber, now);
    this.pruneOverflowTracks();

    return entry;
  }

  public getSearchCandidates(
    activeVehicleTrackNumbers: Set<number>,
    options: {
      limit?: number;
      now?: number;
      includeRecentlySearched?: boolean;
    } = {}
  ): VehicleFrameEntry[] {
    const now = options.now ?? Date.now();
    const limit = clamp(Math.round(options.limit ?? VEHICLE_FIRST_DEFAULTS.maxPlateSearchFrames), 1, 8);
    this.pruneStale(activeVehicleTrackNumbers, now);

    const candidates = Array.from(this.buffers.entries())
      .filter(([trackNumber]) => activeVehicleTrackNumbers.has(trackNumber))
      .flatMap(([, entries]) => entries)
      .filter((entry) => {
        if (entry.plateSearchCount >= this.maxPlateSearchesPerEntry) return false;
        if (options.includeRecentlySearched) return true;
        return !entry.lastPlateSearchAt || now - entry.lastPlateSearchAt >= this.plateSearchIntervalMs;
      })
      .sort((a, b) => this.scoreEntry(b, now) - this.scoreEntry(a, now));

    return candidates.slice(0, limit);
  }

  public markPlateSearch(entry: VehicleFrameEntry, now = Date.now()): void {
    entry.plateSearchCount++;
    entry.lastPlateSearchAt = now;
  }

  public getBufferedFrameCount(trackNumber?: number): number {
    if (typeof trackNumber === 'number') {
      return this.buffers.get(trackNumber)?.length ?? 0;
    }

    return Array.from(this.buffers.values()).reduce((sum, entries) => sum + entries.length, 0);
  }

  public clearTrack(trackNumber: number): void {
    const buffer = this.buffers.get(trackNumber);
    if (!buffer) return;
    buffer.forEach((entry) => releaseCanvasMemory(entry.canvas));
    this.buffers.delete(trackNumber);
  }

  public clearExcept(activeTrackNumbers: Set<number>): void {
    for (const trackNumber of Array.from(this.buffers.keys())) {
      if (!activeTrackNumbers.has(trackNumber)) {
        this.clearTrack(trackNumber);
      }
    }
  }

  public pruneStale(activeTrackNumbers?: Set<number>, now = Date.now()): void {
    for (const [trackNumber, entries] of Array.from(this.buffers.entries())) {
      if (activeTrackNumbers && !activeTrackNumbers.has(trackNumber)) {
        this.clearTrack(trackNumber);
        continue;
      }

      const fresh = entries.filter((entry) => now - entry.timestamp <= this.maxEntryAgeMs);
      entries
        .filter((entry) => now - entry.timestamp > this.maxEntryAgeMs)
        .forEach((entry) => releaseCanvasMemory(entry.canvas));

      if (fresh.length === 0) {
        this.buffers.delete(trackNumber);
      } else {
        this.buffers.set(trackNumber, fresh);
        this.rankAndTrim(trackNumber, now);
      }
    }

    this.pruneOverflowTracks();
  }

  public resetAll(): void {
    for (const buffer of this.buffers.values()) {
      buffer.forEach((entry) => releaseCanvasMemory(entry.canvas));
    }
    this.buffers.clear();
  }

  private scoreEntry(entry: VehicleFrameEntry, now: number): number {
    const ageScore = Math.max(0, 1 - (now - entry.timestamp) / this.maxEntryAgeMs);
    const searchPenalty = Math.min(0.28, entry.plateSearchCount * 0.08);

    return (
      entry.qualityScore * 0.48 +
      entry.detectorConfidence * 0.16 +
      entry.trackStability * 0.12 +
      entry.sizeScore * 0.10 +
      ageScore * 0.10 +
      (1 - entry.motionScore) * 0.04 -
      searchPenalty
    );
  }

  private rankAndTrim(trackNumber: number, now: number): void {
    const buffer = this.buffers.get(trackNumber);
    if (!buffer) return;

    buffer.sort((a, b) => this.scoreEntry(b, now) - this.scoreEntry(a, now));
    while (buffer.length > this.maxFramesPerVehicle) {
      const removed = buffer.pop();
      if (removed) releaseCanvasMemory(removed.canvas);
    }
  }

  private pruneOverflowTracks(): void {
    if (this.buffers.size <= this.maxVehicleBuffers) return;

    const ranked = Array.from(this.buffers.entries()).sort((a, b) => {
      const newestA = Math.max(...a[1].map((entry) => entry.timestamp));
      const newestB = Math.max(...b[1].map((entry) => entry.timestamp));
      return newestB - newestA;
    });

    for (const [trackNumber] of ranked.slice(this.maxVehicleBuffers)) {
      this.clearTrack(trackNumber);
    }
  }
}

export function expandPlateDetectionsToVehicleDetections(
  plates: DetectedPlateBox[],
  frameWidth: number,
  frameHeight: number
): VehicleDetectionBox[] {
  const detections = plates.map((plate) => {
    const plateBox = plate.bbox;
    const vehicleWidth = clamp(plateBox.width * 5.4, plateBox.width * 2.8, frameWidth * 0.86);
    const vehicleHeight = clamp(plateBox.height * 7.4, plateBox.height * 3.2, frameHeight * 0.82);
    const plateCenterX = plateBox.x + plateBox.width / 2;
    const plateCenterY = plateBox.y + plateBox.height / 2;
    const candidate = clampBoxToFrame(
      {
        x: plateCenterX - vehicleWidth / 2,
        y: plateCenterY - vehicleHeight * 0.72,
        width: vehicleWidth,
        height: vehicleHeight,
        confidence: clamp(plate.confidence * 0.86 + 0.12, 0.35, 0.96),
      },
      frameWidth,
      frameHeight
    );

    return {
      bbox: candidate,
      confidence: candidate.confidence,
      label: 'vehicle' as const,
      source: 'PLATE_SEED' as const,
      motionScore: 0,
    };
  });

  return mergeVehicleDetections(detections, frameWidth, frameHeight);
}

export function combineVehicleDetections(
  detections: VehicleDetectionBox[],
  frameWidth: number,
  frameHeight: number
): VehicleDetectionBox[] {
  return mergeVehicleDetections(detections, frameWidth, frameHeight);
}

export function mapVehiclePlateDetectionsToFrame(
  entry: VehicleFrameEntry,
  detections: DetectedPlateBox[]
): DetectedPlateBox[] {
  const scaleX = entry.bbox.width / Math.max(1, entry.canvas.width);
  const scaleY = entry.bbox.height / Math.max(1, entry.canvas.height);

  return detections.map((detection) => ({
    ...detection,
    bbox: {
      x: Math.round(entry.bbox.x + detection.bbox.x * scaleX),
      y: Math.round(entry.bbox.y + detection.bbox.y * scaleY),
      width: Math.round(detection.bbox.width * scaleX),
      height: Math.round(detection.bbox.height * scaleY),
    },
    confidence: Math.round(Math.min(0.99, detection.confidence * 0.97) * 1000) / 1000,
  }));
}

export function combinePlateDetectionsWithNms(
  primaryDetections: DetectedPlateBox[],
  bufferedDetections: DetectedPlateBox[],
  frameWidth: number,
  frameHeight: number,
  iouThreshold = 0.45
): DetectedPlateBox[] {
  const all = [...primaryDetections, ...bufferedDetections]
    .filter((detection) => {
      const box = detection.bbox;
      if (box.width < Math.max(24, frameWidth * 0.018)) return false;
      if (box.height < Math.max(8, frameHeight * 0.008)) return false;
      const aspect = box.width / Math.max(1, box.height);
      return aspect >= 0.75 && aspect <= 7.2;
    })
    .sort((a, b) => b.confidence - a.confidence);
  const selected: DetectedPlateBox[] = [];

  for (const detection of all) {
    const bbox = {
      ...detection.bbox,
      confidence: detection.confidence,
    };
    const overlaps = selected.some((existing) => {
      const existingBox = { ...existing.bbox, confidence: existing.confidence };
      return calculateIoU(existingBox, bbox) > iouThreshold;
    });

    if (!overlaps) {
      selected.push(detection);
    }
  }

  return selected.slice(0, 12);
}
