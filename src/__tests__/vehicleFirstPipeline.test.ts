import { describe, expect, it } from 'vitest';
import {
  combinePlateDetectionsWithNms,
  expandPlateDetectionsToVehicleDetections,
  mapVehiclePlateDetectionsToFrame,
  type VehicleFrameEntry,
} from '../lib/anpr/vehicleFirstPipeline';
import type { DetectedPlateBox } from '../lib/anpr/yoloDetector';

describe('vehicle-first pipeline helpers', () => {
  it('expands plate detections into bounded vehicle search regions', () => {
    const plate: DetectedPlateBox = {
      bbox: { x: 300, y: 220, width: 90, height: 28 },
      confidence: 0.82,
      label: 'License-Plate',
      sourceEngine: 'LOCAL_ONNX',
    };

    const vehicles = expandPlateDetectionsToVehicleDetections([plate], 800, 450);

    expect(vehicles).toHaveLength(1);
    expect(vehicles[0].bbox.width).toBeGreaterThan(plate.bbox.width);
    expect(vehicles[0].bbox.height).toBeGreaterThan(plate.bbox.height);
    expect(vehicles[0].bbox.x).toBeGreaterThanOrEqual(0);
    expect(vehicles[0].bbox.y).toBeGreaterThanOrEqual(0);
    expect(vehicles[0].source).toBe('PLATE_SEED');
  });

  it('maps plate detections from a buffered vehicle crop back to frame coordinates', () => {
    const entry: VehicleFrameEntry = {
      id: 'veh-1',
      canvas: { width: 200, height: 100 } as HTMLCanvasElement,
      timestamp: 1000,
      bbox: { x: 240, y: 120, width: 400, height: 200, confidence: 0.7 },
      detectorConfidence: 0.7,
      trackStability: 0.8,
      motionScore: 0.1,
      qualityScore: 0.75,
      sharpnessScore: 0.7,
      contrastScore: 0.8,
      sizeScore: 0.6,
      plateSearchCount: 0,
    };
    const cropDetection: DetectedPlateBox = {
      bbox: { x: 60, y: 40, width: 50, height: 16 },
      confidence: 0.74,
      label: 'License-Plate',
      sourceEngine: 'LOCAL_ONNX',
    };

    const [mapped] = mapVehiclePlateDetectionsToFrame(entry, [cropDetection]);

    expect(mapped.bbox).toEqual({ x: 360, y: 200, width: 100, height: 32 });
    expect(mapped.confidence).toBeCloseTo(0.718, 3);
  });

  it('deduplicates recovered plate boxes against live frame detections', () => {
    const live: DetectedPlateBox = {
      bbox: { x: 100, y: 100, width: 120, height: 35 },
      confidence: 0.88,
      label: 'License-Plate',
      sourceEngine: 'LOCAL_ONNX',
    };
    const duplicateRecovered: DetectedPlateBox = {
      bbox: { x: 104, y: 102, width: 118, height: 34 },
      confidence: 0.7,
      label: 'License-Plate',
      sourceEngine: 'LOCAL_ONNX',
    };
    const distinctRecovered: DetectedPlateBox = {
      bbox: { x: 420, y: 180, width: 100, height: 30 },
      confidence: 0.66,
      label: 'License-Plate',
      sourceEngine: 'LOCAL_ONNX',
    };

    const combined = combinePlateDetectionsWithNms(
      [live],
      [duplicateRecovered, distinctRecovered],
      800,
      450
    );

    expect(combined).toHaveLength(2);
    expect(combined[0]).toBe(live);
    expect(combined).toContain(distinctRecovered);
  });
});
