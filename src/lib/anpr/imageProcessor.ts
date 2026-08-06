import { BoundingBox } from './tracker';
import { PlateLayout } from '../db/types';

export type PreprocessVariant =
  | 'ORIGINAL'
  | 'GRAYSCALE'
  | 'DEFAULT_CONTRAST'
  | 'INVERTED'
  | 'CLAHE'
  | 'SHARPEN'
  | 'DARK_BG'
  | 'NOISE_REDUCED'
  | 'GAMMA_BRIGHTEN'
  | 'HIGHLIGHT_REDUCED'
  | 'PERSPECTIVE'
  | 'ADAPTIVE_THRESHOLD'
  | 'BLACKHAT'
  | 'TOPHAT'
  | 'CONTRAST_BOOST'
  | 'WIDE_CROP'
  | 'LARGE_TEXT';

export interface MultiCropResult {
  variant: PreprocessVariant;
  canvas: HTMLCanvasElement;
  qualityScore: number;
  layout: PlateLayout;
  isTwoLine: boolean;
  topLineCanvas?: HTMLCanvasElement;
  bottomLineCanvas?: HTMLCanvasElement;
}

export type CanvasRotationDegrees = 0 | 90 | 180 | 270;

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

export function releaseCanvasMemory(canvas?: HTMLCanvasElement | null): void {
  if (!canvas) return;
  canvas.width = 0;
  canvas.height = 0;
}

export function rotateCanvas(sourceCanvas: HTMLCanvasElement, rotationDegrees: CanvasRotationDegrees): HTMLCanvasElement {
  const normalizedRotation = (((rotationDegrees % 360) + 360) % 360) as CanvasRotationDegrees;
  const output = document.createElement('canvas');
  const swapsAxes = normalizedRotation === 90 || normalizedRotation === 270;
  output.width = swapsAxes ? sourceCanvas.height : sourceCanvas.width;
  output.height = swapsAxes ? sourceCanvas.width : sourceCanvas.height;

  const ctx = output.getContext('2d', { willReadFrequently: true });
  if (!ctx || sourceCanvas.width <= 0 || sourceCanvas.height <= 0) return output;

  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = 'high';
  ctx.save();
  if (normalizedRotation === 90) {
    ctx.translate(output.width, 0);
    ctx.rotate(Math.PI / 2);
  } else if (normalizedRotation === 180) {
    ctx.translate(output.width, output.height);
    ctx.rotate(Math.PI);
  } else if (normalizedRotation === 270) {
    ctx.translate(0, output.height);
    ctx.rotate(-Math.PI / 2);
  }
  ctx.drawImage(sourceCanvas, 0, 0);
  ctx.restore();

  return output;
}

function getSourceDimensions(sourceCanvas: HTMLCanvasElement | HTMLVideoElement): { width: number; height: number } {
  if (typeof HTMLVideoElement !== 'undefined' && sourceCanvas instanceof HTMLVideoElement) {
    return {
      width: sourceCanvas.videoWidth || sourceCanvas.width || 0,
      height: sourceCanvas.videoHeight || sourceCanvas.height || 0,
    };
  }

  return {
    width: sourceCanvas.width || 0,
    height: sourceCanvas.height || 0,
  };
}

export function clampCropBox(
  bbox: BoundingBox,
  sourceWidth: number,
  sourceHeight: number,
  paddingRatioX = 0.08,
  paddingRatioY = 0.12
): BoundingBox {
  const padX = Math.max(0, bbox.width * paddingRatioX);
  const padY = Math.max(0, bbox.height * paddingRatioY);
  const x = clamp(Math.round(bbox.x - padX), 0, Math.max(0, sourceWidth - 1));
  const y = clamp(Math.round(bbox.y - padY), 0, Math.max(0, sourceHeight - 1));
  const right = clamp(Math.round(bbox.x + bbox.width + padX), x + 1, sourceWidth);
  const bottom = clamp(Math.round(bbox.y + bbox.height + padY), y + 1, sourceHeight);

  return {
    x,
    y,
    width: Math.max(1, right - x),
    height: Math.max(1, bottom - y),
    confidence: bbox.confidence,
  };
}

export function scaleBoundingBox(
  bbox: BoundingBox,
  scaleX: number,
  scaleY: number
): BoundingBox {
  return {
    x: bbox.x * scaleX,
    y: bbox.y * scaleY,
    width: bbox.width * scaleX,
    height: bbox.height * scaleY,
    confidence: bbox.confidence,
  };
}

function getAdaptiveCropTargetSize(
  bbox: BoundingBox,
  targetWidth: number,
  targetHeight: number
): { width: number; height: number } {
  const rawAspect = bbox.width / Math.max(1, bbox.height);
  const aspect = Number.isFinite(rawAspect) ? clamp(rawAspect, 0.65, 8.8) : 3.3;

  if (aspect < 2.3) {
    const width = aspect < 1.6 ? 288 : 336;
    return {
      width,
      height: clamp(Math.round(width / aspect), 128, 320),
    };
  }

  return {
    width: targetWidth,
    height: clamp(Math.round(targetWidth / aspect), 56, targetHeight),
  };
}

/**
 * CV Heuristic Candidate Region Detection (Fallback when ONNX model is unavailable).
 */
