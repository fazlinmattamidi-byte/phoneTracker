/**
 * PlateQ — Primary Malaysian License Plate Detection Engine
 * Model: YOLOv8 Object Detection (Universe Roboflow: fyp-hq4ka/license-plate-malaysia-kqy48)
 * 
 * Production Hardware Execution Policy:
 * Stable Chain: WASM -> WebGPU (WebGL removed from production chain)
 * Zero silent fallbacks to CV heuristic or remote APIs in production.
 */

import { detectPlateCandidatesCV } from './imageProcessor';
import {
  canUseWebGpuExecutionProvider,
  configureOrtWasm,
  fetchWithTimeout,
  getOrt,
  withTimeout,
} from './onnxRuntime';

export interface BoundingBox {
  x: number;      // top-left x in canvas pixels
  y: number;      // top-left y in canvas pixels
  width: number;  // width in canvas pixels
  height: number; // height in canvas pixels
}

export type DetectorFrameOrientation = 'UPRIGHT' | 'ROTATED_180' | 'ROTATED_90_CW' | 'ROTATED_90_CCW';

export interface DetectedPlateBox {
  bbox: BoundingBox;
  confidence: number;
  label: string;
  sourceEngine: 'LOCAL_ONNX' | 'CV_HEURISTIC';
  frameOrientation?: DetectorFrameOrientation;
}

export interface DetectionOptions {
  minConfidence?: number;
  iouThreshold?: number;
  enginePreference?: 'AUTO' | 'LOCAL_ONNX' | 'CV_HEURISTIC';
  developerMode?: boolean;
  orientationFallback?: boolean;
}

export type DetectorStatus = 'UNINITIALIZED' | 'LOADING' | 'READY' | 'FAILED';
export type ActiveExecutionProvider = 'WebGPU' | 'WASM' | 'NONE';

let localOnnxSession: any = null;
let detectorStatus: DetectorStatus = 'UNINITIALIZED';
let activeProvider: ActiveExecutionProvider = 'NONE';
let isOnnxLoading = false;
let onnxLoadPromise: Promise<boolean> | null = null;
let onnxLoadFailures = 0;
const MAX_ONNX_FAILURES = 3;
const MODEL_FETCH_TIMEOUT_MS = 20000;
const PROVIDER_INIT_TIMEOUT_MS = 15000;
const PROVIDER_WARMUP_TIMEOUT_MS = 8000;

// Inference singletons for zero GC overhead. ONNX Runtime Web sessions and the
// reusable tensor buffers are shared, so detector inference must run serially.
let detectorQueue: Promise<void> = Promise.resolve();
let reusableCanvas: HTMLCanvasElement | null = null;
let reusableCtx: CanvasRenderingContext2D | null = null;
let reusableFloat32Data: Float32Array | null = null;
const ORIENTATION_FALLBACKS: DetectorFrameOrientation[] = ['ROTATED_180', 'ROTATED_90_CW', 'ROTATED_90_CCW'];
const ORIENTATION_FALLBACK_CONFIDENCE_SCALE = 0.98;

let lastDetectorError: string | null = null;

export function getDetectorError(): string | null {
  return lastDetectorError;
}

export function getDetectorStatus(): DetectorStatus {
  return detectorStatus;
}

export function getActiveDetectorProvider(): ActiveExecutionProvider {
  return activeProvider;
}

