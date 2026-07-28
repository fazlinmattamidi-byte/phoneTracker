import {
  PLATE_QUALITY_CLASSES,
  PlateQualityClass,
} from './adaptiveConfig';
import {
  canUseWebGpuExecutionProvider,
  configureOrtWasm,
  fetchWithTimeout,
  getOrt,
  withTimeout,
} from './onnxRuntime';
import { assessCropQuality, CropQualityReport } from './qualityAssessor';

export type PlateQualityModelStatus = 'UNINITIALIZED' | 'LOADING' | 'READY' | 'FALLBACK' | 'FAILED';

export interface PlateQualityAssessment {
  label: PlateQualityClass;
  confidence: number;
  source: 'YOLOV8_CLASSIFIER' | 'HEURISTIC';
  shouldSendToOcr: boolean;
  score: number;
  report: CropQualityReport;
  sampledAt: number;
}

export interface PlateQualityModelOptions {
  heuristicReport?: CropQualityReport;
  minReadableWidth?: number;
  minQualityScore?: number;
  acceptedClasses?: PlateQualityClass[];
  marginalClasses?: PlateQualityClass[];
  minimumClassifierConfidence?: number;
}

const QUALITY_MODEL_PATH = '/models/plate-quality-classifier.onnx';
const QUALITY_METADATA_PATH = '/models/plate-quality-classifier.metadata.json';
const MODEL_FETCH_TIMEOUT_MS = 12000;
const MODEL_INIT_TIMEOUT_MS = 12000;
const MODEL_INFERENCE_TIMEOUT_MS = 2000;
const CLASSIFIER_INPUT_SIZE = 224;

let qualitySession: any = null;
let qualityStatus: PlateQualityModelStatus = 'UNINITIALIZED';
let qualityLoadPromise: Promise<boolean> | null = null;
let qualityError: string | null = null;
let reusableCanvas: HTMLCanvasElement | null = null;
let reusableCtx: CanvasRenderingContext2D | null = null;
let reusableTensorData: Float32Array | null = null;
let qualityModelClasses: PlateQualityClass[] = [...PLATE_QUALITY_CLASSES];

export function getPlateQualityModelStatus(): PlateQualityModelStatus {
  return qualityStatus;
}

export function getPlateQualityModelError(): string | null {
  return qualityError;
}

export async function initPlateQualityModel(): Promise<boolean> {
  if (typeof window === 'undefined') return false;
  if (qualitySession && qualityStatus === 'READY') return true;
  if (qualityStatus === 'FALLBACK' || qualityStatus === 'FAILED') return false;
  if (qualityLoadPromise) return qualityLoadPromise;

  qualityStatus = 'LOADING';
  qualityError = null;

  qualityLoadPromise = (async () => {
    try {
      const modelResponse = await fetchWithTimeout(
        QUALITY_MODEL_PATH,
        MODEL_FETCH_TIMEOUT_MS,
        'Plate quality classifier model fetch'
      );

      if (!modelResponse.ok) {
        qualityStatus = 'FALLBACK';
        qualityError =
          modelResponse.status === 404
            ? 'Plate quality classifier ONNX model not found; using crop-quality heuristic fallback.'
            : `HTTP ${modelResponse.status} fetching ${QUALITY_MODEL_PATH}`;
        return false;
      }

      const ort = await getOrt();
      const webGpuAvailable = canUseWebGpuExecutionProvider();
      configureOrtWasm(ort, webGpuAvailable);
      const modelBytes = new Uint8Array(await modelResponse.arrayBuffer());
      const providersToTry = webGpuAvailable ? [['webgpu', 'wasm'], ['wasm']] : [['wasm']];

      for (const providers of providersToTry) {
        try {
          qualitySession = await withTimeout<any>(
            ort.InferenceSession.create(modelBytes, {
              executionProviders: providers,
              graphOptimizationLevel: 'all',
            }),
            MODEL_INIT_TIMEOUT_MS,
            'Plate quality classifier session creation'
          );
          qualityModelClasses = await loadPlateQualityModelClasses();
          qualityStatus = 'READY';
          return true;
        } catch (err: any) {
          qualityError = err?.message || String(err);
        }
      }

      qualityStatus = 'FAILED';
      return false;
    } catch (err: any) {
      qualityStatus = 'FALLBACK';
      qualityError = err?.message || String(err);
      return false;
    }
  })().finally(() => {
    qualityLoadPromise = null;
  });

  return qualityLoadPromise;
}