export function detectPlateCandidatesCV(
  canvas: HTMLCanvasElement,
  minConfidence: number = 0.35,
  maxCandidates: number = 8
): { crop: BoundingBox; confidence: number }[] {
  const W = canvas.width;
  const H = canvas.height;

  if (W === 0 || H === 0) return [];

  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  if (!ctx) return [];

  const candidates: BoundingBox[] = [];
  const plateAspectRatios = [8.4, 7.6, 6.6, 5.6, 4.7, 3.8, 3.2, 2.4, 1.8, 1.25, 0.95];
  const scanScales = [0.08, 0.12, 0.18, 0.25, 0.35, 0.45, 0.55];

  for (const scale of scanScales) {
    const plateW = Math.round(W * scale);

    for (const ar of plateAspectRatios) {
      const plateH = Math.round(plateW / ar);
      if (plateH < 14 || plateW < 50) continue;

      const stepX = Math.max(Math.round(plateW * 0.35), 20);
      const stepY = Math.max(Math.round(plateH * 0.6), 12);

      for (let y = 0; y <= H - plateH; y += stepY) {
        for (let x = 0; x <= W - plateW; x += stepX) {
          const score = scorePlateCandidateRegion(ctx, x, y, plateW, plateH);
          if (score >= minConfidence) {
            candidates.push({
              x,
              y,
              width: plateW,
              height: plateH,
              confidence: score,
            });
          }
        }
      }
    }
  }

  const nmsResult = applyNMS(candidates, 0.30);
  const mergedResult = mergeAdjacentBoxes(nmsResult);
  mergedResult.sort((a, b) => b.confidence - a.confidence);
  return mergedResult.slice(0, Math.max(1, maxCandidates)).map((box) => ({
    crop: box,
    confidence: box.confidence,
  }));
}

/**
 * Merges horizontally aligned and adjacent candidate boxes (e.g. "YA" and "8055" on the same plate).
 */
function mergeAdjacentBoxes(boxes: BoundingBox[]): BoundingBox[] {
  if (boxes.length <= 1) return boxes;
  let result = [...boxes];
  let changed = true;

  while (changed) {
    changed = false;
    const nextList: BoundingBox[] = [];
    const mergedIndices = new Set<number>();

    for (let i = 0; i < result.length; i++) {
      if (mergedIndices.has(i)) continue;
      let cur = { ...result[i] };

      for (let j = i + 1; j < result.length; j++) {
        if (mergedIndices.has(j)) continue;
        const b = result[j];

        // Check vertical overlap (same row/line)
        const yOverlap = Math.max(0, Math.min(cur.y + cur.height, b.y + b.height) - Math.max(cur.y, b.y));
        const minH = Math.min(cur.height, b.height);
        const isVerticallyAligned = minH > 0 && (yOverlap / minH) > 0.4;

        // Check horizontal proximity (gap between boxes)
        const curRight = cur.x + cur.width;
        const bRight = b.x + b.width;
        const gap = Math.max(0, Math.max(cur.x, b.x) - Math.min(curRight, bRight));
        const maxW = Math.max(cur.width, b.width);
        const isHorizontallyClose = gap < maxW * 1.2;

        if (isVerticallyAligned && isHorizontallyClose) {
          const newX = Math.min(cur.x, b.x);
          const newY = Math.min(cur.y, b.y);
          const newW = Math.max(curRight, bRight) - newX;
          const newH = Math.max(cur.y + cur.height, b.y + b.height) - newY;
          
          // Verify aspect ratio of merged box is still realistic for a plate, including long special series.
          const mergedAR = newW / Math.max(1, newH);
          if (mergedAR >= 0.65 && mergedAR <= 8.8) {
            cur = {
              x: newX,
              y: newY,
              width: newW,
              height: newH,
              confidence: Math.max(cur.confidence || 0, b.confidence || 0),
            };
            mergedIndices.add(j);
            changed = true;
          }
        }
      }
      mergedIndices.add(i);
      nextList.push(cur);
    }
    result = nextList;
  }

  return result;
}

/**
 * Scores candidate region for plate-like contrast, edge density, and horizontal bias.
 */
function scorePlateCandidateRegion(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  w: number,
  h: number
): number {
  const sampleStep = 3;
  const imgData = ctx.getImageData(x, y, w, h);
  const data = imgData.data;
  const totalPx = w * h;

  if (totalPx === 0) return 0;

  const gray: number[] = new Array(totalPx);
  for (let i = 0; i < totalPx; i++) {
    const p = i * 4;
    gray[i] = 0.299 * data[p] + 0.587 * data[p + 1] + 0.114 * data[p + 2];
  }

  let edgeSum = 0;
  let edgeSamples = 0;
  for (let row = 1; row < h - 1; row += sampleStep) {
    for (let col = 1; col < w - 1; col += sampleStep) {
      const tl = gray[(row - 1) * w + (col - 1)];
      const t  = gray[(row - 1) * w + col];
      const tr = gray[(row - 1) * w + (col + 1)];
      const bl = gray[(row + 1) * w + (col - 1)];
      const b  = gray[(row + 1) * w + col];
      const br = gray[(row + 1) * w + (col + 1)];

      const gy = -tl - 2 * t - tr + bl + 2 * b + br;
      edgeSum += Math.abs(gy);
      edgeSamples++;
    }
  }

  const avgEdge = edgeSamples > 0 ? edgeSum / edgeSamples : 0;

  let mean = 0;
  const sampleCount = Math.floor(totalPx / sampleStep);
  for (let i = 0; i < totalPx; i += sampleStep) mean += gray[i];
  mean /= sampleCount;

  let variance = 0;
  for (let i = 0; i < totalPx; i += sampleStep) {
    const d = gray[i] - mean;
    variance += d * d;
  }
  variance /= sampleCount;
  const stdDev = Math.sqrt(variance);

  let hEdge = 0, vEdge = 0;
  for (let row = 1; row < h - 1; row += sampleStep * 2) {
    for (let col = 1; col < w - 1; col += sampleStep * 2) {
      const c  = gray[row * w + col];
      const r  = gray[row * w + (col + 1)];
      const dn = gray[(row + 1) * w + col];
      hEdge += Math.abs(c - r);
      vEdge += Math.abs(c - dn);
    }
  }
  const hRatio = hEdge + vEdge > 0 ? hEdge / (hEdge + vEdge) : 0.5;

  const edgeScore     = Math.min(1.0, avgEdge / 40);
  const contrastScore = Math.min(1.0, stdDev / 80);
  const edgeRatioScore = Math.min(1.0, hRatio / 0.6);

  return Math.min(1.0, edgeScore * 0.45 + contrastScore * 0.35 + edgeRatioScore * 0.20);
}

