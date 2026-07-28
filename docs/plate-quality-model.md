# Plate Quality Model Training

The plate quality model is a YOLOv8 classification model that decides whether a detected plate crop is worth sending to OCR. It does not read plate text.

## Classes

```text
READABLE
GOOD
SLIGHT_BLUR
MOTION_BLUR
OUT_OF_FOCUS
TOO_SMALL
LOW_CONTRAST
DIRTY
OCCLUDED
REFLECTION
```

The browser runtime reads `/models/plate-quality-classifier.metadata.json` when present, so the ONNX output order stays aligned with the trained model.

## Collect Data

Use Scanner Dataset Mode during real testing. Exported JSON includes each original frame, plate crop, environment label, quality label, OCR result, and confidence values.

For production training, review and correct `qualityClass` before preparing the dataset. Scanner-assigned labels are useful bootstrapping labels, not a replacement for human review.

## Prepare Dataset

```bash
npm run prepare:quality -- \
  --exports /path/to/track_dataset_export_*.json \
  --output datasets/plate-quality-cls \
  --min-label-confidence 0.70 \
  --val-ratio 0.20 \
  --clear
```

Useful options:

```bash
--max-per-class 5000
--dry-run
```

This writes:

```text
datasets/plate-quality-cls/
  train/GOOD/*.jpg
  train/MOTION_BLUR/*.jpg
  val/GOOD/*.jpg
  val/MOTION_BLUR/*.jpg
  metadata.json
```

## Train and Export ONNX

```bash
npm run train:quality -- \
  --data datasets/plate-quality-cls \
  --model yolov8n-cls.pt \
  --epochs 50 \
  --imgsz 224
```

This writes:

```text
public/models/plate-quality-classifier.onnx
public/models/plate-quality-classifier.metadata.json
```

If the model is absent, the scanner continues using the deterministic crop-quality heuristic fallback.

## Recommended Labeling Rules

Use `GOOD` for crisp, readable crops with strong contrast. Use `READABLE` for crops OCR can probably read but that are not ideal.

Use failure labels for the dominant reason OCR should be delayed or skipped:

| Class | Meaning |
| --- | --- |
| `SLIGHT_BLUR` | Readable but softened |
| `MOTION_BLUR` | Directional streaking from movement |
| `OUT_OF_FOCUS` | Defocused crop |
| `TOO_SMALL` | Plate text is too small for reliable OCR |
| `LOW_CONTRAST` | Washed-out, dark, or weak text/background separation |
| `DIRTY` | Dirt, haze, water, or smeared lens/crop |
| `OCCLUDED` | Plate partly hidden |
| `REFLECTION` | Glare or reflected light across text |