export async function classifyPlateQuality(
  cropCanvas: HTMLCanvasElement,
  options: PlateQualityModelOptions = {}
): Promise<PlateQualityAssessment> {
  const report = options.heuristicReport ?? assessCropQuality(cropCanvas);
  const modelReady = await initPlateQualityModel();

  if (modelReady && qualitySession) {
    try {
      const modelAssessment = await runPlateQualityClassifier(cropCanvas, report, options);
      if (modelAssessment) return modelAssessment;
    } catch (err: any) {
      qualityStatus = 'FALLBACK';
      qualityError = err?.message || String(err);
    }
  }

  return classifyPlateQualityHeuristic(cropCanvas, report, options);
}

export function classifyPlateQualityHeuristic(
  cropCanvas: HTMLCanvasElement,
  report: CropQualityReport = assessCropQuality(cropCanvas),
  options: PlateQualityModelOptions = {}
): PlateQualityAssessment {
  const minReadableWidth = options.minReadableWidth ?? 48;
  let label: PlateQualityClass = 'READABLE';
  let confidence = 0.70;

  if (cropCanvas.width < minReadableWidth || cropCanvas.height < 18) {
    label = 'TOO_SMALL';
    confidence = 0.92;
  } else if (report.glareScore >= 0.64) {
    label = 'REFLECTION';
    confidence = 0.88;
  } else if (report.motionBlurScore >= 0.62) {
    label = 'MOTION_BLUR';
    confidence = 0.86;
  } else if (report.blurScore < 18 || report.sharpnessScore <= 0.14) {
    label = 'OUT_OF_FOCUS';
    confidence = 0.90;
  } else if (report.contrastScore <= 0.18) {
    label = 'LOW_CONTRAST';
    confidence = 0.82;
  } else if (report.overallScore >= 0.72 && report.recommendation === 'PASS') {
    label = 'GOOD';
    confidence = 0.88;
  } else if (report.overallScore >= 0.50) {
    label = 'READABLE';
    confidence = 0.78;
  } else if (report.overallScore >= 0.34) {
    label = 'SLIGHT_BLUR';
    confidence = 0.72;
  } else if (report.brightnessScore <= 0.18 || report.contrastScore <= 0.12) {
    label = 'LOW_CONTRAST';
    confidence = 0.82;
  } else {
    label = 'DIRTY';
    confidence = 0.68;
  }

  return buildAssessment(label, confidence, 'HEURISTIC', report, options);
}

async function runPlateQualityClassifier(
  cropCanvas: HTMLCanvasElement,
  report: CropQualityReport,
  options: PlateQualityModelOptions
): Promise<PlateQualityAssessment | null> {
  if (!qualitySession) return null;

  const ort = await getOrt();
  const input = prepareClassifierInput(cropCanvas);
  const inputName = qualitySession.inputNames?.[0] || 'images';
  const tensor = new ort.Tensor('float32', input, [1, 3, CLASSIFIER_INPUT_SIZE, CLASSIFIER_INPUT_SIZE]);
  let outputs: Record<string, any> | null = null;

  try {
    outputs = await withTimeout<Record<string, any>>(
      qualitySession.run({ [inputName]: tensor }),
      MODEL_INFERENCE_TIMEOUT_MS,
      'Plate quality classifier inference'
    );
    const outputName = qualitySession.outputNames?.[0] || Object.keys(outputs)[0];
    const probs = toProbabilities(outputs[outputName]?.data || [], qualityModelClasses.length);
    const top = getTopClass(probs, qualityModelClasses);

    return buildAssessment(top.label, top.confidence, 'YOLOV8_CLASSIFIER', report, options);
  } finally {
    tensor.dispose?.();
    if (outputs) {
      Object.values(outputs).forEach((output) => output?.dispose?.());
    }
  }
}