/**
 * Non-Maximum Suppression
 */
export function applyNMS(boxes: BoundingBox[], iouThreshold: number = 0.4): BoundingBox[] {
  if (boxes.length === 0) return [];

  const sorted = [...boxes].sort((a, b) => b.confidence - a.confidence);
  const kept: BoundingBox[] = [];
  const suppressed = new Set<number>();

  for (let i = 0; i < sorted.length; i++) {
    if (suppressed.has(i)) continue;
    kept.push(sorted[i]);

    for (let j = i + 1; j < sorted.length; j++) {
      if (suppressed.has(j)) continue;
      const iou = computeBoxIoU(sorted[i], sorted[j]);
      if (iou > iouThreshold) {
        suppressed.add(j);
      }
    }
  }

  return kept;
}

function computeBoxIoU(a: BoundingBox, b: BoundingBox): number {
  const ix = Math.max(0, Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x));
  const iy = Math.max(0, Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y));
  const inter = ix * iy;
  if (inter === 0) return 0;
  const union = a.width * a.height + b.width * b.height - inter;
  return inter / union;
}

/**
 * Generate adaptive image preprocessing versions for OCR recognition across
 * black, white, reflective, two-line, square, and special-series plate crops.
 */
export function generateAdaptiveCrops(
  sourceCanvas: HTMLCanvasElement | HTMLVideoElement,
  bbox: BoundingBox,
  targetWidth: number = 360,
  targetHeight: number = 108,
  variantsOverride?: PreprocessVariant[]
): MultiCropResult[] {
  const results: MultiCropResult[] = [];

  const ar = bbox.width / (bbox.height || 1);
  const isTwoLine = ar < 2.3;
  const layout: PlateLayout = isTwoLine ? (ar < 1.6 ? 'SQUARE' : 'TWO_LINE') : 'SINGLE_LINE';

  const variants: PreprocessVariant[] = variantsOverride ?? [
    'ORIGINAL',
    'PERSPECTIVE',
    'GRAYSCALE',
    'DEFAULT_CONTRAST',
    'INVERTED',
    'CLAHE',
    'SHARPEN',
    'DARK_BG',
    'NOISE_REDUCED',
    'GAMMA_BRIGHTEN',
    'HIGHLIGHT_REDUCED',
  ];

  for (const variant of variants) {
    const cropCanvas = document.createElement('canvas');
    const outputSize = variant === 'WIDE_CROP'
      ? getAdaptiveCropTargetSize(
          { ...bbox, width: bbox.width * 1.18 },
          Math.max(targetWidth, 440),
          Math.max(targetHeight, 124)
        )
      : getAdaptiveCropTargetSize(bbox, targetWidth, targetHeight);

    // Auto-upscale small plates from distant vehicles
    let scaleFactor = 1.0;
    if (bbox.width < 120 || bbox.height < 35) {
      scaleFactor = 1.6; // Upscale distant small plates
    }
    if (variant === 'LARGE_TEXT') {
      scaleFactor = Math.max(scaleFactor, 1.35);
    }

    const scaledW = Math.round(outputSize.width * scaleFactor);
    const scaledH = Math.round(outputSize.height * scaleFactor);

    cropCanvas.width = scaledW;
    cropCanvas.height = scaledH;
    const ctx = cropCanvas.getContext('2d', { willReadFrequently: true });
    if (!ctx) continue;

    const { width: sourceWidth, height: sourceHeight } = getSourceDimensions(sourceCanvas);
    const cropBox = variant === 'WIDE_CROP'
      ? clampCropBox(bbox, sourceWidth, sourceHeight, 0.18, 0.14)
      : variant === 'LARGE_TEXT'
        ? clampCropBox(bbox, sourceWidth, sourceHeight, 0.04, 0.06)
        : clampCropBox(bbox, sourceWidth, sourceHeight);

    ctx.drawImage(sourceCanvas, cropBox.x, cropBox.y, cropBox.width, cropBox.height, 0, 0, scaledW, scaledH);

    // Apply specific preprocessing variant
    preprocessCropVariant(ctx, scaledW, scaledH, variant);

    const quality = calculateCropQualityScore(ctx, scaledW, scaledH);

    let topLineCanvas: HTMLCanvasElement | undefined;
    let bottomLineCanvas: HTMLCanvasElement | undefined;

    if (isTwoLine) {
      const lineCrops = splitTwoLineCrop(cropCanvas);
      topLineCanvas = lineCrops.top;
      bottomLineCanvas = lineCrops.bottom;
    }

    results.push({
      variant,
      canvas: cropCanvas,
      qualityScore: quality,
      layout,
      isTwoLine,
      topLineCanvas,
      bottomLineCanvas,
    });
  }

  results.sort((a, b) => b.qualityScore - a.qualityScore);
  return results;
}

/**
 * Applies specified preprocessing transformation variant to canvas context.
 */