function getErrorMessage(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

function releaseOnnxSession(session: any): void {
  try {
    session?.release?.();
  } catch {
    // Best-effort cleanup for ONNX Runtime Web sessions.
  }
  try {
    session?.dispose?.();
  } catch {
    // Older runtime builds expose release(), newer/other builds may expose dispose().
  }
}

function markDetectorRuntimeFailure(err: unknown, context: string): void {
  lastDetectorError = `${context}: ${getErrorMessage(err)}`;
  detectorStatus = 'FAILED';
  activeProvider = 'NONE';
  onnxLoadFailures = MAX_ONNX_FAILURES;
  const failedSession = localOnnxSession;
  localOnnxSession = null;
  releaseOnnxSession(failedSession);
  console.debug(`[ANPR YoloDetector] ${lastDetectorError}`);
}

/**
 * Initialize Local ONNX Session with stable chain: WASM -> WebGPU
 */
export async function initLocalOnnxSession(): Promise<boolean> {
  if (typeof window === 'undefined') return false;
  if (localOnnxSession && detectorStatus === 'READY') return true;
  if (onnxLoadFailures >= MAX_ONNX_FAILURES) {
    detectorStatus = 'FAILED';
    return false;
  }
  if (isOnnxLoading && onnxLoadPromise) return onnxLoadPromise;

  isOnnxLoading = true;
  detectorStatus = 'LOADING';
  lastDetectorError = null;

  onnxLoadPromise = (async () => {
    try {
      const ort = await getOrt();
      const webGpuAvailable = canUseWebGpuExecutionProvider();

      // Configure WASM paths to match the locally served runtime assets.
      configureOrtWasm(ort, webGpuAvailable);

      // Fetch model into Uint8Array to bypass browser URL fetch restrictions on iOS Safari
      const modelRes = await fetchWithTimeout(
        '/models/plate-detector.onnx',
        MODEL_FETCH_TIMEOUT_MS,
        'YOLOv8 detector model fetch'
      );
      if (!modelRes.ok) {
        throw new Error(`HTTP ${modelRes.status} ${modelRes.statusText} fetching /models/plate-detector.onnx`);
      }
      const modelBuffer = await modelRes.arrayBuffer();
      const modelBytes = new Uint8Array(modelBuffer);

      const providersToTry: { name: ActiveExecutionProvider; epList: string[] }[] = [
        { name: 'WASM', epList: ['wasm'] },
        ...(webGpuAvailable ? [{ name: 'WebGPU' as const, epList: ['webgpu', 'wasm'] }] : []),
      ];
      let lastErrDetail = '';

      for (const item of providersToTry) {
        try {
          configureOrtWasm(ort, item.name === 'WebGPU');
          const session = await withTimeout<any>(
            ort.InferenceSession.create(modelBytes, {
              executionProviders: item.epList,
              graphOptimizationLevel: 'all',
            }),
            PROVIDER_INIT_TIMEOUT_MS,
            `YOLOv8 detector ${item.name} session creation`
          );

          // Dummy inference to validate session functionality
          const targetSize = 640;
          const dummyInput = new ort.Tensor('float32', new Float32Array(3 * targetSize * targetSize), [1, 3, targetSize, targetSize]);
          const inputName = session.inputNames[0] || 'images';
          const dummyResults = await withTimeout<Record<string, any>>(
            session.run({ [inputName]: dummyInput }),
            PROVIDER_WARMUP_TIMEOUT_MS,
            `YOLOv8 detector ${item.name} warm-up`
          );

          // Clean up dummy tensor output
          dummyInput.dispose?.();
          for (const t of Object.values(dummyResults)) {
            (t as any)?.dispose?.();
          }

          localOnnxSession = session;
          activeProvider = item.name;
          detectorStatus = 'READY';
          onnxLoadFailures = 0;
          console.log(`[ANPR YoloDetector] Model initialized successfully with provider: ${item.name}`);
          return true;
        } catch (err: any) {
          lastErrDetail = err?.message || String(err);
          console.debug(`[ANPR YoloDetector] Provider ${item.name} failed initialization:`, lastErrDetail);
        }
      }

      throw new Error(`All execution providers failed to run model.${lastErrDetail ? ` Last error: ${lastErrDetail}` : ''}`);
    } catch (err: any) {
      onnxLoadFailures++;
      detectorStatus = 'FAILED';
      activeProvider = 'NONE';
      lastDetectorError = err?.message || String(err);
      console.debug(`[ANPR YoloDetector] Local ONNX load failed (attempt ${onnxLoadFailures}/${MAX_ONNX_FAILURES}):`, lastDetectorError);
      return false;
    }
  })().finally(() => {
    isOnnxLoading = false;
    onnxLoadPromise = null;
  });

  return onnxLoadPromise;
}

export async function validateDetector(): Promise<{ valid: boolean; provider?: ActiveExecutionProvider }> {
  if (!localOnnxSession || detectorStatus !== 'READY') return { valid: false };
  try {
    if (!localOnnxSession.inputNames || !localOnnxSession.outputNames) return { valid: false };
    return { valid: true, provider: activeProvider };
  } catch {
    return { valid: false };
  }
}

/**
 * Detect all visible Malaysian vehicle number plates across the camera frame.
 */
export async function detectMalaysianPlates(
  canvas: HTMLCanvasElement,
  options: DetectionOptions = {}
): Promise<DetectedPlateBox[]> {
  const minConf = options.minConfidence ?? 0.35;
  const pref = options.enginePreference || 'AUTO';
  const iouThreshold = options.iouThreshold ?? 0.35;

  // 1. Primary Production Engine: Local ONNX Model ONLY
  if (pref === 'LOCAL_ONNX' || pref === 'AUTO') {
    if (!localOnnxSession && detectorStatus !== 'FAILED') {
      await initLocalOnnxSession();
    }
    if (localOnnxSession && detectorStatus === 'READY') {
      try {
        return await runLocalOnnxDetection(canvas, minConf, iouThreshold, options.orientationFallback === true);
      } catch (err) {
        markDetectorRuntimeFailure(err, 'Local ONNX inference failed');
      }
    }
    // Return empty while ONNX model is initializing or if failed — ZERO silent fallbacks in production
    return [];
  }

  // 2. Developer Mode Engine: CV Heuristic (Gated strictly by developerMode)
  if (pref === 'CV_HEURISTIC') {
    if (options.developerMode !== true) {
      console.warn('[ANPR YoloDetector] CV Heuristic detector requested without developerMode.');
      return [];
    }
    const cvCandidates = detectPlateCandidatesCV(canvas, minConf);
    const mapped = cvCandidates.map((c) => ({
      bbox: {
        x: c.crop.x,
        y: c.crop.y,
        width: c.crop.width,
        height: c.crop.height,
      },
      confidence: c.confidence,
      label: 'License-Plate',
      sourceEngine: 'CV_HEURISTIC' as const,
    }));
    return applyFiltersAndNMS(mapped, iouThreshold, canvas.width, canvas.height);
  }

  return [];
}

/**
 * Benchmark detection helper for WASM admission control
 */
export async function runBenchmarkDetection(): Promise<boolean> {
  if (!localOnnxSession) return false;
  try {
    const ort = await getOrt();
    const targetSize = 640;
    const dummyInput = new ort.Tensor('float32', new Float32Array(3 * targetSize * targetSize), [1, 3, targetSize, targetSize]);
    const inputName = localOnnxSession.inputNames[0] || 'images';
    const dummyResults = await localOnnxSession.run({ [inputName]: dummyInput });

    dummyInput.dispose?.();
    for (const t of Object.values(dummyResults)) {
      (t as any)?.dispose?.();
    }
    return true;
  } catch (err) {
    markDetectorRuntimeFailure(err, 'YOLOv8 detector benchmark failed');
    return false;
  }
}

function clampNumber(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function releaseTransientCanvas(canvas: HTMLCanvasElement): void {
  canvas.width = 0;
  canvas.height = 0;
}

function createOrientationFallbackCanvas(
  sourceCanvas: HTMLCanvasElement,
  orientation: DetectorFrameOrientation
): HTMLCanvasElement | null {
  if (orientation === 'UPRIGHT' || sourceCanvas.width <= 0 || sourceCanvas.height <= 0) return null;

  const output = document.createElement('canvas');
  const swapsAxes = orientation === 'ROTATED_90_CW' || orientation === 'ROTATED_90_CCW';
  output.width = swapsAxes ? sourceCanvas.height : sourceCanvas.width;
  output.height = swapsAxes ? sourceCanvas.width : sourceCanvas.height;

  const ctx = output.getContext('2d', { willReadFrequently: true });
  if (!ctx) return output;

  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = 'high';
  ctx.save();
  if (orientation === 'ROTATED_180') {
    ctx.translate(output.width, output.height);
    ctx.rotate(Math.PI);
  } else if (orientation === 'ROTATED_90_CW') {
    ctx.translate(output.width, 0);
    ctx.rotate(Math.PI / 2);
  } else if (orientation === 'ROTATED_90_CCW') {
    ctx.translate(0, output.height);
    ctx.rotate(-Math.PI / 2);
  }
  ctx.drawImage(sourceCanvas, 0, 0);
  ctx.restore();

  return output;
}

function mapFallbackBoxToSource(
  bbox: BoundingBox,
  orientation: DetectorFrameOrientation,
  sourceWidth: number,
  sourceHeight: number
): BoundingBox {
  let mapped: BoundingBox;

  if (orientation === 'ROTATED_180') {
    mapped = {
      x: sourceWidth - (bbox.x + bbox.width),
      y: sourceHeight - (bbox.y + bbox.height),
      width: bbox.width,
      height: bbox.height,
    };
  } else if (orientation === 'ROTATED_90_CW') {
    mapped = {
      x: bbox.y,
      y: sourceHeight - (bbox.x + bbox.width),
      width: bbox.height,
      height: bbox.width,
    };
  } else if (orientation === 'ROTATED_90_CCW') {
    mapped = {
      x: sourceWidth - (bbox.y + bbox.height),
      y: bbox.x,
      width: bbox.height,
      height: bbox.width,
    };
  } else {
    mapped = bbox;
  }

  const left = clampNumber(Math.round(mapped.x), 0, Math.max(0, sourceWidth - 1));
  const top = clampNumber(Math.round(mapped.y), 0, Math.max(0, sourceHeight - 1));
  const right = clampNumber(Math.round(mapped.x + mapped.width), left + 1, sourceWidth);
  const bottom = clampNumber(Math.round(mapped.y + mapped.height), top + 1, sourceHeight);

  return {
    x: left,
    y: top,
    width: Math.max(1, right - left),
    height: Math.max(1, bottom - top),
  };
}

function isUsableMappedFallbackBox(box: DetectedPlateBox, canvasWidth: number, canvasHeight: number): boolean {
  const longEdge = Math.max(box.bbox.width, box.bbox.height);
  const shortEdge = Math.min(box.bbox.width, box.bbox.height);
  const minLongEdge = Math.max(28, Math.max(canvasWidth, canvasHeight) * 0.018);
  const minShortEdge = Math.max(8, Math.min(canvasWidth, canvasHeight) * 0.007);
  if (longEdge < minLongEdge || shortEdge < minShortEdge) return false;

  const normalizedAspect = longEdge / Math.max(1, shortEdge);
  return normalizedAspect >= 1.0 && normalizedAspect <= 7.2;
}

/**
 * Run Local ONNX Inference with Letterboxing Preprocessing & Inverse Transform
 */
async function runLocalOnnxDetection(
  canvas: HTMLCanvasElement,
  minConfidence: number,
  iouThreshold: number,
  orientationFallback: boolean
): Promise<DetectedPlateBox[]> {
  if (!localOnnxSession || typeof window === 'undefined') return [];

  const queuedInference = detectorQueue.then(() =>
    runLocalOnnxDetectionExclusive(canvas, minConfidence, iouThreshold, orientationFallback)
  );
  detectorQueue = queuedInference.then(
    () => undefined,
    () => undefined
  );
  return queuedInference;
}

async function runLocalOnnxDetectionExclusive(
  canvas: HTMLCanvasElement,
  minConfidence: number,
  iouThreshold: number,
  orientationFallback: boolean
): Promise<DetectedPlateBox[]> {
  const primaryDetections = await runLocalOnnxDetectionPass(canvas, minConfidence, iouThreshold);
  if (primaryDetections.length > 0) {
    return primaryDetections.map((box) => ({ ...box, frameOrientation: 'UPRIGHT' }));
  }
  if (!orientationFallback) return [];

  const fallbackDetections: DetectedPlateBox[] = [];
  const fallbackMinConfidence = Math.max(0.22, minConfidence * 0.92);

  for (const orientation of ORIENTATION_FALLBACKS) {
    const fallbackCanvas = createOrientationFallbackCanvas(canvas, orientation);
    if (!fallbackCanvas) continue;

    try {
      const detections = await runLocalOnnxDetectionPass(fallbackCanvas, fallbackMinConfidence, iouThreshold);
      fallbackDetections.push(
        ...detections
          .map((box) => ({
            ...box,
            bbox: mapFallbackBoxToSource(box.bbox, orientation, canvas.width, canvas.height),
            confidence: Math.round(box.confidence * ORIENTATION_FALLBACK_CONFIDENCE_SCALE * 1000) / 1000,
            frameOrientation: orientation,
          }))
          .filter((box) => isUsableMappedFallbackBox(box, canvas.width, canvas.height))
      );
    } finally {
      releaseTransientCanvas(fallbackCanvas);
    }

    if (fallbackDetections.some((box) => box.confidence >= Math.max(0.52, minConfidence))) {
      break;
    }
  }

  if (fallbackDetections.length === 0) return [];
  return applyNMS(fallbackDetections, Math.min(iouThreshold, 0.35), canvas.width, canvas.height).slice(0, 12);
}

async function runLocalOnnxDetectionPass(
  canvas: HTMLCanvasElement,
  minConfidence: number,
  iouThreshold: number
): Promise<DetectedPlateBox[]> {
  const targetSize = 640;

  // Reuse canvas & 2D context to avoid GC overhead
  if (!reusableCanvas) {
    reusableCanvas = document.createElement('canvas');
    reusableCanvas.width = targetSize;
    reusableCanvas.height = targetSize;
    reusableCtx = reusableCanvas.getContext('2d', { willReadFrequently: true });
  }

  if (!reusableCtx) {
    return [];
  }

  // 1. Aspect-Ratio Preserving Letterboxing Preprocessing
  const scale = Math.min(targetSize / canvas.width, targetSize / canvas.height);
  const drawW = Math.round(canvas.width * scale);
  const drawH = Math.round(canvas.height * scale);
  const padX = Math.round((targetSize - drawW) / 2);
  const padY = Math.round((targetSize - drawH) / 2);

  // Fill canvas neutral gray background
  reusableCtx.fillStyle = '#7f7f7f';
  reusableCtx.fillRect(0, 0, targetSize, targetSize);
  // Draw scaled image centered inside 640x640 letterbox
  reusableCtx.drawImage(canvas, 0, 0, canvas.width, canvas.height, padX, padY, drawW, drawH);

  const imgData = reusableCtx.getImageData(0, 0, targetSize, targetSize);
  const { data } = imgData;

  const channelArea = targetSize * targetSize;
  if (!reusableFloat32Data || reusableFloat32Data.length !== 3 * channelArea) {
    reusableFloat32Data = new Float32Array(3 * channelArea);
  }

  for (let i = 0; i < channelArea; i++) {
    reusableFloat32Data[i] = data[i * 4] / 255.0;
    reusableFloat32Data[channelArea + i] = data[i * 4 + 1] / 255.0;
    reusableFloat32Data[2 * channelArea + i] = data[i * 4 + 2] / 255.0;
  }

  let inputTensor: any = null;
  let results: any = null;

  try {
    const ort = await getOrt();
    inputTensor = new ort.Tensor('float32', reusableFloat32Data, [1, 3, targetSize, targetSize]);
    const inputName = localOnnxSession.inputNames[0] || 'images';

    results = await localOnnxSession.run({ [inputName]: inputTensor });

    const outputName = localOnnxSession.outputNames[0] || 'output0';
    const outputTensor = results[outputName];
    if (!outputTensor) return [];

    const dims = outputTensor.dims;
    const rawData = outputTensor.data as Float32Array;

    let numAnchors = 8400;
    let numChannels = 5;
    let isTransposed = false;

    if (dims.length >= 2) {
      const d1 = dims[dims.length - 2];
      const d2 = dims[dims.length - 1];
      if (d1 > d2) {
        numAnchors = d1;
        numChannels = d2;
        isTransposed = true; // e.g. [1, 8400, 5]
      } else {
        numChannels = d1;
        numAnchors = d2;
        isTransposed = false; // e.g. [1, 5, 8400]
      }
    }

    const hasObjectness = (numChannels === 6 || numChannels === 85);
    const detections: DetectedPlateBox[] = [];

    // Relative Minimum Detection Sizes
    const minBoxW = Math.max(32, canvas.width * 0.022);
    const minBoxH = Math.max(9, canvas.height * 0.008);

    for (let i = 0; i < numAnchors; i++) {
      let cx: number, cy: number, w: number, h: number, objConf: number, classConf: number;

      if (isTransposed) {
        cx = rawData[i * numChannels + 0];
        cy = rawData[i * numChannels + 1];
        w = rawData[i * numChannels + 2];
        h = rawData[i * numChannels + 3];
        if (hasObjectness) {
          objConf = rawData[i * numChannels + 4];
          classConf = rawData[i * numChannels + 5];
        } else {
          objConf = 1.0;
          classConf = rawData[i * numChannels + 4];
        }
      } else {
        cx = rawData[0 * numAnchors + i];
        cy = rawData[1 * numAnchors + i];
        w = rawData[2 * numAnchors + i];
        h = rawData[3 * numAnchors + i];
        if (hasObjectness) {
          objConf = rawData[4 * numAnchors + i];
          classConf = rawData[5 * numAnchors + i];
        } else {
          objConf = 1.0;
          classConf = rawData[4 * numAnchors + i];
        }
      }

      const conf = objConf * classConf;

      // Validate finite numbers
      if (!Number.isFinite(cx) || !Number.isFinite(cy) || !Number.isFinite(w) || !Number.isFinite(h) || !Number.isFinite(conf)) {
        continue;
      }

      if (conf >= minConfidence) {
        // Reverse Letterbox Coordinate Mapping:
        // (cx, cy, w, h) are in 0..640 letterbox space.
        // Subtract letterbox padding, then divide by scale factor to map back to original canvas pixels.
        const realCx = (cx - padX) / scale;
        const realCy = (cy - padY) / scale;
        const realW = w / scale;
        const realH = h / scale;

        // Strict boundary clipping
        const left = Math.max(0, Math.min(canvas.width, realCx - realW / 2));
        const top = Math.max(0, Math.min(canvas.height, realCy - realH / 2));
        const right = Math.max(0, Math.min(canvas.width, realCx + realW / 2));
        const bottom = Math.max(0, Math.min(canvas.height, realCy + realH / 2));

        const finalW = Math.round(right - left);
        const finalH = Math.round(bottom - top);

        if (finalW >= minBoxW && finalH >= minBoxH) {
          detections.push({
            bbox: {
              x: Math.round(left),
              y: Math.round(top),
              width: finalW,
              height: finalH,
            },
            confidence: Math.round(conf * 1000) / 1000,
            label: 'License-Plate',
            sourceEngine: 'LOCAL_ONNX',
          });
        }
      }
    }

    return applyFiltersAndNMS(detections, iouThreshold, canvas.width, canvas.height);
  } finally {
    // Memory Disposal Guarantee for CPU/GPU memory
    inputTensor?.dispose?.();
    if (results) {
      for (const tensor of Object.values(results)) {
        (tensor as any)?.dispose?.();
      }
    }
  }
}

function applyFiltersAndNMS(
  boxes: DetectedPlateBox[],
  iouThreshold: number,
  canvasWidth: number,
  canvasHeight: number
): DetectedPlateBox[] {
  const minW = Math.max(28, canvasWidth * 0.018);
  const minH = Math.max(8, canvasHeight * 0.007);

  const filtered = boxes.filter(box => {
    const { width, height } = box.bbox;
    if (width < minW || height < minH) return false;
    
    const ar = width / height;
    // Malaysian plates include square/two-line rear and motorcycle plates,
    // long JPJePlate/commercial plates, plus framed/recessed crops.
    if (ar < 0.65 || ar > 7.2) return false;
    
    return true;
  });

  // Lower NMS threshold (e.g. 0.35) = MORE aggressive suppression of overlapping boxes
  const effectiveThreshold = Math.min(iouThreshold, 0.35);
  return applyNMS(filtered, effectiveThreshold, canvasWidth, canvasHeight).slice(0, 12);
}

function getBoxArea(box: DetectedPlateBox): number {
  return box.bbox.width * box.bbox.height;
}

function getBoxRank(box: DetectedPlateBox, frameArea: number): number {
  const areaScore = Math.min(1, getBoxArea(box) / Math.max(1, frameArea * 0.08));
  return box.confidence * 0.68 + areaScore * 0.32;
}

function isMostlyContained(inner: BoundingBox, outer: BoundingBox): boolean {
  const cx = inner.x + inner.width / 2;
  const cy = inner.y + inner.height / 2;
  const centreInside =
    cx >= outer.x &&
    cx <= outer.x + outer.width &&
    cy >= outer.y &&
    cy <= outer.y + outer.height;

  return centreInside && inner.width * inner.height < outer.width * outer.height * 0.65;
}

function applyNMS(
  boxes: DetectedPlateBox[],
  iouThreshold: number,
  canvasWidth: number,
  canvasHeight: number
): DetectedPlateBox[] {
  const frameArea = canvasWidth * canvasHeight;
  const sorted = [...boxes].sort((a, b) => getBoxRank(b, frameArea) - getBoxRank(a, frameArea));
  const selected: DetectedPlateBox[] = [];

  for (const box of sorted) {
    let keep = true;
    for (const sel of selected) {
      if (
        calculateIoU(box.bbox, sel.bbox) > iouThreshold ||
        isMostlyContained(box.bbox, sel.bbox)
      ) {
        keep = false;
        break;
      }
    }
    if (keep) {
      selected.push(box);
    }
  }

  return selected;
}

export function calculateIoU(boxA: BoundingBox, boxB: BoundingBox): number {
  const xA = Math.max(boxA.x, boxB.x);
  const yA = Math.max(boxA.y, boxB.y);
  const xB = Math.min(boxA.x + boxA.width, boxB.x + boxB.width);
  const yB = Math.min(boxA.y + boxA.height, boxB.y + boxB.height);

  const interWidth = Math.max(0, xB - xA);
  const interHeight = Math.max(0, yB - yA);
  const interArea = interWidth * interHeight;

  if (interArea === 0) return 0;

  const areaA = boxA.width * boxA.height;
  const areaB = boxB.width * boxB.height;
  return interArea / (areaA + areaB - interArea);
}