function buildAssessment(
  label: PlateQualityClass,
  confidence: number,
  source: PlateQualityAssessment['source'],
  report: CropQualityReport,
  options: PlateQualityModelOptions
): PlateQualityAssessment {
  const acceptedClasses = options.acceptedClasses ?? ['READABLE', 'GOOD'];
  const marginalClasses = options.marginalClasses ?? ['SLIGHT_BLUR', 'LOW_CONTRAST'];
  const minQualityScore = options.minQualityScore ?? 0.24;
  const minimumClassifierConfidence = options.minimumClassifierConfidence ?? 0.45;
  const accepted = acceptedClasses.includes(label);
  const marginal = marginalClasses.includes(label) && confidence < 0.92;
  const confidentEnough = source === 'HEURISTIC' || confidence >= minimumClassifierConfidence;
  const shouldSendToOcr =
    confidentEnough &&
    report.recommendation !== 'REJECT' &&
    report.overallScore >= minQualityScore &&
    (accepted || marginal);

  return {
    label,
    confidence: roundMetric(confidence),
    source,
    shouldSendToOcr,
    score: report.overallScore,
    report,
    sampledAt: Date.now(),
  };
}

function prepareClassifierInput(canvas: HTMLCanvasElement): Float32Array {
  if (!reusableCanvas) {
    reusableCanvas = document.createElement('canvas');
    reusableCanvas.width = CLASSIFIER_INPUT_SIZE;
    reusableCanvas.height = CLASSIFIER_INPUT_SIZE;
    reusableCtx = reusableCanvas.getContext('2d', { willReadFrequently: true });
  }

  if (!reusableCtx) {
    return new Float32Array(3 * CLASSIFIER_INPUT_SIZE * CLASSIFIER_INPUT_SIZE);
  }

  reusableCtx.drawImage(canvas, 0, 0, CLASSIFIER_INPUT_SIZE, CLASSIFIER_INPUT_SIZE);
  const image = reusableCtx.getImageData(0, 0, CLASSIFIER_INPUT_SIZE, CLASSIFIER_INPUT_SIZE);
  const { data } = image;
  const area = CLASSIFIER_INPUT_SIZE * CLASSIFIER_INPUT_SIZE;

  if (!reusableTensorData || reusableTensorData.length !== area * 3) {
    reusableTensorData = new Float32Array(area * 3);
  }

  for (let i = 0; i < area; i++) {
    reusableTensorData[i] = data[i * 4] / 255;
    reusableTensorData[area + i] = data[i * 4 + 1] / 255;
    reusableTensorData[area * 2 + i] = data[i * 4 + 2] / 255;
  }

  return reusableTensorData;
}

async function loadPlateQualityModelClasses(): Promise<PlateQualityClass[]> {
  try {
    const response = await fetchWithTimeout(
      QUALITY_METADATA_PATH,
      2500,
      'Plate quality classifier metadata fetch',
      { cache: 'no-store' }
    );
    if (!response.ok) return [...PLATE_QUALITY_CLASSES];
    const metadata = await response.json();
    const classes = Array.isArray(metadata?.classes) ? metadata.classes : [];
    const allowed = new Set<string>(PLATE_QUALITY_CLASSES);
    const validClasses = classes.filter((item: unknown): item is PlateQualityClass => (
      typeof item === 'string' && allowed.has(item)
    ));

    return validClasses.length > 0 ? validClasses : [...PLATE_QUALITY_CLASSES];
  } catch {
    return [...PLATE_QUALITY_CLASSES];
  }
}

function toProbabilities(values: ArrayLike<number>, classCount: number): number[] {
  const raw = Array.from(values).slice(0, classCount);
  if (raw.length === 0) return [];
  const alreadyProbabilities =
    raw.every((value) => value >= 0 && value <= 1) &&
    Math.abs(raw.reduce((sum, value) => sum + value, 0) - 1) < 0.25;

  if (alreadyProbabilities) return raw;

  const max = Math.max(...raw);
  const exps = raw.map((value) => Math.exp(value - max));
  const sum = exps.reduce((acc, value) => acc + value, 0) || 1;
  return exps.map((value) => value / sum);
}

function getTopClass<T extends string>(
  probabilities: number[],
  labels: readonly T[]
): { label: T; confidence: number } {
  let bestIndex = 0;
  let bestValue = probabilities[0] ?? 0;

  for (let i = 1; i < Math.min(probabilities.length, labels.length); i++) {
    if (probabilities[i] > bestValue) {
      bestValue = probabilities[i];
      bestIndex = i;
    }
  }

  return {
    label: labels[bestIndex] ?? labels[0],
    confidence: roundMetric(bestValue),
  };
}

function roundMetric(value: number): number {
  return Math.round(Math.min(1, Math.max(0, value)) * 1000) / 1000;
}