export function preprocessCropVariant(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  variant: PreprocessVariant
): void {
  if (variant === 'ORIGINAL') return;
  if (variant === 'PERSPECTIVE') {
    applyPerspectiveRectification(ctx, width, height);
    return;
  }
  if (variant === 'WIDE_CROP') return;

  const imgData = ctx.getImageData(0, 0, width, height);
  const data = imgData.data;

  let minL = 255, maxL = 0;

  for (let i = 0; i < data.length; i += 4) {
    const gray = Math.round(0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2]);
    data[i] = data[i + 1] = data[i + 2] = gray;
    if (gray < minL) minL = gray;
    if (gray > maxL) maxL = gray;
  }

  const range = maxL - minL || 1;

  if (variant === 'GRAYSCALE') {
    ctx.putImageData(imgData, 0, 0);
    return;
  }

  if (variant === 'DEFAULT_CONTRAST') {
    const threshold = minL + range * 0.48;
    for (let i = 0; i < data.length; i += 4) {
      const v = data[i] > threshold ? 255 : 0;
      data[i] = data[i + 1] = data[i + 2] = v;
    }
  } else if (variant === 'CONTRAST_BOOST') {
    for (let i = 0; i < data.length; i += 4) {
      const normalized = (data[i] - minL) / range;
      const boosted = clamp((normalized - 0.5) * 1.55 + 0.5, 0, 1);
      data[i] = data[i + 1] = data[i + 2] = Math.round(boosted * 255);
    }
  } else if (variant === 'ADAPTIVE_THRESHOLD') {
    applyAdaptiveThreshold(data, width, height);
  } else if (variant === 'BLACKHAT') {
    applyMorphologicalContrast(data, width, height, 'BLACKHAT');
  } else if (variant === 'TOPHAT') {
    applyMorphologicalContrast(data, width, height, 'TOPHAT');
  } else if (variant === 'INVERTED') {
    // Inverted for White background plates (JPJePlate EV, Taxis) -> turn black text to white for OCR
    const threshold = minL + range * 0.52;
    for (let i = 0; i < data.length; i += 4) {
      const v = data[i] < threshold ? 255 : 0;
      data[i] = data[i + 1] = data[i + 2] = v;
    }
  } else if (variant === 'CLAHE') {
    for (let i = 0; i < data.length; i += 4) {
      const norm = Math.round(((data[i] - minL) / range) * 255);
      const v = norm > 128 ? 255 : 0;
      data[i] = data[i + 1] = data[i + 2] = v;
    }
  } else if (variant === 'DARK_BG') {
    // Optimized for Standard Black Malaysian License Plates
    const threshold = minL + range * 0.60;
    for (let i = 0; i < data.length; i += 4) {
      const v = data[i] > threshold ? 255 : 0;
      data[i] = data[i + 1] = data[i + 2] = v;
    }
  } else if (variant === 'SHARPEN') {
    // Sharpening Kernel Filter
    ctx.putImageData(imgData, 0, 0);
    applySharpenKernel(ctx, width, height);
    return;
  } else if (variant === 'NOISE_REDUCED') {
    // 3x3 Box blur box filter
    for (let y = 1; y < height - 1; y++) {
      for (let x = 1; x < width - 1; x++) {
        const idx = (y * width + x) * 4;
        let avg = 0;
        for (let dy = -1; dy <= 1; dy++) {
          for (let dx = -1; dx <= 1; dx++) {
            avg += data[((y + dy) * width + (x + dx)) * 4];
          }
        }
        data[idx] = data[idx + 1] = data[idx + 2] = Math.round(avg / 9);
      }
    }
  } else if (variant === 'GAMMA_BRIGHTEN') {
    for (let i = 0; i < data.length; i += 4) {
      const normalized = data[i] / 255;
      const v = Math.round(Math.pow(normalized, 0.68) * 255);
      data[i] = data[i + 1] = data[i + 2] = v;
    }
  } else if (variant === 'HIGHLIGHT_REDUCED') {
    for (let i = 0; i < data.length; i += 4) {
      const normalized = data[i] / 255;
      const compressed = normalized > 0.70
        ? 0.70 + (normalized - 0.70) * 0.45
        : normalized;
      const v = Math.round(clamp(compressed * 1.08, 0, 1) * 255);
      data[i] = data[i + 1] = data[i + 2] = v;
    }
  } else if (variant === 'LARGE_TEXT') {
    for (let i = 0; i < data.length; i += 4) {
      const norm = Math.round(((data[i] - minL) / range) * 255);
      data[i] = data[i + 1] = data[i + 2] = norm;
    }
    ctx.putImageData(imgData, 0, 0);
    applySharpenKernel(ctx, width, height);
    return;
  }

  ctx.putImageData(imgData, 0, 0);
}

function applyAdaptiveThreshold(data: Uint8ClampedArray, width: number, height: number): void {
  const src = new Uint8ClampedArray(data);
  const radius = Math.max(3, Math.min(9, Math.round(Math.min(width, height) / 18)));

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      let sum = 0;
      let count = 0;

      for (let yy = Math.max(0, y - radius); yy <= Math.min(height - 1, y + radius); yy++) {
        for (let xx = Math.max(0, x - radius); xx <= Math.min(width - 1, x + radius); xx++) {
          sum += src[(yy * width + xx) * 4];
          count++;
        }
      }

      const idx = (y * width + x) * 4;
      const threshold = sum / Math.max(1, count) - 6;
      const v = src[idx] > threshold ? 255 : 0;
      data[idx] = data[idx + 1] = data[idx + 2] = v;
    }
  }
}

function applyMorphologicalContrast(
  data: Uint8ClampedArray,
  width: number,
  height: number,
  mode: 'BLACKHAT' | 'TOPHAT'
): void {
  const src = new Uint8ClampedArray(data);
  const radius = Math.max(1, Math.min(3, Math.round(Math.min(width, height) / 50)));

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      let localMin = 255;
      let localMax = 0;

      for (let yy = Math.max(0, y - radius); yy <= Math.min(height - 1, y + radius); yy++) {
        for (let xx = Math.max(0, x - radius); xx <= Math.min(width - 1, x + radius); xx++) {
          const v = src[(yy * width + xx) * 4];
          if (v < localMin) localMin = v;
          if (v > localMax) localMax = v;
        }
      }

      const idx = (y * width + x) * 4;
      const original = src[idx];
      const enhanced = mode === 'BLACKHAT'
        ? clamp((localMax - original) * 1.7, 0, 255)
        : clamp((original - localMin) * 1.7, 0, 255);
      data[idx] = data[idx + 1] = data[idx + 2] = Math.round(enhanced);
    }
  }
}

