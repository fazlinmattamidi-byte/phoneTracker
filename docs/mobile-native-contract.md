# PlateQ Native ANPR Bridge Contract

This contract defines the Flutter-to-native boundary for the replacement mobile application. Android and iOS must emit equivalent payloads so the Flutter UI, alerts, history, matching, and tests can stay platform-neutral.

## Channels

| Channel | Type | Direction | Purpose |
| --- | --- | --- | --- |
| `plateq.anpr/methods` | `MethodChannel` | Flutter -> native | Initialize, configure, start/stop scanning, select camera, request snapshots. |
| `plateq.anpr/events` | `EventChannel` | Native -> Flutter | Runtime state, camera changes, track updates, OCR results, match alerts, errors. |
| `plateq.anpr_camera_preview` | Platform view | Native -> Flutter UI | Camera preview rendered by CameraX on Android and AVFoundation on iOS. |

## Flutter Method Calls

### `initialize`

Loads models, initializes runtime capability detection, and prepares the native camera layer.

Request:

```json
{
  "modelAssets": {
    "detector": "assets/public/models/plate-detector.onnx",
    "ocr": "assets/public/models/ppocr-rec.onnx",
    "ocrDictionary": "assets/public/models/ppocr-dict.txt",
    "environment": "assets/public/models/environment-classifier.onnx",
    "environmentMetadata": "assets/public/models/environment-classifier.metadata.json",
    "plateQuality": "assets/public/models/plate-quality-classifier.onnx",
    "plateQualityMetadata": "assets/public/models/plate-quality-classifier.metadata.json"
  },
  "deviceTier": "AUTO",
  "enableHardwareAcceleration": true
}
```

Response:

```json
{
  "runtimeState": "READY",
  "deviceTier": "MEDIUM",
  "detectorProvider": "CPU",
  "ocrProvider": "CPU",
  "environmentProvider": "CPU",
  "plateQualityProvider": "HEURISTIC",
  "warnings": []
}
```

### `listCameras`

Returns currently available native cameras.

Response:

```json
[
  {
    "id": "back-0",
    "label": "Rear Camera",
    "facing": "BACK",
    "isDefault": true,
    "supportsAutofocus": true,
    "supportsExposure": true,
    "supportedResolutions": ["1920x1080", "1280x720"],
    "supportedFps": [30, 60]
  }
]
```

### `selectCamera`

Request:

```json
{
  "cameraId": "back-0"
}
```

### `startScanning`

Request:

```json
{
  "cameraId": "back-0",
  "settings": {
    "detectionThreshold": 0.35,
    "recognitionThreshold": 0.60,
    "consensusVotes": 3,
    "maxTracks": 8,
    "maxOcrConcurrency": 3,
    "enableSpecialSeries": true,
    "scannerMode": "MULTI_VEHICLE"
  }
}
```

### `stopScanning`

Stops frame acquisition and inference, releases camera resources, and keeps finalized events/history available to Flutter.

### `updateSettings`

Applies runtime settings without forcing a camera restart when possible.

### `setFacing`

Request:

```json
{
  "facing": "BACK"
}
```

### `dispose`

Releases camera, ONNX sessions, tensors, pixel buffers, and pending queues.

## Native Event Payloads

Every event must contain:

```json
{
  "type": "runtime",
  "timestamp": "2026-08-10T04:00:00.000Z",
  "platform": "android"
}
```

### Runtime State Event

```json
{
  "type": "runtime",
  "runtimeState": "SCANNING",
  "deviceTier": "HIGH",
  "cameraId": "back-0",
  "cameraLabel": "Rear Camera",
  "detectorFps": 9.8,
  "cameraFps": 30.0,
  "ocrQueueDepth": 1,
  "temperatureState": "NOMINAL",
  "memoryMb": 184.2
}
```

### Camera Availability Event

```json
{
  "type": "cameraListChanged",
  "cameras": []
}
```

### Track Update Event

Bounding boxes use normalized camera-preview coordinates in the range `0.0` to `1.0`, measured against the visible preview frame after orientation correction. Native code must also keep original pixel coordinates internally for crops and evidence.

```json
{
  "type": "trackUpdate",
  "tracks": [
    {
      "trackId": "track-42",
      "trackNumber": 42,
      "state": "VISIBLE",
      "pipelineState": "COLLECTING",
      "bbox": { "x": 0.28, "y": 0.62, "width": 0.22, "height": 0.06 },
      "confidence": 0.86,
      "detectorConfidence": 0.91,
      "motionScore": 0.14,
      "qualityScore": 0.72,
      "qualityClass": "STANDARD_RECTANGLE",
      "currentPlate": "ANN7569",
      "currentPlateConfidence": 0.82,
      "matchType": "NONE"
    }
  ]
}
```

### OCR Event

```json
{
  "type": "ocr",
  "trackId": "track-42",
  "rawText": "ANN7569",
  "normalizedPlate": "ANN7569",
  "displayPlate": "ANN 7569",
  "confidence": 0.91,
  "layout": "SINGLE_LINE",
  "category": "STANDARD",
  "patternScore": 0.88,
  "characterConfidences": [
    { "char": "A", "confidence": 0.95, "position": 0 }
  ]
}
```

### Match Alert Event

This event must not be emitted without evidence. If a match is confirmed after the vehicle disappears, native code must process the retained best evidence and still include the image fields.

```json
{
  "type": "matchAlert",
  "trackId": "track-42",
  "plate": "ANN7569",
  "confidence": 0.91,
  "matchType": "EXACT",
  "reason": "Exact normalized plate equality",
  "cameraId": "back-0",
  "cameraLabel": "Rear Camera",
  "vehicle": {
    "id": "veh-001",
    "plate": "ANN7569",
    "customerName": "Ahmad",
    "brand": "Perodua",
    "model": "Bezza",
    "colour": "White",
    "financeCompany": "CIMB Bank",
    "reference": "CIMB001",
    "priority": "HIGH",
    "status": "ACTIVE"
  },
  "evidence": {
    "vehicleImagePath": "file:///...",
    "plateImagePath": "file:///...",
    "capturedAt": "2026-08-10T04:00:00.000Z",
    "qualityScore": 0.78,
    "detectorConfidence": 0.91,
    "ocrConfidence": 0.91
  }
}
```

### Error Event

```json
{
  "type": "error",
  "code": "CAMERA_INTERRUPTED",
  "message": "Camera stream interrupted. Reconnecting.",
  "recoverable": true
}
```

## Native Pipeline Requirements

1. Each visible vehicle/plate candidate owns its own track, evidence buffers, OCR state, consensus state, match state, and alert state.
2. Prediction may be used briefly but stale boxes must be removed quickly. A previous vehicle's plate must never attach to a new vehicle.
3. Detection should populate evidence buffers immediately. OCR should be scheduled from selected best frames, not every frame.
4. If a vehicle disappears before OCR completes, native code must continue processing the captured best frame.
5. Exact or possible matches must include vehicle/plate evidence images.
6. Hardware acceleration must be capability-detected. CPU fallback is mandatory.
7. Thermal and memory pressure must reduce detector cadence, OCR concurrency, preprocessing variants, and evidence buffer size before instability.
8. The native implementation must expose deterministic test hooks for offline validation clips and static plate crops.
