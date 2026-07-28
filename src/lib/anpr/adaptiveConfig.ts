import type { PreprocessVariant } from './imageProcessor';

export const ENVIRONMENT_CLASSES = [
  'BACKLIGHT',
  'DAY',
  'FOG',
  'GLARE',
  'GOOD_CONDITION',
  'HEAVY_RAIN',
  'HIGHWAY',
  'LOW_LIGHT',
  'NIGHT',
  'PARKING',
  'RAIN',
  'TRAFFIC',
  'TUNNEL',
] as const;

export type EnvironmentClass = (typeof ENVIRONMENT_CLASSES)[number];

export const PLATE_QUALITY_CLASSES = [
  'READABLE',
  'GOOD',
  'SLIGHT_BLUR',
  'MOTION_BLUR',
  'OUT_OF_FOCUS',
  'TOO_SMALL',
  'LOW_CONTRAST',
  'DIRTY',
  'OCCLUDED',
  'REFLECTION',
] as const;

export type PlateQualityClass = (typeof PLATE_QUALITY_CLASSES)[number];

export type Distribution<T extends string> = Record<T, number>;

export interface EnvironmentProfile {
  label: EnvironmentClass;
  confidence: number;
  source: 'YOLOV8_CLASSIFIER' | 'HEURISTIC';
  sampledAt: number;
  stats?: {
    brightness: number;
    contrast: number;
    glareRatio: number;
    blurScore: number;
    motionScore: number;
    dirtyLensScore: number;
  };
}

export interface AdaptiveScannerConfig {
  environment: EnvironmentProfile;
  detector: {
    targetIntervalMs: number;
    busyIntervalMs: number;
    minDelayMs: number;
    minConfidence: number;
  };
  camera: {
    idealWidth: number;
    idealHeight: number;
    idealFps: number;
    fallbackWidth: number;
    fallbackHeight: number;
  };
  processing: {
    maxLongEdge: number;
    preprocessingVariants: PreprocessVariant[];
    perspectiveRectification: boolean;
  };
  buffer: {
    maxSize: number;
    maxEntryAgeMs: number;
    cropSampleIntervalMultiplier: number;
  };
  ocr: {
    minQuality: number;
    firstReadMinQuality: number;
    repeatReadMinQuality: number;
    minTrackConfidence: number;
    firstReadMinTrackConfidence: number;
    recognitionThreshold: number;
    consensusVotes: number;
    maxConcurrency: number;
    firstReadRetryMs: number;
    repeatReadRetryMs: number;
    requiredBufferedCrops: number;
    maxBestCropAgeMs: number;
    maxCandidateCrops: number;
    useInnerTextCrop: boolean;
  };
  qualityGate: {
    acceptedClasses: PlateQualityClass[];
    marginalClasses: PlateQualityClass[];
    minimumClassifierConfidence: number;
  };
  track: {
    lifetimeMultiplier: number;
    prioritizeHighestConfidence: boolean;
  };
  datasetFolder: string;
}

export function createEmptyDistribution<T extends string>(classes: readonly T[]): Distribution<T> {
  return classes.reduce((acc, item) => {
    acc[item] = 0;
    return acc;
  }, {} as Distribution<T>);
}

export function incrementDistribution<T extends string>(
  distribution: Distribution<T>,
  label: T,
  amount = 1
): Distribution<T> {
  return {
    ...distribution,
    [label]: (distribution[label] ?? 0) + amount,
  };
}

export function getDistributionPercentages<T extends string>(
  distribution: Distribution<T>
): Record<T, number> {
  const total = (Object.values(distribution) as number[]).reduce((sum, value) => sum + Number(value), 0);
  const result = {} as Record<T, number>;

  (Object.keys(distribution) as T[]).forEach((key) => {
    result[key] = total > 0 ? Math.round(((distribution[key] || 0) / total) * 1000) / 10 : 0;
  });

  return result;
}

export function createDefaultEnvironmentProfile(): EnvironmentProfile {
  return {
    label: 'GOOD_CONDITION',
    confidence: 0,
    source: 'HEURISTIC',
    sampledAt: Date.now(),
  };
}