function applySharpenKernel(ctx: CanvasRenderingContext2D, width: number, height: number): void {
  const imgData = ctx.getImageData(0, 0, width, height);
  const src = new Uint8ClampedArray(imgData.data);
  const dst = imgData.data;

  // Kernel: [[0, -1, 0], [-1, 5, -1], [0, -1, 0]]
  for (let y = 1; y < height - 1; y++) {
    for (let x = 1; x < width - 1; x++) {
      const idx = (y * width + x) * 4;
      const c = src[idx] * 5;
      const top = src[((y - 1) * width + x) * 4];
      const bot = src[((y + 1) * width + x) * 4];
      const left = src[(y * width + (x - 1)) * 4];
      const right = src[(y * width + (x + 1)) * 4];

      const val = Math.min(255, Math.max(0, c - top - bot - left - right));
      dst[idx] = dst[idx + 1] = dst[idx + 2] = val;
    }
  }

  ctx.putImageData(imgData, 0, 0);
}

interface Point2D {
  x: number;
  y: number;
}

interface WeightedPoint2D extends Point2D {
  weight: number;
}

interface Line2D {
  slope: number;
  intercept: number;
}

function applyPerspectiveRectification(ctx: CanvasRenderingContext2D, width: number, height: number): void {
  if (width < 32 || height < 16) return;

  const source = ctx.getImageData(0, 0, width, height);
  const quad = estimateReadablePlateQuad(source, width, height);
  if (!quad) return;

  const homography = computeHomography(
    [
      { x: 0, y: 0 },
      { x: width - 1, y: 0 },
      { x: width - 1, y: height - 1 },
      { x: 0, y: height - 1 },
    ],
    quad
  );
  if (!homography) return;

  const output = ctx.createImageData(width, height);
  const src = source.data;
  const dst = output.data;

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const denom = homography[6] * x + homography[7] * y + 1;
      if (Math.abs(denom) < 1e-6) continue;

      const sx = (homography[0] * x + homography[1] * y + homography[2]) / denom;
      const sy = (homography[3] * x + homography[4] * y + homography[5]) / denom;
      const outIdx = (y * width + x) * 4;

      sampleBilinear(src, width, height, sx, sy, dst, outIdx);
    }
  }

  ctx.putImageData(output, 0, 0);
}

function estimateReadablePlateQuad(
  image: ImageData,
  width: number,
  height: number
): [Point2D, Point2D, Point2D, Point2D] | null {
  const luma = new Float32Array(width * height);
  const data = image.data;

  for (let i = 0; i < width * height; i++) {
    const offset = i * 4;
    luma[i] = data[offset] * 0.299 + data[offset + 1] * 0.587 + data[offset + 2] * 0.114;
  }

  const sampleStep = Math.max(1, Math.floor(Math.max(width, height) / 180));
  const marginX = Math.max(2, Math.round(width * 0.03));
  const marginY = Math.max(2, Math.round(height * 0.04));
  let edgeSum = 0;
  let edgeSqSum = 0;
  let edgeCount = 0;

  for (let y = marginY + sampleStep; y < height - marginY - sampleStep; y += sampleStep) {
    for (let x = marginX + sampleStep; x < width - marginX - sampleStep; x += sampleStep) {
      const idx = y * width + x;
      const gx = Math.abs(luma[idx + sampleStep] - luma[idx - sampleStep]);
      const gy = Math.abs(luma[idx + width * sampleStep] - luma[idx - width * sampleStep]);
      const edge = gx + gy;
      edgeSum += edge;
      edgeSqSum += edge * edge;
      edgeCount++;
    }
  }

  if (edgeCount < 12) return null;
  const edgeMean = edgeSum / edgeCount;
  const edgeStd = Math.sqrt(Math.max(0, edgeSqSum / edgeCount - edgeMean * edgeMean));
  const threshold = Math.max(26, edgeMean + edgeStd * 0.65);
  const points: WeightedPoint2D[] = [];
  const xValues: number[] = [];

  for (let y = marginY + sampleStep; y < height - marginY - sampleStep; y += sampleStep) {
    for (let x = marginX + sampleStep; x < width - marginX - sampleStep; x += sampleStep) {
      const idx = y * width + x;
      const gx = Math.abs(luma[idx + sampleStep] - luma[idx - sampleStep]);
      const gy = Math.abs(luma[idx + width * sampleStep] - luma[idx - width * sampleStep]);
      const edge = gx + gy;
      if (edge < threshold) continue;
      points.push({ x, y, weight: edge });
      xValues.push(x);
    }
  }

  if (points.length < 18 || xValues.length < 18) return null;

  xValues.sort((a, b) => a - b);
  const xSpread = xValues[xValues.length - 1] - xValues[0];
  if (xSpread < width * 0.32) return null;

  const leftX = clamp(quantileSorted(xValues, 0.03) - width * 0.06, 0, width - 2);
  const rightX = clamp(quantileSorted(xValues, 0.97) + width * 0.06, leftX + 2, width - 1);
  const bins = buildVerticalEdgeBins(points, leftX, rightX, 18);
  if (bins.top.length < 5 || bins.bottom.length < 5) return null;

  const topLine = fitWeightedLine(bins.top);
  const bottomLine = fitWeightedLine(bins.bottom);
  if (!topLine || !bottomLine) return null;

  const aspect = width / Math.max(1, height);
  const verticalMarginRatio = aspect < 2.3 ? 0.08 : 0.14;
  const minBandHeight = height * (aspect < 2.3 ? 0.38 : 0.22);

  let topLeftY = evaluateLine(topLine, leftX);
  let topRightY = evaluateLine(topLine, rightX);
  let bottomLeftY = evaluateLine(bottomLine, leftX);
  let bottomRightY = evaluateLine(bottomLine, rightX);

  const leftBand = bottomLeftY - topLeftY;
  const rightBand = bottomRightY - topRightY;
  if (leftBand < minBandHeight || rightBand < minBandHeight) {
    return null;
  }

  const leftMargin = leftBand * verticalMarginRatio;
  const rightMargin = rightBand * verticalMarginRatio;
  topLeftY = clamp(topLeftY - leftMargin, 0, height - 2);
  bottomLeftY = clamp(bottomLeftY + leftMargin, topLeftY + 2, height - 1);
  topRightY = clamp(topRightY - rightMargin, 0, height - 2);
  bottomRightY = clamp(bottomRightY + rightMargin, topRightY + 2, height - 1);

  const maxSlope = Math.max(
    Math.abs(topRightY - topLeftY) / Math.max(1, rightX - leftX),
    Math.abs(bottomRightY - bottomLeftY) / Math.max(1, rightX - leftX)
  );
  const heightRatio = Math.max(leftBand, rightBand) / Math.max(1, Math.min(leftBand, rightBand));
  if (maxSlope > 0.45 || heightRatio > 2.7) return null;

  return [
    { x: leftX, y: topLeftY },
    { x: rightX, y: topRightY },
    { x: rightX, y: bottomRightY },
    { x: leftX, y: bottomLeftY },
  ];
}

function buildVerticalEdgeBins(
  points: WeightedPoint2D[],
  leftX: number,
  rightX: number,
  binCount: number
): { top: WeightedPoint2D[]; bottom: WeightedPoint2D[] } {
  const buckets: { x: number; ys: number[]; weight: number }[] = Array.from({ length: binCount }, (_, index) => ({
    x: leftX + ((rightX - leftX) * (index + 0.5)) / binCount,
    ys: [],
    weight: 0,
  }));

  for (const point of points) {
    if (point.x < leftX || point.x > rightX) continue;
    const bucketIndex = clamp(
      Math.floor(((point.x - leftX) / Math.max(1, rightX - leftX)) * binCount),
      0,
      binCount - 1
    );
    buckets[bucketIndex].ys.push(point.y);
    buckets[bucketIndex].weight += point.weight;
  }

  const top: WeightedPoint2D[] = [];
  const bottom: WeightedPoint2D[] = [];

  for (const bucket of buckets) {
    if (bucket.ys.length < 2) continue;
    bucket.ys.sort((a, b) => a - b);
    const topY = quantileSorted(bucket.ys, 0.12);
    const bottomY = quantileSorted(bucket.ys, 0.88);
    if (bottomY - topY < 4) continue;
    const weight = Math.max(1, bucket.weight / bucket.ys.length);
    top.push({ x: bucket.x, y: topY, weight });
    bottom.push({ x: bucket.x, y: bottomY, weight });
  }

  return { top, bottom };
}

function fitWeightedLine(points: WeightedPoint2D[]): Line2D | null {
  if (points.length < 2) return null;

  let weightSum = 0;
  let meanX = 0;
  let meanY = 0;

  for (const point of points) {
    weightSum += point.weight;
    meanX += point.x * point.weight;
    meanY += point.y * point.weight;
  }
  if (weightSum <= 0) return null;

  meanX /= weightSum;
  meanY /= weightSum;

  let covXX = 0;
  let covXY = 0;
  for (const point of points) {
    const dx = point.x - meanX;
    covXX += dx * dx * point.weight;
    covXY += dx * (point.y - meanY) * point.weight;
  }

  const slope = Math.abs(covXX) < 1e-6 ? 0 : covXY / covXX;
  return {
    slope,
    intercept: meanY - slope * meanX,
  };
}

function evaluateLine(line: Line2D, x: number): number {
  return line.slope * x + line.intercept;
}

function quantileSorted(values: number[], q: number): number {
  if (values.length === 0) return 0;
  const idx = clamp((values.length - 1) * q, 0, values.length - 1);
  const lower = Math.floor(idx);
  const upper = Math.ceil(idx);
  if (lower === upper) return values[lower];
  const t = idx - lower;
  return values[lower] * (1 - t) + values[upper] * t;
}

function computeHomography(
  source: [Point2D, Point2D, Point2D, Point2D],
  destination: [Point2D, Point2D, Point2D, Point2D]
): number[] | null {
  const matrix: number[][] = [];

  for (let i = 0; i < 4; i++) {
    const src = source[i];
    const dst = destination[i];
    matrix.push([src.x, src.y, 1, 0, 0, 0, -src.x * dst.x, -src.y * dst.x, dst.x]);
    matrix.push([0, 0, 0, src.x, src.y, 1, -src.x * dst.y, -src.y * dst.y, dst.y]);
  }

  const solved = solveLinearSystem(matrix);
  return solved ? [...solved, 1] : null;
}

function solveLinearSystem(matrix: number[][]): number[] | null {
  const n = 8;

  for (let col = 0; col < n; col++) {
    let pivotRow = col;
    for (let row = col + 1; row < n; row++) {
      if (Math.abs(matrix[row][col]) > Math.abs(matrix[pivotRow][col])) {
        pivotRow = row;
      }
    }

    if (Math.abs(matrix[pivotRow][col]) < 1e-8) return null;
    if (pivotRow !== col) {
      const temp = matrix[col];
      matrix[col] = matrix[pivotRow];
      matrix[pivotRow] = temp;
    }

    const pivot = matrix[col][col];
    for (let i = col; i <= n; i++) matrix[col][i] /= pivot;

    for (let row = 0; row < n; row++) {
      if (row === col) continue;
      const factor = matrix[row][col];
      for (let i = col; i <= n; i++) {
        matrix[row][i] -= factor * matrix[col][i];
      }
    }
  }

  return matrix.map((row) => row[n]);
}