export function createAdaptiveScannerConfig(
  environment: EnvironmentProfile = createDefaultEnvironmentProfile()
): AdaptiveScannerConfig {
  const base: AdaptiveScannerConfig = {
    environment,
    detector: {
      targetIntervalMs: 100,
      busyIntervalMs: 145,
      minDelayMs: 16,
      minConfidence: 0.35,
    },
    camera: {
      idealWidth: 1920,
      idealHeight: 1080,
      idealFps: 30,
      fallbackWidth: 1280,
      fallbackHeight: 720,
    },
    processing: {
      maxLongEdge: 1280,
      preprocessingVariants: ['ORIGINAL', 'DARK_BG', 'INVERTED'],
      perspectiveRectification: true,
    },
    buffer: {
      maxSize: 6,
      maxEntryAgeMs: 5000,
      cropSampleIntervalMultiplier: 1,
    },
    ocr: {
      minQuality: 0.24,
      firstReadMinQuality: 0.26,
      repeatReadMinQuality: 0.22,
      minTrackConfidence: 0.70,
      firstReadMinTrackConfidence: 0.62,
      recognitionThreshold: 0.60,
      consensusVotes: 3,
      maxConcurrency: 3,
      firstReadRetryMs: 90,
      repeatReadRetryMs: 180,
      requiredBufferedCrops: 1,
      maxBestCropAgeMs: 1800,
      maxCandidateCrops: 5,
      useInnerTextCrop: true,
    },
    qualityGate: {
      acceptedClasses: ['READABLE', 'GOOD'],
      marginalClasses: ['SLIGHT_BLUR', 'LOW_CONTRAST'],
      minimumClassifierConfidence: 0.45,
    },
    track: {
      lifetimeMultiplier: 1,
      prioritizeHighestConfidence: false,
    },
    datasetFolder: `dataset/${environment.label.toLowerCase()}`,
  };

  switch (environment.label) {
    case 'DAY':
    case 'GOOD_CONDITION':
      return base;

    case 'NIGHT':
    case 'LOW_LIGHT':
    case 'TUNNEL':
      return mergeAdaptiveConfig(base, {
        detector: {
          targetIntervalMs: 115,
          busyIntervalMs: 180,
          minConfidence: 0.32,
        },
        processing: {
          preprocessingVariants: ['ORIGINAL', 'CLAHE', 'SHARPEN', 'DARK_BG', 'INVERTED'],
        },
        buffer: {
          maxSize: 9,
          maxEntryAgeMs: 7500,
          cropSampleIntervalMultiplier: 0.85,
        },
        ocr: {
          firstReadMinQuality: 0.22,
          repeatReadMinQuality: 0.20,
          minTrackConfidence: 0.68,
          firstReadMinTrackConfidence: 0.58,
          recognitionThreshold: 0.66,
          consensusVotes: 4,
          requiredBufferedCrops: 2,
          maxBestCropAgeMs: 2800,
          maxCandidateCrops: 6,
        },
      });

    case 'RAIN':
    case 'HEAVY_RAIN':
      return mergeAdaptiveConfig(base, {
        detector: {
          targetIntervalMs: environment.label === 'HEAVY_RAIN' ? 135 : 115,
          busyIntervalMs: environment.label === 'HEAVY_RAIN' ? 230 : 185,
          minConfidence: 0.40,
        },
        processing: {
          preprocessingVariants: ['ORIGINAL', 'SHARPEN', 'NOISE_REDUCED', 'CLAHE'],
        },
        buffer: {
          maxSize: 10,
          maxEntryAgeMs: 8000,
          cropSampleIntervalMultiplier: 0.9,
        },
        ocr: {
          minQuality: 0.34,
          firstReadMinQuality: 0.36,
          repeatReadMinQuality: 0.32,
          minTrackConfidence: 0.74,
          firstReadMinTrackConfidence: 0.66,
          recognitionThreshold: 0.68,
          consensusVotes: 4,
          requiredBufferedCrops: 2,
          maxBestCropAgeMs: 3000,
        },
        qualityGate: {
          marginalClasses: ['SLIGHT_BLUR'],
          minimumClassifierConfidence: 0.50,
        },
        track: {
          lifetimeMultiplier: environment.label === 'HEAVY_RAIN' ? 1.8 : 1.45,
        },
      });

    case 'FOG':
      return mergeAdaptiveConfig(base, {
        detector: {
          targetIntervalMs: 130,
          busyIntervalMs: 220,
          minConfidence: 0.38,
        },
        processing: {
          preprocessingVariants: ['ORIGINAL', 'CLAHE', 'SHARPEN', 'NOISE_REDUCED'],
        },
        buffer: {
          maxSize: 9,
          maxEntryAgeMs: 8500,
        },
        ocr: {
          minQuality: 0.36,
          firstReadMinQuality: 0.38,
          repeatReadMinQuality: 0.34,
          recognitionThreshold: 0.70,
          consensusVotes: 4,
          requiredBufferedCrops: 2,
          maxCandidateCrops: 6,
        },
        qualityGate: {
          acceptedClasses: ['GOOD', 'READABLE'],
          marginalClasses: [],
          minimumClassifierConfidence: 0.52,
        },
      });

    case 'GLARE':
    case 'BACKLIGHT':
      return mergeAdaptiveConfig(base, {
        detector: {
          targetIntervalMs: 120,
          busyIntervalMs: 190,
          minConfidence: 0.38,
        },
        processing: {
          preprocessingVariants: ['ORIGINAL', 'CLAHE', 'DARK_BG', 'INVERTED', 'SHARPEN'],
        },
        buffer: {
          maxSize: 8,
          maxEntryAgeMs: 6500,
        },
        ocr: {
          minQuality: 0.32,
          firstReadMinQuality: 0.34,
          repeatReadMinQuality: 0.30,
          recognitionThreshold: 0.68,
          consensusVotes: 4,
          maxCandidateCrops: 6,
        },
        qualityGate: {
          marginalClasses: ['REFLECTION', 'LOW_CONTRAST', 'SLIGHT_BLUR'],
        },
      });

    case 'HIGHWAY':
      return mergeAdaptiveConfig(base, {
        detector: {
          targetIntervalMs: 70,
          busyIntervalMs: 110,
          minConfidence: 0.34,
        },
        processing: {
          maxLongEdge: 960,
          preprocessingVariants: ['ORIGINAL', 'SHARPEN', 'DARK_BG'],
        },
        buffer: {
          maxSize: 4,
          maxEntryAgeMs: 2500,
          cropSampleIntervalMultiplier: 0.65,
        },
        ocr: {
          consensusVotes: 2,
          maxConcurrency: 2,
          firstReadRetryMs: 70,
          repeatReadRetryMs: 140,
          requiredBufferedCrops: 1,
          maxBestCropAgeMs: 1200,
          maxCandidateCrops: 3,
          useInnerTextCrop: false,
        },
        track: {
          lifetimeMultiplier: 0.8,
          prioritizeHighestConfidence: true,
        },
      });

    case 'TRAFFIC':
    case 'PARKING':
      return mergeAdaptiveConfig(base, {
        detector: {
          targetIntervalMs: 90,
          busyIntervalMs: 145,
        },
        buffer: {
          maxSize: 8,
          maxEntryAgeMs: 7000,
          cropSampleIntervalMultiplier: 0.85,
        },
        ocr: {
          maxConcurrency: 4,
          requiredBufferedCrops: 1,
          maxCandidateCrops: 5,
        },
        track: {
          lifetimeMultiplier: 1.35,
          prioritizeHighestConfidence: true,
        },
      });

    default:
      return base;
  }
}

type DeepPartialAdaptiveConfig = {
  detector?: Partial<AdaptiveScannerConfig['detector']>;
  camera?: Partial<AdaptiveScannerConfig['camera']>;
  processing?: Partial<AdaptiveScannerConfig['processing']>;
  buffer?: Partial<AdaptiveScannerConfig['buffer']>;
  ocr?: Partial<AdaptiveScannerConfig['ocr']>;
  qualityGate?: Partial<AdaptiveScannerConfig['qualityGate']>;
  track?: Partial<AdaptiveScannerConfig['track']>;
};

function mergeAdaptiveConfig(
  base: AdaptiveScannerConfig,
  patch: DeepPartialAdaptiveConfig
): AdaptiveScannerConfig {
  return {
    ...base,
    detector: { ...base.detector, ...patch.detector },
    camera: { ...base.camera, ...patch.camera },
    processing: { ...base.processing, ...patch.processing },
    buffer: { ...base.buffer, ...patch.buffer },
    ocr: { ...base.ocr, ...patch.ocr },
    qualityGate: { ...base.qualityGate, ...patch.qualityGate },
    track: { ...base.track, ...patch.track },
  };
}