function sampleBilinear(
  src: Uint8ClampedArray,
  width: number,
  height: number,
  x: number,
  y: number,
  dst: Uint8ClampedArray,
  dstOffset: number
): void {
  if (x < 0 || y < 0 || x > width - 1 || y > height - 1) {
    dst[dstOffset] = 0;
    dst[dstOffset + 1] = 0;
    dst[dstOffset + 2] = 0;
    dst[dstOffset + 3] = 255;
    return;
  }

  const x0 = Math.floor(x);
  const y0 = Math.floor(y);
  const x1 = Math.min(width - 1, x0 + 1);
  const y1 = Math.min(height - 1, y0 + 1);
  const tx = x - x0;
  const ty = y - y0;
  const idx00 = (y0 * width + x0) * 4;
  const idx10 = (y0 * width + x1) * 4;
  const idx01 = (y1 * width + x0) * 4;
  const idx11 = (y1 * width + x1) * 4;

  for (let channel = 0; channel < 4; channel++) {
    const top = src[idx00 + channel] * (1 - tx) + src[idx10 + channel] * tx;
    const bottom = src[idx01 + channel] * (1 - tx) + src[idx11 + channel] * tx;
    dst[dstOffset + channel] = Math.round(top * (1 - ty) + bottom * ty);
  }
  dst[dstOffset + 3] = 255;
}

export function splitTwoLineCrop(
  sourceCanvas: HTMLCanvasElement
): { top: HTMLCanvasElement; bottom: HTMLCanvasElement } {
  const W = sourceCanvas.width;
  const H = sourceCanvas.height;
  const splitY = estimateTwoLineSplitY(sourceCanvas);
  const overlap = Math.max(2, Math.round(H * 0.06));
  const topSourceH = clamp(splitY + overlap, 1, H);
  const bottomSourceY = clamp(splitY - overlap, 0, H - 1);
  const bottomSourceH = Math.max(1, H - bottomSourceY);

  const top = document.createElement('canvas');
  top.width = W;
  top.height = Math.round(H * 0.55);
  const topCtx = top.getContext('2d', { willReadFrequently: true });
  if (topCtx) {
    topCtx.drawImage(sourceCanvas, 0, 0, W, topSourceH, 0, 0, W, top.height);
  }

  const bottom = document.createElement('canvas');
  bottom.width = W;
  bottom.height = Math.round(H * 0.55);
  const botCtx = bottom.getContext('2d', { willReadFrequently: true });
  if (botCtx) {
    botCtx.drawImage(sourceCanvas, 0, bottomSourceY, W, bottomSourceH, 0, 0, W, bottom.height);
  }

  return { top, bottom };
}

function estimateTwoLineSplitY(sourceCanvas: HTMLCanvasElement): number {
  const W = sourceCanvas.width;
  const H = sourceCanvas.height;
  const fallback = Math.round(H * 0.52);
  if (W < 16 || H < 32) return fallback;

  const ctx = sourceCanvas.getContext('2d', { willReadFrequently: true });
  if (!ctx) return fallback;

  try {
    const image = ctx.getImageData(0, 0, W, H);
    const { data } = image;
    const rowEnergy = new Float32Array(H);

    for (let y = 1; y < H - 1; y++) {
      let energy = 0;
      for (let x = 1; x < W - 1; x++) {
        const idx = (y * W + x) * 4;
        const left = data[idx - 4] * 0.299 + data[idx - 3] * 0.587 + data[idx - 2] * 0.114;
        const right = data[idx + 4] * 0.299 + data[idx + 5] * 0.587 + data[idx + 6] * 0.114;
        const up = data[idx - W * 4] * 0.299 + data[idx - W * 4 + 1] * 0.587 + data[idx - W * 4 + 2] * 0.114;
        const down = data[idx + W * 4] * 0.299 + data[idx + W * 4 + 1] * 0.587 + data[idx + W * 4 + 2] * 0.114;
        energy += Math.abs(right - left) + Math.abs(down - up);
      }
      rowEnergy[y] = energy / Math.max(1, W - 2);
    }

    const minY = Math.round(H * 0.34);
    const maxY = Math.round(H * 0.66);
    let bestY = fallback;
    let bestScore = Number.POSITIVE_INFINITY;

    for (let y = minY; y <= maxY; y++) {
      const localEnergy =
        rowEnergy[y - 2] * 0.2 +
        rowEnergy[y - 1] * 0.4 +
        rowEnergy[y] +
        rowEnergy[y + 1] * 0.4 +
        rowEnergy[y + 2] * 0.2;
      const centrePenalty = Math.abs(y - fallback) / H;
      const score = localEnergy + centrePenalty * 12;
      if (score < bestScore) {
        bestScore = score;
        bestY = y;
      }
    }

    return bestY;
  } catch {
    return fallback;
  }
}

export function calculateCropQualityScore(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number
): number {
  const imgData = ctx.getImageData(0, 0, width, height);
  const data = imgData.data;
  const totalPx = width * height;

  let mean = 0;
  for (let i = 0; i < data.length; i += 4) mean += data[i];
  mean /= totalPx;

  let variance = 0;
  for (let i = 0; i < data.length; i += 4) {
    const d = data[i] - mean;
    variance += d * d;
  }
  variance /= totalPx;

  return Math.min(1.0, Math.sqrt(variance) / 128);
}

export function cropCanvasRegion(
  sourceCanvas: HTMLCanvasElement | HTMLVideoElement,
  bbox: BoundingBox,
  targetWidth: number = 360,
  targetHeight: number = 108
): HTMLCanvasElement {
  const crops = generateAdaptiveCrops(sourceCanvas, bbox, targetWidth, targetHeight);
  return crops.length > 0 ? crops[0].canvas : document.createElement('canvas');
}

export function cropCanvasRegionFast(
  sourceCanvas: HTMLCanvasElement | HTMLVideoElement,
  bbox: BoundingBox,
  targetWidth: number = 360,
  targetHeight: number = 108
): HTMLCanvasElement {
  const cropCanvas = document.createElement('canvas');
  const outputSize = getAdaptiveCropTargetSize(bbox, targetWidth, targetHeight);

  let scaleFactor = 1.0;
  if (bbox.width < 120 || bbox.height < 35) {
    scaleFactor = 1.6;
  }

  const scaledW = Math.round(outputSize.width * scaleFactor);
  const scaledH = Math.round(outputSize.height * scaleFactor);
  cropCanvas.width = scaledW;
  cropCanvas.height = scaledH;

  const ctx = cropCanvas.getContext('2d', { willReadFrequently: true });
  if (!ctx) return cropCanvas;

  const { width: sourceWidth, height: sourceHeight } = getSourceDimensions(sourceCanvas);
  const cropBox = clampCropBox(bbox, sourceWidth, sourceHeight);

  ctx.drawImage(sourceCanvas, cropBox.x, cropBox.y, cropBox.width, cropBox.height, 0, 0, scaledW, scaledH);
  return cropCanvas;
}

export function cropDeskewedCanvasRegionFast(
  sourceCanvas: HTMLCanvasElement | HTMLVideoElement,
  bbox: BoundingBox,
  angleRad: number,
  targetWidth: number = 360,
  targetHeight: number = 108
): HTMLCanvasElement {
  const boundedAngle = Number.isFinite(angleRad) ? clamp(angleRad, -0.60, 0.60) : 0;
  if (Math.abs(boundedAngle) < 0.035) {
    return cropCanvasRegionFast(sourceCanvas, bbox, targetWidth, targetHeight);
  }

  const cropCanvas = document.createElement('canvas');
  const outputSize = getAdaptiveCropTargetSize(bbox, targetWidth, targetHeight);

  let scaleFactor = 1.0;
  if (bbox.width < 120 || bbox.height < 35) {
    scaleFactor = 1.6;
  }

  const scaledW = Math.round(outputSize.width * scaleFactor);
  const scaledH = Math.round(outputSize.height * scaleFactor);
  cropCanvas.width = scaledW;
  cropCanvas.height = scaledH;

  const ctx = cropCanvas.getContext('2d', { willReadFrequently: true });
  if (!ctx) return cropCanvas;

  const { width: sourceWidth, height: sourceHeight } = getSourceDimensions(sourceCanvas);
  const angleAmount = Math.abs(boundedAngle);
  const cropBox = clampCropBox(
    bbox,
    sourceWidth,
    sourceHeight,
    0.12 + Math.min(0.20, angleAmount * 0.42),
    0.18 + Math.min(0.24, angleAmount * 0.52)
  );

  ctx.fillStyle = 'rgb(0, 0, 0)';
  ctx.fillRect(0, 0, scaledW, scaledH);
  ctx.save();
  ctx.translate(scaledW / 2, scaledH / 2);
  ctx.rotate(-boundedAngle);
  ctx.drawImage(sourceCanvas, cropBox.x, cropBox.y, cropBox.width, cropBox.height, -scaledW / 2, -scaledH / 2, scaledW, scaledH);
  ctx.restore();

  return cropCanvas;
}

export function createInnerPlateTextCrop(sourceCanvas: HTMLCanvasElement): HTMLCanvasElement {
  const output = document.createElement('canvas');
  output.width = sourceCanvas.width;
  output.height = sourceCanvas.height;

  const ctx = output.getContext('2d', { willReadFrequently: true });
  if (!ctx || sourceCanvas.width === 0 || sourceCanvas.height === 0) return output;

  const aspect = sourceCanvas.width / Math.max(1, sourceCanvas.height);
  const isTwoLine = aspect < 2.3;
  const marginX = isTwoLine ? 0.04 : 0.06;
  const marginY = isTwoLine ? 0.06 : 0.18;

  const srcX = Math.round(sourceCanvas.width * marginX);
  const srcY = Math.round(sourceCanvas.height * marginY);
  const srcW = Math.max(1, Math.round(sourceCanvas.width * (1 - marginX * 2)));
  const srcH = Math.max(1, Math.round(sourceCanvas.height * (1 - marginY * 2)));

  ctx.drawImage(sourceCanvas, srcX, srcY, srcW, srcH, 0, 0, output.width, output.height);
  return output;
}

export function prioritiseTracks(
  tracks: {
    trackId: string;
    bbox: BoundingBox;
    framesSeen: number;
    ocrState: string;
    lastOcrAttemptAt?: number;
    voteCount?: number;
  }[],
  frameWidth: number,
  frameHeight: number,
  maxOcrSlots: number = 3
): string[] {
  const frameCentreX = frameWidth / 2;
  const frameCentreY = frameHeight / 2;

  const scored = tracks
    .filter(t => t.ocrState !== 'COOLDOWN' && t.ocrState !== 'MATCHED' && !t.ocrState.startsWith('OCR_RUNNING'))
    .map(t => {
      const area = t.bbox.width * t.bbox.height;
      const plateCentreX = t.bbox.x + t.bbox.width / 2;
      const plateCentreY = t.bbox.y + t.bbox.height / 2;
      const distFromCentre = Math.sqrt(
        Math.pow(plateCentreX - frameCentreX, 2) + Math.pow(plateCentreY - frameCentreY, 2)
      );
      const frameArea = frameWidth * frameHeight;
      const distScore = 1 - Math.min(1, distFromCentre / Math.sqrt(frameArea));
      const areaScore = Math.min(1, area / (frameArea * 0.25));
      const stabilityScore = Math.min(1, t.framesSeen / 15);
      const confScore = t.bbox.confidence ?? 0.8;
      const lastAttemptAge = t.lastOcrAttemptAt ? Date.now() - t.lastOcrAttemptAt : 5000;
      const fairnessScore = Math.min(1, lastAttemptAge / 1200);
      const noVoteBoost = (t.voteCount ?? 0) === 0 ? 0.12 : 0;

      const priority =
        areaScore * 0.28 +
        confScore * 0.25 +
        distScore * 0.18 +
        stabilityScore * 0.12 +
        fairnessScore * 0.17 +
        noVoteBoost;
      return { trackId: t.trackId, priority };
    });

  scored.sort((a, b) => b.priority - a.priority);
  return scored.slice(0, maxOcrSlots).map(s => s.trackId);
}
