import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var plateqBridge: PlateqNativeBridge?
  private var plateqFileService: PlateqShareService?
  private var plateqAppStorage: PlateqAppStorage?
  private var plateqModelStaging: PlateqModelStaging?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PlateqNativeBridge") else {
      return
    }
    let bridge = PlateqNativeBridge()
    let fileService = PlateqShareService()
    let appStorage = PlateqAppStorage()
    let modelStaging = PlateqModelStaging()
    plateqBridge = bridge
    plateqFileService = fileService
    plateqAppStorage = appStorage
    plateqModelStaging = modelStaging

    FlutterMethodChannel(
      name: "plateq.anpr/methods",
      binaryMessenger: registrar.messenger()
    ).setMethodCallHandler(bridge.handle)
    FlutterEventChannel(
      name: "plateq.anpr/events",
      binaryMessenger: registrar.messenger()
    ).setStreamHandler(bridge)
    FlutterMethodChannel(
      name: "plateq.auth/session",
      binaryMessenger: registrar.messenger()
    ).setMethodCallHandler(PlateqSessionStore().handle)
    FlutterMethodChannel(
      name: "plateq.files/share",
      binaryMessenger: registrar.messenger()
    ).setMethodCallHandler(fileService.handle)
    FlutterMethodChannel(
      name: "plateq.app/storage",
      binaryMessenger: registrar.messenger()
    ).setMethodCallHandler(appStorage.handle)
    FlutterMethodChannel(
      name: "plateq.app/models",
      binaryMessenger: registrar.messenger()
    ).setMethodCallHandler(modelStaging.handle)
    registrar.register(PlateqCameraPreviewFactory(bridge: bridge), withId: "plateq.anpr_camera_preview")
  }
}

final class PlateqNativeBridge: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var timer: Timer?
  private var scanning = false
  private var selectedCameraId: String?
  private var lastSettings: [String: Any?] = [:]
  private var lastFrameWidth = 0
  private var lastFrameHeight = 0
  private var lastFrameRotation = 0
  private var frameCount = 0
  private var detectorFrameCount = 0
  private var lastDetectorFps = 0.0
  private var lastCameraFps = 0.0
  private var lastEnvironmentLabel = "GOOD_CONDITION"
  private var lastEnvironmentConfidence = 0.0
  private var lastEnvironmentBrightness = 0.0
  private var lastEnvironmentContrast = 0.0
  private var lastEnvironmentGlareRatio = 0.0
  private var lastPlateQualityScore = 0.0
  private var lastPlateQualityClass = "TOO_SMALL"
  private var lastDetectorConfidence = 0.0
  private var lastRuntimeFrameCount = 0
  private var lastRuntimeDetectorCount = 0
  private var lastRuntimeSample = Date()
  private let nativeTracker = NativeTrackEngine()
  private let ortRuntime = PlateqOrtRuntime()

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      let args = call.arguments as? [String: Any]
      requestCameraPermissionIfNeeded()
      ortRuntime.initialize(stagedModelAssets: readStagedModelAssets(args))
      result(runtimeStatus())
      emitRuntime(scanning ? "SCANNING" : "READY")
    case "listCameras":
      result(listNativeCameras())
    case "selectCamera":
      selectedCameraId = (call.arguments as? [String: Any])?["cameraId"] as? String
      result(nil)
    case "startScanning":
      guard hasCameraPermission() else {
        requestCameraPermissionIfNeeded()
        emitError(code: "CAMERA_PERMISSION", message: "Camera permission is required before scanning.", recoverable: true)
        result(FlutterError(code: "CAMERA_PERMISSION", message: "Camera permission is required before scanning.", details: nil))
        return
      }
      guard ortRuntime.realScannerReady() else {
        let message = "Native detector and OCR models must be initialized before scanning."
        emitError(code: "MODEL_NOT_READY", message: message, recoverable: true)
        result(FlutterError(code: "MODEL_NOT_READY", message: message, details: ortRuntime.warnings()))
        return
      }
      let args = call.arguments as? [String: Any]
      selectedCameraId = args?["cameraId"] as? String ?? selectedCameraId ?? defaultCameraId()
      lastSettings = args?["settings"] as? [String: Any?] ?? [:]
      nativeTracker.reset()
      frameCount = 0
      detectorFrameCount = 0
      lastRuntimeFrameCount = 0
      lastRuntimeDetectorCount = 0
      lastRuntimeSample = Date()
      scanning = true
      result(nil)
      emitRuntime("SCANNING")
      emitTrackUpdate()
      startTimer()
    case "stopScanning":
      stopTimer()
      scanning = false
      nativeTracker.reset()
      result(nil)
      emitRuntime("READY")
    case "updateSettings":
      let args = call.arguments as? [String: Any]
      lastSettings = args?["settings"] as? [String: Any?] ?? [:]
      result(nil)
      emitRuntime(scanning ? "SCANNING" : "READY")
    case "setFacing":
      let args = call.arguments as? [String: Any]
      selectedCameraId = cameraId(forFacing: args?["facing"] as? String ?? "BACK") ?? selectedCameraId
      result(nil)
    case "dispose":
      stopTimer()
      scanning = false
      nativeTracker.reset()
      ortRuntime.close()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    emitRuntime(scanning ? "SCANNING" : "READY")
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func runtimeStatus() -> [String: Any] {
    var warnings: [String] = []
    if !hasCameraPermission() {
      warnings.append("Camera permission has not been granted yet.")
    }
    warnings.append(contentsOf: ortRuntime.warnings())
    return [
      "runtimeState": scanning ? "SCANNING" : "READY",
      "deviceTier": deviceTier(),
      "detectorProvider": detectorProviderLabel(),
      "ocrProvider": ocrProviderLabel(),
      "environmentProvider": environmentProviderLabel(),
      "plateQualityProvider": plateQualityProviderLabel(),
      "warnings": Array(Set(warnings)).sorted(),
      "modelProviderStatus": ortRuntime.status(),
    ]
  }

  private func listNativeCameras() -> [[String: Any]] {
    let session = AVCaptureDevice.DiscoverySession(
      deviceTypes: [
        .builtInWideAngleCamera,
        .builtInDualCamera,
        .builtInUltraWideCamera,
        .builtInTelephotoCamera,
      ],
      mediaType: .video,
      position: .unspecified
    )
    let devices = session.devices
    guard !devices.isEmpty else {
      return [fallbackCamera()]
    }
    return devices.enumerated().map { index, device in
      let facing = facingName(device.position)
      let fps = device.formats
        .flatMap { $0.videoSupportedFrameRateRanges.map { Int($0.maxFrameRate.rounded()) } }
        .reduce(into: Set<Int>()) { $0.insert($1) }
        .sorted()
      let resolutions = device.formats
        .prefix(8)
        .map { format -> String in
          let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
          return "\(dimensions.width)x\(dimensions.height)"
        }
      return [
        "id": device.uniqueID,
        "label": device.localizedName.isEmpty ? "\(facing.capitalized) Camera \(index + 1)" : device.localizedName,
        "facing": facing,
        "isDefault": selectedCameraId == device.uniqueID || (selectedCameraId == nil && facing == "BACK"),
        "supportsAutofocus": device.isFocusModeSupported(.continuousAutoFocus),
        "supportsExposure": device.isExposureModeSupported(.continuousAutoExposure),
        "supportedResolutions": resolutions,
        "supportedFps": fps,
      ]
    }
  }

  private func fallbackCamera() -> [String: Any] {
    [
      "id": "native-back",
      "label": "Rear Camera",
      "facing": "BACK",
      "isDefault": true,
      "supportsAutofocus": false,
      "supportsExposure": false,
      "supportedResolutions": [String](),
      "supportedFps": [Int](),
    ]
  }

  private func defaultCameraId() -> String {
    cameraId(forFacing: "BACK") ?? listNativeCameras().first?["id"] as? String ?? "native-back"
  }

  private func cameraId(forFacing facing: String) -> String? {
    listNativeCameras().first { $0["facing"] as? String == facing }?["id"] as? String
  }

  private func facingName(_ position: AVCaptureDevice.Position) -> String {
    switch position {
    case .front:
      return "FRONT"
    case .back:
      return "BACK"
    default:
      return "EXTERNAL"
    }
  }

  private func startTimer() {
    stopTimer()
    timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      guard let self, self.scanning else { return }
      self.emitRuntime("SCANNING")
      self.emitTrackUpdate()
      self.emitOcrEvents()
    }
  }

  private func stopTimer() {
    timer?.invalidate()
    timer = nil
  }

  private func emitRuntime(_ state: String) {
    updateRuntimeFps()
    eventSink?([
      "type": "runtime",
      "timestamp": timestamp(),
      "platform": "ios",
      "runtimeState": state,
      "deviceTier": deviceTier(),
      "cameraId": selectedCameraId ?? defaultCameraId(),
      "cameraLabel": listNativeCameras().first { $0["id"] as? String == selectedCameraId }?["label"] as? String ?? "Rear Camera",
      "detectorFps": scanning ? lastDetectorFps : 0.0,
      "cameraFps": scanning ? lastCameraFps : 0.0,
      "ocrQueueDepth": 0,
      "temperatureState": thermalState(),
      "memoryMb": usedMemoryMb(),
      "frameWidth": lastFrameWidth,
      "frameHeight": lastFrameHeight,
      "frameRotation": lastFrameRotation,
      "frameCount": frameCount,
      "detectorProvider": detectorProviderLabel(),
      "ocrProvider": ocrProviderLabel(),
      "environmentProvider": environmentProviderLabel(),
      "plateQualityProvider": plateQualityProviderLabel(),
      "modelProviderStatus": ortRuntime.status(),
      "environmentLabel": lastEnvironmentLabel,
      "environmentConfidence": lastEnvironmentConfidence,
      "environmentStats": [
        "brightness": lastEnvironmentBrightness,
        "contrast": lastEnvironmentContrast,
        "glareRatio": lastEnvironmentGlareRatio,
      ],
      "plateQualityScore": lastPlateQualityScore,
      "plateQualityClass": lastPlateQualityClass,
      "settings": lastSettings,
    ])
  }

  func selectedCaptureDevice() -> AVCaptureDevice? {
    if let selectedCameraId {
      let session = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
        mediaType: .video,
        position: .unspecified
      )
      if let selected = session.devices.first(where: { $0.uniqueID == selectedCameraId }) {
        return selected
      }
    }
    return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) ??
      AVCaptureDevice.default(for: .video)
  }

  func recordFrame(sampleBuffer: CMSampleBuffer) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let nextFrame = frameCount + 1
    let analysis = shouldRunAnalyzer(nextFrameNumber: nextFrame)
      ? NativeFrameAnalyzer.analyze(
        pixelBuffer: pixelBuffer,
        frameNumber: nextFrame,
        threshold: settingDouble("detectionThreshold", fallback: 0.35),
        ortRuntime: ortRuntime
      )
      : nil
    let evidenceFrame = analysis == nil ? nil : NativeEvidenceFrame.fromPixelBuffer(pixelBuffer)
    DispatchQueue.main.async {
      self.lastFrameWidth = width
      self.lastFrameHeight = height
      self.lastFrameRotation = 0
      self.frameCount += 1
      guard self.scanning, let analysis else { return }
      self.detectorFrameCount += 1
      self.lastDetectorConfidence = analysis.detectorConfidence
      self.lastEnvironmentLabel = analysis.environmentLabel
      self.lastEnvironmentConfidence = analysis.environmentConfidence
      self.lastEnvironmentBrightness = analysis.brightness
      self.lastEnvironmentContrast = analysis.contrast
      self.lastEnvironmentGlareRatio = analysis.glareRatio
      self.lastPlateQualityScore = analysis.qualityScore
      self.lastPlateQualityClass = analysis.qualityClass
      self.nativeTracker.update(
        detections: analysis.detections,
        evidenceFrame: evidenceFrame,
        frameNumber: self.frameCount,
        timestampMs: Int(Date().timeIntervalSince1970 * 1000),
        maxTracks: self.settingInt("maxTracks", fallback: 8)
      )
      if self.frameCount % 3 == 0 {
        self.emitTrackUpdate()
        self.emitOcrEvents()
      }
    }
  }

  private func emitTrackUpdate() {
    eventSink?([
      "type": "trackUpdate",
      "timestamp": timestamp(),
      "platform": "ios",
      "tracks": nativeTracker.snapshot(),
    ])
  }

  private func emitOcrEvents() {
    let candidates = nativeTracker.ocrCandidates(
      frameNumber: frameCount,
      maxCount: effectiveOcrConcurrency()
    )
    for track in candidates {
      let nativeOcr = track.recognizeBestPlate(ortRuntime: ortRuntime)
      guard let nativeOcr, !nativeOcr.normalizedPlate.isEmpty else {
        track.markOcrAttempt(frameNumber: frameCount)
        continue
      }
      let normalizedPlate = nativeOcr.normalizedPlate
      let confidence = nativeOcr.confidence
      let characterConfidences = nativeOcr.characterConfidences
      track.markOcr(plate: normalizedPlate, confidence: confidence, frameNumber: frameCount)
      let evidencePaths = track.writeBestEvidenceFiles(
        cacheDirectory: evidenceCacheDirectory(),
        frameNumber: frameCount
      )
      eventSink?([
        "type": "ocr",
        "timestamp": timestamp(),
        "platform": "ios",
        "trackId": "track-\(track.trackNumber)",
        "rawText": nativeOcr.rawText,
        "normalizedPlate": normalizedPlate,
        "displayPlate": displayPlate(normalizedPlate),
        "confidence": confidence,
        "layout": nativeOcr.layout,
        "category": nativeOcr.category,
        "patternScore": nativeOcr.patternScore,
        "provider": nativeOcr.provider,
        "vehicleImagePath": evidencePaths?.vehicleImagePath ?? "",
        "plateImagePath": evidencePaths?.plateImagePath ?? "",
        "plateEnhancedImagePath": evidencePaths?.plateEnhancedImagePath ?? "",
        "plateBinaryImagePath": evidencePaths?.plateBinaryImagePath ?? "",
        "plateTopLineImagePath": evidencePaths?.plateTopLineImagePath ?? "",
        "plateBottomLineImagePath": evidencePaths?.plateBottomLineImagePath ?? "",
        "plateInnerTextImagePath": evidencePaths?.plateInnerTextImagePath ?? "",
        "plateCropWidth": evidencePaths?.plateCropWidth ?? 0,
        "plateCropHeight": evidencePaths?.plateCropHeight ?? 0,
        "preprocessingVariant": nativeOcr.preprocessingVariant,
        "preprocessingVariants": mergePreprocessingVariants(
          evidencePaths?.preprocessingVariants,
          nativeOcr.preprocessingVariant
        ),
        "characterConfidences": characterConfidences.map { $0.toMap() },
      ])
    }
  }

  private func mergePreprocessingVariants(_ evidenceVariants: [String]?, _ ocrVariant: String?) -> [String] {
    var variants: [String] = []
    for variant in evidenceVariants ?? [] where !variant.isEmpty && !variants.contains(variant) {
      variants.append(variant)
    }
    if let ocrVariant, !ocrVariant.isEmpty, !variants.contains(ocrVariant) {
      variants.append(ocrVariant)
    }
    return variants.isEmpty ? ["RAW_CROP"] : variants
  }

  private func detectorProviderLabel() -> String {
    ortRuntime.providerLabel(id: "detector", fallback: "UNAVAILABLE")
  }

  private func ocrProviderLabel() -> String {
    ortRuntime.providerLabel(id: "ocr", fallback: "UNAVAILABLE")
  }

  private func environmentProviderLabel() -> String {
    ortRuntime.providerLabel(id: "environment", fallback: "NATIVE_HEURISTIC")
  }

  private func plateQualityProviderLabel() -> String {
    ortRuntime.providerLabel(id: "plateQuality", fallback: "NATIVE_HEURISTIC")
  }

  private func displayPlate(_ plate: String) -> String {
    guard let split = plate.firstIndex(where: { $0.isNumber }), split > plate.startIndex else {
      return plate
    }
    return "\(plate[..<split]) \(plate[split...])"
  }

  private func evidenceCacheDirectory() -> URL {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ??
      URL(fileURLWithPath: NSTemporaryDirectory())
    let directory = base.appendingPathComponent("plateq-evidence", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func shouldRunAnalyzer(nextFrameNumber: Int) -> Bool {
    nextFrameNumber % effectiveAnalysisStride() == 0
  }

  private func effectiveAnalysisStride() -> Int {
    let tierStride: Int
    switch deviceTier() {
    case "LOW":
      tierStride = 3
    case "MEDIUM":
      tierStride = 2
    default:
      tierStride = 1
    }
    let environmentStride = ["GLARE", "FOG", "LOW_LIGHT", "NIGHT", "BACKLIGHT"].contains(lastEnvironmentLabel) ? 2 : 1
    return max(tierStride, environmentStride)
  }

  private func effectiveOcrConcurrency() -> Int {
    let tierLimit: Int
    switch deviceTier() {
    case "LOW":
      tierLimit = 1
    case "MEDIUM":
      tierLimit = 2
    default:
      tierLimit = 3
    }
    return max(1, min(settingInt("maxOcrConcurrency", fallback: 3), tierLimit))
  }

  private func deviceTier() -> String {
    let cores = ProcessInfo.processInfo.processorCount
    let memoryMb = Double(ProcessInfo.processInfo.physicalMemory) / (1024.0 * 1024.0)
    if cores >= 8, memoryMb >= 4096 { return "HIGH" }
    if cores >= 4, memoryMb >= 2048 { return "MEDIUM" }
    return "LOW"
  }

  private func usedMemoryMb() -> Double {
    roundMetric(Double(ProcessInfo.processInfo.physicalMemory) / (1024.0 * 1024.0))
  }

  private func thermalState() -> String {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal, .fair:
      return "NOMINAL"
    case .serious:
      return "WARM"
    case .critical:
      return "HOT"
    @unknown default:
      return "NOMINAL"
    }
  }

  private func updateRuntimeFps() {
    let now = Date()
    let elapsedSeconds = max(0.001, now.timeIntervalSince(lastRuntimeSample))
    if elapsedSeconds < 0.75 { return }
    lastCameraFps = clamp01(Double(frameCount - lastRuntimeFrameCount) / elapsedSeconds / 30.0) * 30.0
    lastDetectorFps = Double(detectorFrameCount - lastRuntimeDetectorCount) / elapsedSeconds
    lastRuntimeFrameCount = frameCount
    lastRuntimeDetectorCount = detectorFrameCount
    lastRuntimeSample = now
  }

  private func settingDouble(_ key: String, fallback: Double) -> Double {
    guard let value = lastSettings[key] else { return fallback }
    if let number = value as? NSNumber { return number.doubleValue }
    if let number = value as? Double { return number }
    if let text = value as? String, let number = Double(text) { return number }
    return fallback
  }

  private func settingInt(_ key: String, fallback: Int) -> Int {
    guard let value = lastSettings[key] else { return fallback }
    if let number = value as? NSNumber { return number.intValue }
    if let number = value as? Int { return number }
    if let text = value as? String, let number = Int(text) { return number }
    return fallback
  }

  private func readStagedModelAssets(_ args: [String: Any]?) -> [String: String] {
    guard let staged = args?["stagedModelAssets"] as? [String: Any] else { return [:] }
    return staged.reduce(into: [String: String]()) { result, entry in
      let path = String(describing: entry.value)
      if !entry.key.isEmpty, !path.isEmpty {
        result[entry.key] = path
      }
    }
  }

  private func emitError(code: String, message: String, recoverable: Bool) {
    eventSink?([
      "type": "error",
      "timestamp": timestamp(),
      "platform": "ios",
      "code": code,
      "message": message,
      "recoverable": recoverable,
    ])
  }

  private func hasCameraPermission() -> Bool {
    AVCaptureDevice.authorizationStatus(for: .video) == .authorized
  }

  private func requestCameraPermissionIfNeeded() {
    if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
      AVCaptureDevice.requestAccess(for: .video) { _ in }
    }
  }

  private func timestamp() -> String {
    ISO8601DateFormatter().string(from: Date())
  }
}

private let ppOcrTargetWidth = 320
private let ppOcrTargetHeight = 48

private struct NativeOcrCharacterConfidence {
  let char: String
  let confidence: Double
  let position: Int

  func toMap() -> [String: Any] {
    [
      "char": char,
      "confidence": confidence,
      "position": position,
    ]
  }
}

private struct NativeOcrResult {
  let rawText: String
  let normalizedPlate: String
  let confidence: Double
  let characterConfidences: [NativeOcrCharacterConfidence]
  let layout: String
  let category: String
  let patternScore: Double
  let provider: String
  let preprocessingVariant: String
}

private struct NativePpOcrDecodeResult {
  let rawText: String
  let confidence: Double
  let characterConfidences: [NativeOcrCharacterConfidence]
}

private final class PlateqOrtRuntime {
  private let lock = NSLock()
  private var environment: ORTEnv?
  private var sessions: [String: OrtModelSession] = [:]
  private var errors: [String: String] = [:]
  private var ocrDictionary: [String] = []
  private var lastDetectorInferenceError: String?
  private var lastOcrInferenceError: String?

  func initialize(stagedModelAssets: [String: String]) {
    lock.lock()
    defer { lock.unlock() }
    closeLocked()
    loadOcrDictionary(stagedModelAssets["ocrDictionary"])
    let onnxAssets = [
      "detector": stagedModelAssets["detector"],
      "ocr": stagedModelAssets["ocr"],
      "environment": stagedModelAssets["environment"],
      "plateQuality": stagedModelAssets["plateQuality"],
    ]
    for (id, path) in onnxAssets {
      guard let path, !path.isEmpty else {
        if id != "plateQuality" {
          errors[id] = "Native model path was not staged."
        }
        continue
      }
      loadSession(id: id, path: path)
    }
  }

  func recognizePlateCrop(
    crop: UIImage,
    preprocessingVariant: String,
    layout: String
  ) -> NativeOcrResult? {
    lock.lock()
    defer { lock.unlock() }
    guard let model = sessions["ocr"], !ocrDictionary.isEmpty else { return nil }
    do {
      let inputData = PpOcrTensor.fromImage(crop)
      let output = try runFloatModel(
        model: model,
        inputData: inputData,
        inputShape: [
          NSNumber(value: 1),
          NSNumber(value: 3),
          NSNumber(value: ppOcrTargetHeight),
          NSNumber(value: ppOcrTargetWidth),
        ]
      )
      let decoded = decodePpOcrOutput(raw: output.values, dims: output.shape)
      let normalized = normalizeNativePlate(decoded.rawText)
      guard normalized.count >= 2 else { return nil }
      let patternScore = nativePatternScore(normalized)
      lastOcrInferenceError = nil
      return NativeOcrResult(
        rawText: decoded.rawText,
        normalizedPlate: normalized,
        confidence: roundMetric(decoded.confidence),
        characterConfidences: normalizeNativeCharacterConfidences(decoded: decoded, normalizedPlate: normalized),
        layout: layout,
        category: nativePlateCategory(normalized),
        patternScore: patternScore,
        provider: "CPU_ONNX_PP_OCR",
        preprocessingVariant: preprocessingVariant
      )
    } catch {
      lastOcrInferenceError = error.localizedDescription
      return nil
    }
  }

  func detectPlates(pixelBuffer: CVPixelBuffer, minConfidence: Double) -> [NativeOnnxDetection] {
    lock.lock()
    defer { lock.unlock() }
    guard let model = sessions["detector"] else { return [] }
    do {
      let inputData = ImageLetterboxTensor.fromPixelBuffer(pixelBuffer)
      let output = try runFloatModel(
        model: model,
        inputData: inputData.tensor,
        inputShape: [
          NSNumber(value: 1),
          NSNumber(value: 3),
          NSNumber(value: ImageLetterboxTensor.targetSize),
          NSNumber(value: ImageLetterboxTensor.targetSize),
        ]
      )
      let detections = decodeYoloOutput(
        raw: output.values,
        dims: output.shape,
        imageWidth: CVPixelBufferGetWidth(pixelBuffer),
        imageHeight: CVPixelBufferGetHeight(pixelBuffer),
        letterbox: inputData.letterbox,
        minConfidence: minConfidence
      )
      lastDetectorInferenceError = nil
      return detections
    } catch {
      lastDetectorInferenceError = error.localizedDescription
      return []
    }
  }

  func realScannerReady() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return sessions["detector"] != nil &&
      sessions["ocr"] != nil &&
      !ocrDictionary.isEmpty
  }

  func providerLabel(id: String, fallback: String) -> String {
    lock.lock()
    defer { lock.unlock() }
    guard sessions[id] != nil else { return fallback }
    switch id {
    case "detector":
      return lastDetectorInferenceError == nil ? "CPU_ONNX" : "CPU_ONNX_ERROR"
    case "ocr":
      return !ocrDictionary.isEmpty && lastOcrInferenceError == nil ? "CPU_ONNX_PP_OCR" : "CPU_ONNX_PP_OCR_ERROR"
    default:
      return "CPU_ONNX_READY"
    }
  }

  func warnings() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    var output = errors
      .sorted { $0.key < $1.key }
      .map { "ONNX \($0.key) unavailable: \($0.value)" }
    if let lastDetectorInferenceError {
      output.append("ONNX detector inference unavailable: \(lastDetectorInferenceError)")
    }
    if let lastOcrInferenceError {
      output.append("ONNX OCR inference unavailable: \(lastOcrInferenceError)")
    }
    return output
  }

  func status() -> [String: Any] {
    lock.lock()
    defer { lock.unlock() }
    let ids = ["detector", "ocr", "environment", "plateQuality"]
    return ids.reduce(into: [String: Any]()) { result, id in
      if let session = sessions[id] {
        let extra: [String: Any]
        switch id {
        case "detector":
          extra = ["lastInferenceError": lastDetectorInferenceError as Any]
        case "ocr":
          extra = [
            "dictionaryReady": !ocrDictionary.isEmpty,
            "dictionaryEntries": ocrDictionary.count,
            "lastInferenceError": lastOcrInferenceError as Any,
          ]
        default:
          extra = [:]
        }
        result[id] = session.toMap(extra: extra)
      } else {
        result[id] = [
          "state": "UNAVAILABLE",
          "error": errors[id] as Any,
        ]
      }
    }
  }

  func close() {
    lock.lock()
    defer { lock.unlock() }
    closeLocked()
  }

  private func closeLocked() {
    sessions.removeAll()
    errors.removeAll()
    ocrDictionary = []
    lastDetectorInferenceError = nil
    lastOcrInferenceError = nil
    environment = nil
  }

  private func loadOcrDictionary(_ path: String?) {
    guard let path, !path.isEmpty else {
      errors["ocrDictionary"] = "Native dictionary path was not staged."
      return
    }
    guard FileManager.default.fileExists(atPath: path) else {
      errors["ocrDictionary"] = "File missing at \(path)"
      return
    }
    do {
      var entries = try String(contentsOfFile: path, encoding: .utf8)
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      entries.append(" ")
      ocrDictionary = entries
    } catch {
      errors["ocrDictionary"] = error.localizedDescription
      ocrDictionary = []
    }
  }

  private func loadSession(id: String, path: String) {
    guard FileManager.default.fileExists(atPath: path) else {
      errors[id] = "File missing at \(path)"
      return
    }
    let sizeBytes = fileSize(path)
    guard sizeBytes > 0 else {
      errors[id] = "File empty at \(path)"
      return
    }
    do {
      let env = try environment ?? ORTEnv(loggingLevel: .warning)
      environment = env
      let options = try ORTSessionOptions()
      try options.setGraphOptimizationLevel(.all)
      let session = try ORTSession(env: env, modelPath: path, sessionOptions: options)
      sessions[id] = OrtModelSession(
        id: id,
        nativePath: path,
        sizeBytes: sizeBytes,
        session: session,
        inputNames: try session.inputNames(),
        outputNames: try session.outputNames()
      )
    } catch {
      errors[id] = error.localizedDescription
    }
  }

  private func fileSize(_ path: String) -> Int64 {
    let attributes = try? FileManager.default.attributesOfItem(atPath: path)
    return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
  }

  private func runFloatModel(
    model: OrtModelSession,
    inputData: [Float],
    inputShape: [NSNumber]
  ) throws -> (values: [Float], shape: [Int]) {
    let tensorBytes = inputData.withUnsafeBufferPointer { buffer -> NSMutableData in
      NSMutableData(
        bytes: buffer.baseAddress!,
        length: buffer.count * MemoryLayout<Float>.stride
      )
    }
    let tensor = try ORTValue(
      tensorData: tensorBytes,
      elementType: .float,
      shape: inputShape
    )
    let outputs = try model.session.run(
      withInputs: [model.primaryInputName("images"): tensor],
      outputNames: Set(model.outputNames),
      runOptions: nil
    )
    guard let outputValue = model.outputNames.compactMap({ outputs[$0] }).first else {
      return ([], [])
    }
    let shape = try outputValue.tensorTypeAndShapeInfo().shape.map { $0.intValue }
    let outputData = try outputValue.tensorData()
    let count = outputData.length / MemoryLayout<Float>.stride
    let pointer = outputData.bytes.bindMemory(to: Float.self, capacity: count)
    let values = Array(UnsafeBufferPointer(start: pointer, count: count))
    return (values, shape)
  }

  private func decodePpOcrOutput(raw: [Float], dims: [Int]) -> NativePpOcrDecodeResult {
    let positiveDims = dims.filter { $0 > 0 }
    guard positiveDims.count >= 2, !raw.isEmpty else {
      return NativePpOcrDecodeResult(rawText: "", confidence: 0.0, characterConfidences: [])
    }

    let expectedClassCount = ocrDictionary.count + 1
    let sequenceLength: Int
    let classCount: Int
    let transposed: Bool
    if positiveDims.count >= 3 {
      let middle = positiveDims[positiveDims.count - 2]
      let last = positiveDims.last ?? 0
      transposed = middle == expectedClassCount && last != expectedClassCount
      sequenceLength = transposed ? last : middle
      classCount = transposed ? middle : last
    } else {
      sequenceLength = positiveDims[0]
      classCount = positiveDims[1]
      transposed = false
    }
    guard sequenceLength > 0, classCount > 0 else {
      return NativePpOcrDecodeResult(rawText: "", confidence: 0.0, characterConfidences: [])
    }

    var chars: [String] = []
    var characterConfidences: [NativeOcrCharacterConfidence] = []
    var previousIndex = 0
    let maxTimesteps = min(sequenceLength, max(1, raw.count / max(1, classCount)))
    for timestep in 0..<maxTimesteps {
      var maxIndex = 0
      var maxScore = -Float.greatestFiniteMagnitude
      for classIndex in 0..<classCount {
        let offset = transposed
          ? classIndex * sequenceLength + timestep
          : timestep * classCount + classIndex
        let score = offset >= 0 && offset < raw.count ? raw[offset] : -Float.greatestFiniteMagnitude
        if score > maxScore {
          maxScore = score
          maxIndex = classIndex
        }
      }
      if maxIndex != 0, maxIndex != previousIndex {
        let dictionaryIndex = maxIndex - 1
        if dictionaryIndex >= 0, dictionaryIndex < ocrDictionary.count {
          let char = ocrDictionary[dictionaryIndex]
          if !char.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chars.append(char)
            characterConfidences.append(
              NativeOcrCharacterConfidence(
                char: char,
                confidence: roundMetric(clamp(Double(maxScore), 0.0, 1.0)),
                position: characterConfidences.count
              )
            )
          }
        }
      }
      previousIndex = maxIndex
    }

    let confidence = characterConfidences.isEmpty
      ? 0.0
      : characterConfidences.map(\.confidence).reduce(0.0, +) / Double(characterConfidences.count)
    return NativePpOcrDecodeResult(
      rawText: chars.joined(),
      confidence: confidence,
      characterConfidences: characterConfidences
    )
  }

  private func normalizeNativeCharacterConfidences(
    decoded: NativePpOcrDecodeResult,
    normalizedPlate: String
  ) -> [NativeOcrCharacterConfidence] {
    let cleaned = decoded.characterConfidences.compactMap { item -> NativeOcrCharacterConfidence? in
      let normalizedChar = normalizeNativePlate(item.char)
      guard normalizedChar.count == 1 else { return nil }
      return NativeOcrCharacterConfidence(char: normalizedChar, confidence: item.confidence, position: item.position)
    }
    if cleaned.count == normalizedPlate.count {
      return cleaned.enumerated().map { index, item in
        NativeOcrCharacterConfidence(char: item.char, confidence: item.confidence, position: index)
      }
    }
    return normalizedPlate.enumerated().map { index, character in
      NativeOcrCharacterConfidence(
        char: String(character),
        confidence: roundMetric(decoded.confidence),
        position: index
      )
    }
  }

  private func decodeYoloOutput(
    raw: [Float],
    dims: [Int],
    imageWidth: Int,
    imageHeight: Int,
    letterbox: YoloLetterbox,
    minConfidence: Double
  ) -> [NativeOnnxDetection] {
    guard imageWidth > 0, imageHeight > 0, dims.count >= 2, !raw.isEmpty else { return [] }
    let shape = YoloOutputShape.fromDims(dims)
    let hasObjectness = shape.channelCount == 6 || shape.channelCount == 85
    let minBoxWidth = max(32.0, Double(imageWidth) * 0.022)
    let minBoxHeight = max(9.0, Double(imageHeight) * 0.008)
    var candidates: [YoloCandidate] = []

    for index in 0..<shape.sequenceLength {
      func read(_ channel: Int) -> Double {
        let offset = shape.transposed
          ? index * shape.channelCount + channel
          : channel * shape.sequenceLength + index
        guard offset >= 0, offset < raw.count else { return Double.nan }
        return Double(raw[offset])
      }

      let cx = read(0)
      let cy = read(1)
      let width = read(2)
      let height = read(3)
      let objectness = hasObjectness ? read(4) : 1.0
      let classChannel = hasObjectness ? 5 : 4
      let classConfidence = read(classChannel)
      let confidence = objectness * classConfidence

      guard [cx, cy, width, height, confidence].allSatisfy({ $0.isFinite }),
            confidence >= minConfidence else {
        continue
      }

      let realCx = (cx - Double(letterbox.padX)) / letterbox.scale
      let realCy = (cy - Double(letterbox.padY)) / letterbox.scale
      let realWidth = width / letterbox.scale
      let realHeight = height / letterbox.scale
      let left = clamp(realCx - realWidth / 2.0, 0.0, Double(imageWidth))
      let top = clamp(realCy - realHeight / 2.0, 0.0, Double(imageHeight))
      let right = clamp(realCx + realWidth / 2.0, 0.0, Double(imageWidth))
      let bottom = clamp(realCy + realHeight / 2.0, 0.0, Double(imageHeight))
      let finalWidth = round(right - left)
      let finalHeight = round(bottom - top)

      if finalWidth >= minBoxWidth, finalHeight >= minBoxHeight {
        candidates.append(
          YoloCandidate(
            x: round(left),
            y: round(top),
            width: finalWidth,
            height: finalHeight,
            confidence: roundMetric(confidence)
          )
        )
      }
    }

    return applyYoloFiltersAndNms(candidates, imageWidth: imageWidth, imageHeight: imageHeight)
      .map { candidate in
        NativeOnnxDetection(
          bbox: NativeBbox(
            x: roundMetric(candidate.x / Double(imageWidth)),
            y: roundMetric(candidate.y / Double(imageHeight)),
            width: roundMetric(candidate.width / Double(imageWidth)),
            height: roundMetric(candidate.height / Double(imageHeight))
          ),
          confidence: candidate.confidence
        )
      }
  }

  private func applyYoloFiltersAndNms(
    _ candidates: [YoloCandidate],
    imageWidth: Int,
    imageHeight: Int,
    iouThreshold: Double = 0.35
  ) -> [YoloCandidate] {
    let minWidth = max(28.0, Double(imageWidth) * 0.018)
    let minHeight = max(8.0, Double(imageHeight) * 0.007)
    let filtered = candidates.filter { candidate in
      guard candidate.width >= minWidth, candidate.height >= minHeight, candidate.height > 0.0 else { return false }
      let aspectRatio = candidate.width / candidate.height
      return aspectRatio >= 0.65 && aspectRatio <= 7.2
    }
    let frameArea = imageWidth * imageHeight
    let sorted = filtered.sorted { $0.rank(frameArea: frameArea) > $1.rank(frameArea: frameArea) }
    var selected: [YoloCandidate] = []
    for candidate in sorted {
      let keep = selected.allSatisfy { existing in
        candidate.iou(existing) <= min(iouThreshold, 0.35) && !candidate.isMostlyContained(by: existing)
      }
      if keep {
        selected.append(candidate)
      }
      if selected.count >= 12 { break }
    }
    return selected
  }
}

private struct OrtModelSession {
  let id: String
  let nativePath: String
  let sizeBytes: Int64
  let session: ORTSession
  let inputNames: [String]
  let outputNames: [String]

  func primaryInputName(_ fallback: String) -> String {
    inputNames.first ?? fallback
  }

  func toMap(extra: [String: Any] = [:]) -> [String: Any] {
    [
      "state": "READY",
      "id": id,
      "nativePath": nativePath,
      "sizeBytes": sizeBytes,
      "inputNames": inputNames,
      "outputNames": outputNames,
    ].merging(extra) { _, new in new }
  }
}

private struct NativeOnnxDetection {
  let bbox: NativeBbox
  let confidence: Double
}

private enum PpOcrTensor {
  static func fromImage(_ source: UIImage) -> [Float] {
    let width = ppOcrTargetWidth
    let height = ppOcrTargetHeight
    var pixels = [UInt8](repeating: 127, count: width * height * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
      data: &pixels,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return [Float](repeating: 0.0, count: width * height * 3)
    }
    context.setFillColor(UIColor(red: 0.498, green: 0.498, blue: 0.498, alpha: 1).cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    if let cgImage = source.cgImage {
      let scale = min(
        CGFloat(width) / max(1.0, CGFloat(cgImage.width)),
        CGFloat(height) / max(1.0, CGFloat(cgImage.height))
      )
      let drawWidth = max(1.0, CGFloat(cgImage.width) * scale)
      let drawHeight = max(1.0, CGFloat(cgImage.height) * scale)
      let offsetY = (CGFloat(height) - drawHeight) / 2.0
      context.interpolationQuality = .high
      context.draw(
        cgImage,
        in: CGRect(x: 0, y: offsetY, width: min(CGFloat(width), drawWidth), height: drawHeight)
      )
    }

    let area = width * height
    var tensor = [Float](repeating: 0.0, count: area * 3)
    for index in 0..<area {
      let offset = index * 4
      tensor[index] = normalizePpOcrChannel(pixels[offset])
      tensor[area + index] = normalizePpOcrChannel(pixels[offset + 1])
      tensor[area * 2 + index] = normalizePpOcrChannel(pixels[offset + 2])
    }
    return tensor
  }

  private static func normalizePpOcrChannel(_ value: UInt8) -> Float {
    Float((Double(value) / 255.0 - 0.5) / 0.5)
  }
}

private struct ImageLetterboxTensor {
  static let targetSize = 640
  let tensor: [Float]
  let letterbox: YoloLetterbox

  static func fromPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> ImageLetterboxTensor {
    let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
    let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
    let letterbox = YoloLetterbox(sourceWidth: sourceWidth, sourceHeight: sourceHeight, targetSize: targetSize)
    let area = targetSize * targetSize
    var tensor = [Float](repeating: 127.0 / 255.0, count: area * 3)
    guard sourceWidth > 0, sourceHeight > 0 else {
      return ImageLetterboxTensor(tensor: tensor, letterbox: letterbox)
    }

    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    let context = CIContext()
    guard let cgImage = context.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight)) else {
      return ImageLetterboxTensor(tensor: tensor, letterbox: letterbox)
    }

    var pixels = [UInt8](repeating: 127, count: area * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let drawContext = CGContext(
      data: &pixels,
      width: targetSize,
      height: targetSize,
      bitsPerComponent: 8,
      bytesPerRow: targetSize * 4,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return ImageLetterboxTensor(tensor: tensor, letterbox: letterbox)
    }
    drawContext.setFillColor(UIColor(red: 0.498, green: 0.498, blue: 0.498, alpha: 1).cgColor)
    drawContext.fill(CGRect(x: 0, y: 0, width: targetSize, height: targetSize))
    drawContext.interpolationQuality = .high
    drawContext.draw(
      cgImage,
      in: CGRect(
        x: letterbox.padX,
        y: letterbox.padY,
        width: letterbox.drawWidth,
        height: letterbox.drawHeight
      )
    )

    for index in 0..<area {
      let offset = index * 4
      tensor[index] = Float(pixels[offset]) / 255.0
      tensor[area + index] = Float(pixels[offset + 1]) / 255.0
      tensor[area * 2 + index] = Float(pixels[offset + 2]) / 255.0
    }
    return ImageLetterboxTensor(tensor: tensor, letterbox: letterbox)
  }
}

private struct YoloLetterbox {
  let sourceWidth: Int
  let sourceHeight: Int
  let targetSize: Int
  let scale: Double
  let drawWidth: Int
  let drawHeight: Int
  let padX: Int
  let padY: Int

  init(sourceWidth: Int, sourceHeight: Int, targetSize: Int = 640) {
    self.sourceWidth = sourceWidth
    self.sourceHeight = sourceHeight
    self.targetSize = targetSize
    scale = min(Double(targetSize) / Double(max(1, sourceWidth)), Double(targetSize) / Double(max(1, sourceHeight)))
    drawWidth = Int(round(Double(sourceWidth) * scale))
    drawHeight = Int(round(Double(sourceHeight) * scale))
    padX = Int(round((Double(targetSize - drawWidth)) / 2.0))
    padY = Int(round((Double(targetSize - drawHeight)) / 2.0))
  }
}

private struct YoloOutputShape {
  let sequenceLength: Int
  let channelCount: Int
  let transposed: Bool

  static func fromDims(_ dims: [Int]) -> YoloOutputShape {
    let d1 = dims[max(0, dims.count - 2)]
    let d2 = dims[max(0, dims.count - 1)]
    if isYoloChannelCount(d2), !isYoloChannelCount(d1) {
      return YoloOutputShape(sequenceLength: d1, channelCount: d2, transposed: true)
    }
    if isYoloChannelCount(d1), !isYoloChannelCount(d2) {
      return YoloOutputShape(sequenceLength: d2, channelCount: d1, transposed: false)
    }
    return d1 > d2
      ? YoloOutputShape(sequenceLength: d1, channelCount: d2, transposed: true)
      : YoloOutputShape(sequenceLength: d2, channelCount: d1, transposed: false)
  }

  private static func isYoloChannelCount(_ value: Int) -> Bool {
    value == 5 || value == 6 || value == 85
  }
}

private struct YoloCandidate {
  let x: Double
  let y: Double
  let width: Double
  let height: Double
  let confidence: Double

  private var area: Double {
    width * height
  }

  func iou(_ other: YoloCandidate) -> Double {
    let left = max(x, other.x)
    let top = max(y, other.y)
    let right = min(x + width, other.x + other.width)
    let bottom = min(y + height, other.y + other.height)
    let intersection = max(0.0, right - left) * max(0.0, bottom - top)
    let union = area + other.area - intersection
    return union <= 0.0 ? 0.0 : intersection / union
  }

  func rank(frameArea: Int) -> Double {
    let areaScore = min(1.0, area / max(1.0, Double(frameArea) * 0.08))
    return confidence * 0.68 + areaScore * 0.32
  }

  func isMostlyContained(by outer: YoloCandidate) -> Bool {
    let centerX = x + width / 2.0
    let centerY = y + height / 2.0
    let centerInside =
      centerX >= outer.x &&
        centerX <= outer.x + outer.width &&
        centerY >= outer.y &&
        centerY <= outer.y + outer.height
    return centerInside && area < outer.area * 0.65
  }
}

private func normalizeNativePlate(_ raw: String) -> String {
  raw.uppercased().filter { character in
    character.unicodeScalars.allSatisfy { scalar in
      (65...90).contains(Int(scalar.value)) || (48...57).contains(Int(scalar.value))
    }
  }
}

private func nativePatternScore(_ plate: String) -> Double {
  if plate.count < 2 || plate.count > 10 { return 0.0 }
  let letters = plate.filter(isNativeAsciiLetter).count
  let digits = plate.filter(isNativeAsciiDigit).count
  if letters == 0 || digits == 0 { return 0.16 }
  let standard = matchesNativeRegex(plate, pattern: "^[A-Z]{1,3}[0-9]{1,4}[A-Z]?$")
  let diplomatic = matchesNativeRegex(plate, pattern: "^[A-Z]{2}[0-9]{1,4}$")
  let lengthScore = clamp01(Double(plate.count) / 7.0)
  let structureScore = standard || diplomatic ? 0.58 : 0.30
  let balanceScore = digits >= 2 && letters <= 5 ? 0.22 : 0.10
  return roundMetric(clamp01(structureScore + balanceScore + lengthScore * 0.20))
}

private func nativePlateCategory(_ plate: String) -> String {
  if matchesNativeRegex(plate, pattern: "^[A-Z]{1,3}[0-9]{1,4}[A-Z]?$") {
    return "STANDARD"
  }
  if plate.count >= 2, plate.count <= 10, plate.contains(where: isNativeAsciiDigit), plate.contains(where: isNativeAsciiLetter) {
    return "UNKNOWN_VALID_CANDIDATE"
  }
  return "UNKNOWN"
}

private func rankNativeOcrCandidate(_ candidate: NativeOcrResult) -> Double {
  let hasLetters = candidate.normalizedPlate.contains(where: isNativeAsciiLetter)
  let hasDigits = candidate.normalizedPlate.contains(where: isNativeAsciiDigit)
  let lengthScore = clamp01(Double(candidate.normalizedPlate.count) / 7.0)
  let layoutBonus = ["TWO_LINE", "SQUARE"].contains(candidate.layout) ? 0.06 : 0.0
  let recoveryPenalty: Double
  switch candidate.preprocessingVariant {
  case "ROTATE_180":
    recoveryPenalty = 0.04
  case "DESKEWED_ROTATION":
    recoveryPenalty = 0.02
  default:
    recoveryPenalty = 0.0
  }
  let implausiblePenalty = hasLetters && hasDigits ? 0.0 : 0.35
  return candidate.confidence * 0.48 +
    candidate.patternScore * 0.34 +
    lengthScore * 0.14 +
    layoutBonus -
    recoveryPenalty -
    implausiblePenalty
}

private func matchesNativeRegex(_ text: String, pattern: String) -> Bool {
  text.range(of: pattern, options: .regularExpression) != nil
}

private func isNativeAsciiLetter(_ character: Character) -> Bool {
  character.unicodeScalars.count == 1 &&
    character.unicodeScalars.allSatisfy { (65...90).contains(Int($0.value)) || (97...122).contains(Int($0.value)) }
}

private func isNativeAsciiDigit(_ character: Character) -> Bool {
  character.unicodeScalars.count == 1 &&
    character.unicodeScalars.allSatisfy { (48...57).contains(Int($0.value)) }
}

private struct NativeDetection {
  let bbox: NativeBbox
  let confidence: Double
  let detectorConfidence: Double
  let motionScore: Double
  let qualityScore: Double
  let qualityClass: String
}

private struct NativeBbox {
  let x: Double
  let y: Double
  let width: Double
  let height: Double

  func iou(_ other: NativeBbox) -> Double {
    let left = max(x, other.x)
    let top = max(y, other.y)
    let right = min(x + width, other.x + other.width)
    let bottom = min(y + height, other.y + other.height)
    let intersection = max(0.0, right - left) * max(0.0, bottom - top)
    let union = width * height + other.width * other.height - intersection
    return union <= 0.0 ? 0.0 : intersection / union
  }

  func toMap() -> [String: Any] {
    [
      "x": x,
      "y": y,
      "width": width,
      "height": height,
    ]
  }
}

private struct NativeEvidencePaths {
  let vehicleImagePath: String
  let plateImagePath: String
  let plateEnhancedImagePath: String
  let plateBinaryImagePath: String
  let plateTopLineImagePath: String
  let plateBottomLineImagePath: String
  let plateInnerTextImagePath: String
  let plateCropWidth: Int
  let plateCropHeight: Int
  let preprocessingVariant: String
  let preprocessingVariants: [String]
}

private final class NativeEvidenceFrame {
  private static let ciContext = CIContext()
  private let image: UIImage

  private init(image: UIImage) {
    self.image = image
  }

  func release() {}

  func copyFrame() -> NativeEvidenceFrame? {
    NativeEvidenceFrame(image: image)
  }

  static func fromPixelBuffer(_ pixelBuffer: CVPixelBuffer, maxLongEdge: CGFloat = 640) -> NativeEvidenceFrame? {
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    let extent = ciImage.extent.integral
    guard let cgImage = ciContext.createCGImage(ciImage, from: extent) else {
      return nil
    }
    let source = UIImage(cgImage: cgImage)
    let longest = max(source.size.width, source.size.height)
    guard longest > 0 else { return nil }
    let scale = min(1, maxLongEdge / longest)
    let targetSize = CGSize(
      width: max(1, source.size.width * scale),
      height: max(1, source.size.height * scale)
    )
    let renderer = UIGraphicsImageRenderer(size: targetSize)
    let resized = renderer.image { _ in
      source.draw(in: CGRect(origin: .zero, size: targetSize))
    }
    return NativeEvidenceFrame(image: resized)
  }

  func recognizePlate(
    ortRuntime: PlateqOrtRuntime,
    bbox: NativeBbox,
    qualityClass: String
  ) -> NativeOcrResult? {
    let plateCrop = crop(bbox)
    var candidates: [NativeOcrResult] = []
    let enhancedCrop = enhancePlateCrop(plateCrop)
    let aspect = enhancedCrop.size.width / max(1.0, enhancedCrop.size.height)
    let baseLayout: String
    if aspect < 1.6 {
      baseLayout = "SQUARE"
    } else if aspect < 2.3 {
      baseLayout = "TWO_LINE"
    } else {
      baseLayout = "SINGLE_LINE"
    }

    recognizeCandidate(
      ortRuntime: ortRuntime,
      crop: enhancedCrop,
      preprocessingVariant: "ADAPTIVE_CONTRAST",
      layout: baseLayout,
      candidates: &candidates
    )

    let textCrop = innerTextCrop(enhancedCrop)
    recognizeCandidate(
      ortRuntime: ortRuntime,
      crop: textCrop,
      preprocessingVariant: "INNER_TEXT",
      layout: baseLayout,
      candidates: &candidates
    )

    if baseLayout != "SINGLE_LINE",
       let twoLineCandidate = recognizeTwoLineCandidate(ortRuntime: ortRuntime, source: enhancedCrop, layout: baseLayout) {
      candidates.append(twoLineCandidate)
    }

    let bestFirstPass = candidates.max { rankNativeOcrCandidate($0) < rankNativeOcrCandidate($1) }
    let needsRecovery = bestFirstPass == nil ||
      (bestFirstPass?.confidence ?? 0.0) < 0.42 ||
      (bestFirstPass?.patternScore ?? 0.0) < 0.42
    let shouldDeskew = qualityClass == "SLIGHT_ROTATION" || aspect < 2.0 || aspect > 5.8
    if shouldDeskew {
      for degrees in [-6.0, 6.0] {
        let deskewed = rotatePlateCrop(enhancedCrop, degrees: -degrees)
        recognizeCandidate(
          ortRuntime: ortRuntime,
          crop: deskewed,
          preprocessingVariant: "DESKEWED_ROTATION",
          layout: baseLayout,
          candidates: &candidates
        )
      }
    }

    if needsRecovery {
      let rotated = rotatePlateCrop(enhancedCrop, degrees: 180.0)
      recognizeCandidate(
        ortRuntime: ortRuntime,
        crop: rotated,
        preprocessingVariant: "ROTATE_180",
        layout: baseLayout,
        candidates: &candidates
      )
    }

    return candidates
      .filter { $0.normalizedPlate.count >= 2 }
      .max { rankNativeOcrCandidate($0) < rankNativeOcrCandidate($1) }
  }

  func writeEvidenceFiles(cacheDirectory: URL, trackNumber: Int, bbox: NativeBbox, frameNumber: Int) -> NativeEvidencePaths? {
    let prefix = "track-\(trackNumber)-\(frameNumber)-\(Int(Date().timeIntervalSince1970 * 1000))"
    let vehicleUrl = cacheDirectory.appendingPathComponent("\(prefix)-vehicle.jpg")
    let plateUrl = cacheDirectory.appendingPathComponent("\(prefix)-plate.jpg")
    let enhancedPlateUrl = cacheDirectory.appendingPathComponent("\(prefix)-plate-enhanced.jpg")
    let binaryPlateUrl = cacheDirectory.appendingPathComponent("\(prefix)-plate-binary.jpg")
    let topLinePlateUrl = cacheDirectory.appendingPathComponent("\(prefix)-plate-top-line.jpg")
    let bottomLinePlateUrl = cacheDirectory.appendingPathComponent("\(prefix)-plate-bottom-line.jpg")
    let innerTextPlateUrl = cacheDirectory.appendingPathComponent("\(prefix)-plate-inner-text.jpg")
    let plateCrop = crop(bbox)
    let enhancedCrop = enhancePlateCrop(plateCrop)
    let binaryCrop = binarizePlateCrop(enhancedCrop)
    let topLineCrop = splitPlateCrop(enhancedCrop, topHalf: true)
    let bottomLineCrop = splitPlateCrop(enhancedCrop, topHalf: false)
    let innerTextCrop = innerTextCrop(enhancedCrop)
    guard let vehicleData = image.jpegData(compressionQuality: 0.82),
          let plateData = plateCrop.jpegData(compressionQuality: 0.90),
          let enhancedPlateData = enhancedCrop.jpegData(compressionQuality: 0.92),
          let binaryPlateData = binaryCrop.jpegData(compressionQuality: 0.92),
          let topLinePlateData = topLineCrop.jpegData(compressionQuality: 0.92),
          let bottomLinePlateData = bottomLineCrop.jpegData(compressionQuality: 0.92),
          let innerTextPlateData = innerTextCrop.jpegData(compressionQuality: 0.92) else {
      return nil
    }
    do {
      try vehicleData.write(to: vehicleUrl, options: .atomic)
      try plateData.write(to: plateUrl, options: .atomic)
      try enhancedPlateData.write(to: enhancedPlateUrl, options: .atomic)
      try binaryPlateData.write(to: binaryPlateUrl, options: .atomic)
      try topLinePlateData.write(to: topLinePlateUrl, options: .atomic)
      try bottomLinePlateData.write(to: bottomLinePlateUrl, options: .atomic)
      try innerTextPlateData.write(to: innerTextPlateUrl, options: .atomic)
      return NativeEvidencePaths(
        vehicleImagePath: vehicleUrl.path,
        plateImagePath: plateUrl.path,
        plateEnhancedImagePath: enhancedPlateUrl.path,
        plateBinaryImagePath: binaryPlateUrl.path,
        plateTopLineImagePath: topLinePlateUrl.path,
        plateBottomLineImagePath: bottomLinePlateUrl.path,
        plateInnerTextImagePath: innerTextPlateUrl.path,
        plateCropWidth: Int(plateCrop.size.width.rounded()),
        plateCropHeight: Int(plateCrop.size.height.rounded()),
        preprocessingVariant: "ADAPTIVE_CONTRAST",
        preprocessingVariants: [
          "RAW_CROP",
          "ADAPTIVE_CONTRAST",
          "BINARY_THRESHOLD",
          "TOP_LINE",
          "BOTTOM_LINE",
          "INNER_TEXT",
        ]
      )
    } catch {
      return nil
    }
  }

  private func recognizeCandidate(
    ortRuntime: PlateqOrtRuntime,
    crop: UIImage,
    preprocessingVariant: String,
    layout: String,
    candidates: inout [NativeOcrResult]
  ) {
    if let result = ortRuntime.recognizePlateCrop(
      crop: crop,
      preprocessingVariant: preprocessingVariant,
      layout: layout
    ) {
      candidates.append(result)
    }
  }

  private func recognizeTwoLineCandidate(
    ortRuntime: PlateqOrtRuntime,
    source: UIImage,
    layout: String
  ) -> NativeOcrResult? {
    let topLineCrop = splitPlateCrop(source, topHalf: true)
    let bottomLineCrop = splitPlateCrop(source, topHalf: false)
    let top = ortRuntime.recognizePlateCrop(
      crop: topLineCrop,
      preprocessingVariant: "TOP_LINE",
      layout: "TWO_LINE"
    )
    let bottom = ortRuntime.recognizePlateCrop(
      crop: bottomLineCrop,
      preprocessingVariant: "BOTTOM_LINE",
      layout: "TWO_LINE"
    )
    let rawText = (top?.normalizedPlate ?? "") + (bottom?.normalizedPlate ?? "")
    let normalized = normalizeNativePlate(rawText)
    guard normalized.count >= 2 else { return nil }
    let confidenceValues = [top?.confidence, bottom?.confidence].compactMap { $0 }
    let confidence = roundMetric(
      confidenceValues.isEmpty
        ? 0.0
        : confidenceValues.reduce(0.0, +) / Double(confidenceValues.count)
    )
    let split = top?.normalizedPlate.count ?? 0
    return NativeOcrResult(
      rawText: rawText,
      normalizedPlate: normalized,
      confidence: confidence,
      characterConfidences: normalized.enumerated().map { index, character in
        NativeOcrCharacterConfidence(
          char: String(character),
          confidence: index < split ? (top?.confidence ?? confidence) : (bottom?.confidence ?? confidence),
          position: index
        )
      },
      layout: layout,
      category: nativePlateCategory(normalized),
      patternScore: nativePatternScore(normalized),
      provider: "CPU_ONNX_PP_OCR",
      preprocessingVariant: "TWO_LINE_SPLIT"
    )
  }

  private func crop(_ bbox: NativeBbox) -> UIImage {
    let width = image.size.width
    let height = image.size.height
    let left = clamp(bbox.x * width, 0.0, max(0.0, width - 2.0))
    let top = clamp(bbox.y * height, 0.0, max(0.0, height - 2.0))
    let right = clamp((bbox.x + bbox.width) * width, left + 1.0, width)
    let bottom = clamp((bbox.y + bbox.height) * height, top + 1.0, height)
    let cropRect = CGRect(x: left, y: top, width: max(1, right - left), height: max(1, bottom - top))
    guard let cgImage = image.cgImage?.cropping(to: cropRect) else {
      return image
    }
    return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
  }

  private func binarizePlateCrop(_ source: UIImage) -> UIImage {
    guard let cgImage = source.cgImage else { return source }
    let width = cgImage.width
    let height = cgImage.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: max(1, height * bytesPerRow))
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
      data: &pixels,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return source
    }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    var total = 0
    for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
      total += lumaValue(red: pixels[index], green: pixels[index + 1], blue: pixels[index + 2])
    }
    let threshold = total / max(1, width * height)
    for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
      let luma = lumaValue(red: pixels[index], green: pixels[index + 1], blue: pixels[index + 2])
      let value: UInt8 = luma >= threshold ? 255 : 0
      pixels[index] = value
      pixels[index + 1] = value
      pixels[index + 2] = value
      pixels[index + 3] = 255
    }
    guard let outputContext = CGContext(
      data: &pixels,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ),
      let output = outputContext.makeImage() else {
      return source
    }
    return UIImage(cgImage: output, scale: source.scale, orientation: source.imageOrientation)
  }

  private func lumaValue(red: UInt8, green: UInt8, blue: UInt8) -> Int {
    let redValue = Double(red) * 0.299
    let greenValue = Double(green) * 0.587
    let blueValue = Double(blue) * 0.114
    return Int(redValue + greenValue + blueValue)
  }

  private func splitPlateCrop(_ source: UIImage, topHalf: Bool) -> UIImage {
    let cropHeight = max(1.0, source.size.height / 2.0)
    let top = topHalf ? 0.0 : max(0.0, source.size.height - cropHeight)
    return cropImage(source, rect: CGRect(x: 0, y: top, width: source.size.width, height: cropHeight))
  }

  private func innerTextCrop(_ source: UIImage) -> UIImage {
    let insetX = min(source.size.width / 4.0, max(1.0, source.size.width * 0.06))
    let insetY = min(source.size.height / 3.0, max(1.0, source.size.height * 0.14))
    return cropImage(
      source,
      rect: CGRect(
        x: insetX,
        y: insetY,
        width: max(1.0, source.size.width - insetX * 2.0),
        height: max(1.0, source.size.height - insetY * 2.0)
      )
    )
  }

  private func cropImage(_ source: UIImage, rect: CGRect) -> UIImage {
    guard let cgImage = source.cgImage?.cropping(to: rect.integral) else {
      return source
    }
    return UIImage(cgImage: cgImage, scale: source.scale, orientation: source.imageOrientation)
  }

  private func enhancePlateCrop(_ source: UIImage) -> UIImage {
    guard let input = CIImage(image: source),
          let filter = CIFilter(name: "CIColorControls") else {
      return source
    }
    filter.setValue(input, forKey: kCIInputImageKey)
    filter.setValue(0.0, forKey: kCIInputSaturationKey)
    filter.setValue(1.35, forKey: kCIInputContrastKey)
    filter.setValue(0.03, forKey: kCIInputBrightnessKey)
    guard let output = filter.outputImage,
          let cgImage = NativeEvidenceFrame.ciContext.createCGImage(output, from: input.extent) else {
      return source
    }
    return UIImage(cgImage: cgImage, scale: source.scale, orientation: source.imageOrientation)
  }

  private func rotatePlateCrop(_ source: UIImage, degrees: Double) -> UIImage {
    let size = source.size
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
      UIColor.black.setFill()
      context.fill(CGRect(origin: .zero, size: size))
      let cgContext = context.cgContext
      cgContext.translateBy(x: size.width / 2.0, y: size.height / 2.0)
      cgContext.rotate(by: CGFloat(degrees * Double.pi / 180.0))
      source.draw(
        in: CGRect(
          x: -size.width / 2.0,
          y: -size.height / 2.0,
          width: size.width,
          height: size.height
        )
      )
    }
  }
}

private struct NativeFrameAnalysis {
  let detections: [NativeDetection]
  let detectorConfidence: Double
  let environmentLabel: String
  let environmentConfidence: Double
  let brightness: Double
  let contrast: Double
  let glareRatio: Double
  let qualityScore: Double
  let qualityClass: String
}

private enum NativeFrameAnalyzer {
  static func analyze(
    pixelBuffer: CVPixelBuffer,
    frameNumber: Int,
    threshold: Double,
    ortRuntime: PlateqOrtRuntime
  ) -> NativeFrameAnalysis {
    let stats = sampleLuma(pixelBuffer)
    let environment = classifyEnvironment(stats)
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let onnxDetections = ortRuntime.detectPlates(pixelBuffer: pixelBuffer, minConfidence: threshold)
    let detectorConfidence = onnxDetections.map(\.confidence).max() ?? 0.0
    let qualityScore = onnxDetections.map { detection in
      roundMetric(
        clamp01(
          detection.confidence * 0.34 +
            stats.exposureScore * 0.18 +
            stats.contrastScore * 0.20 +
            stats.sharpnessScore * 0.14 +
            boxSizeScore(detection.bbox) * 0.14 -
            stats.glareRatio * 0.22
        )
      )
    }.max() ?? 0.0
    let qualityClass = onnxDetections.isEmpty
      ? "TOO_SMALL"
      : classifyQuality(stats: stats, qualityScore: qualityScore)
    let detections = onnxDetections.map { detection in
      let perBoxQualityScore = roundMetric(
        clamp01(
          detection.confidence * 0.34 +
            stats.exposureScore * 0.18 +
            stats.contrastScore * 0.20 +
            stats.sharpnessScore * 0.14 +
            boxSizeScore(detection.bbox) * 0.14 -
            stats.glareRatio * 0.22
        )
      )
      return NativeDetection(
        bbox: detection.bbox,
        confidence: perBoxQualityScore,
        detectorConfidence: detection.confidence,
        motionScore: stats.motionScore,
        qualityScore: perBoxQualityScore,
        qualityClass: classifyQuality(stats: stats, qualityScore: perBoxQualityScore)
      )
    }

    return NativeFrameAnalysis(
      detections: detections,
      detectorConfidence: detectorConfidence,
      environmentLabel: environment.label,
      environmentConfidence: environment.confidence,
      brightness: roundMetric(stats.brightness),
      contrast: roundMetric(stats.contrast),
      glareRatio: roundMetric(stats.glareRatio),
      qualityScore: qualityScore,
      qualityClass: qualityClass
    )
  }

  private static func sampleLuma(_ pixelBuffer: CVPixelBuffer) -> LumaStats {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    let planeCount = CVPixelBufferGetPlaneCount(pixelBuffer)
    let width = planeCount > 0 ? CVPixelBufferGetWidthOfPlane(pixelBuffer, 0) : CVPixelBufferGetWidth(pixelBuffer)
    let height = planeCount > 0 ? CVPixelBufferGetHeightOfPlane(pixelBuffer, 0) : CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = planeCount > 0 ? CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0) : CVPixelBufferGetBytesPerRow(pixelBuffer)
    let baseAddress = planeCount > 0 ? CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) : CVPixelBufferGetBaseAddress(pixelBuffer)

    guard let baseAddress else { return .empty }
    let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
    let stepY = max(1, height / 72)
    let stepX = max(1, width / 96)
    var sum = 0.0
    var sumSquares = 0.0
    var count = 0
    var bright = 0
    var dark = 0
    var edge = 0.0
    var edgeCount = 0
    var previous = -1

    var y = 0
    while y < height {
      let row = y * bytesPerRow
      var x = 0
      while x < width {
        let value = Int(bytes[row + x])
        let doubleValue = Double(value)
        sum += doubleValue
        sumSquares += doubleValue * doubleValue
        if value > 242 { bright += 1 }
        if value < 28 { dark += 1 }
        if previous >= 0 {
          edge += Double(abs(value - previous))
          edgeCount += 1
        }
        previous = value
        count += 1
        x += stepX
      }
      y += stepY
    }

    guard count > 0 else { return .empty }
    let meanRaw = sum / Double(count)
    let variance = max(0.0, sumSquares / Double(count) - meanRaw * meanRaw)
    let standardDeviation = sqrt(variance)
    let brightness = meanRaw / 255.0
    let contrast = clamp01(standardDeviation / 96.0)
    let sharpness = clamp01((edge / Double(max(1, edgeCount))) / 48.0)
    return LumaStats(
      brightness: brightness,
      contrast: contrast,
      glareRatio: Double(bright) / Double(count),
      darkRatio: Double(dark) / Double(count),
      exposureScore: clamp01(1.0 - abs(brightness - 0.52) / 0.52),
      contrastScore: contrast,
      sharpnessScore: sharpness,
      motionScore: clamp01(abs(contrast - sharpness) * 0.35)
    )
  }

  private static func classifyEnvironment(_ stats: LumaStats) -> (label: String, confidence: Double) {
    if stats.glareRatio >= 0.10 {
      return ("GLARE", 0.88)
    }
    if stats.glareRatio >= 0.045, stats.brightness >= 0.56 {
      return ("BACKLIGHT", 0.78)
    }
    if stats.brightness <= 0.16 {
      return ("NIGHT", 0.88)
    }
    if stats.brightness <= 0.30 {
      return ("LOW_LIGHT", 0.80)
    }
    if stats.contrast <= 0.16, stats.brightness >= 0.34 {
      return ("FOG", 0.66)
    }
    if stats.brightness >= 0.58, stats.contrast >= 0.24, stats.glareRatio < 0.025 {
      return ("DAY", 0.74)
    }
    if stats.brightness >= 0.38, stats.contrast >= 0.22, stats.sharpnessScore >= 0.32 {
      return ("GOOD_CONDITION", 0.72)
    }
    return ("DAY", 0.58)
  }

  private static func classifyQuality(stats: LumaStats, qualityScore: Double) -> String {
    if stats.glareRatio >= 0.10 { return "GLARE_REFLECTION" }
    if stats.brightness <= 0.18 { return "UNDEREXPOSED" }
    if stats.brightness >= 0.88 { return "OVEREXPOSED" }
    if stats.contrast <= 0.16 { return "LOW_CONTRAST" }
    if stats.sharpnessScore <= 0.16 { return "OUT_OF_FOCUS" }
    if qualityScore >= 0.72 { return "STANDARD_RECTANGLE" }
    if qualityScore >= 0.52 { return "SLIGHT_ROTATION" }
    return "LOW_CONTRAST"
  }

  private static func boxSizeScore(_ box: NativeBbox) -> Double {
    clamp01((box.width * box.height) / 0.045)
  }
}

private struct LumaStats {
  let brightness: Double
  let contrast: Double
  let glareRatio: Double
  let darkRatio: Double
  let exposureScore: Double
  let contrastScore: Double
  let sharpnessScore: Double
  let motionScore: Double

  static let empty = LumaStats(
    brightness: 0.0,
    contrast: 0.0,
    glareRatio: 0.0,
    darkRatio: 1.0,
    exposureScore: 0.0,
    contrastScore: 0.0,
    sharpnessScore: 0.0,
    motionScore: 0.0
  )
}

private final class NativeTrackEngine {
  private var tracks: [NativeTrack] = []
  private var nextTrackNumber = 1

  func reset() {
    tracks.forEach { $0.release() }
    tracks.removeAll()
    nextTrackNumber = 1
  }

  func update(
    detections: [NativeDetection],
    evidenceFrame: NativeEvidenceFrame?,
    frameNumber: Int,
    timestampMs: Int,
    maxTracks: Int
  ) {
    guard !detections.isEmpty else {
      evidenceFrame?.release()
      ageTracks(frameNumber: frameNumber, timestampMs: timestampMs)
      return
    }

    let maxActiveTracks = max(1, maxTracks)
    let sortedDetections = Array(
      detections
        .sorted { ($0.detectorConfidence * 0.70 + $0.qualityScore * 0.30) > ($1.detectorConfidence * 0.70 + $1.qualityScore * 0.30) }
        .prefix(maxActiveTracks)
    )
    var usedDetectionIndices = Set<Int>()

    for track in tracks.filter({ $0.state != "REMOVED" }).sorted(by: { $0.confidence > $1.confidence }) {
      var bestIndex = -1
      var bestIou = 0.0
      for (index, detection) in sortedDetections.enumerated() where !usedDetectionIndices.contains(index) {
        let iou = track.bbox.iou(detection.bbox)
        if iou >= 0.20, iou > bestIou {
          bestIndex = index
          bestIou = iou
        }
      }
      if bestIndex >= 0 {
        track.applyDetection(
          sortedDetections[bestIndex],
          evidenceFrame: evidenceFrame?.copyFrame(),
          frameNumber: frameNumber,
          timestampMs: timestampMs
        )
        usedDetectionIndices.insert(bestIndex)
      }
    }

    for (index, detection) in sortedDetections.enumerated() where !usedDetectionIndices.contains(index) {
      let frameCopy = evidenceFrame?.copyFrame()
      if tracks.count < maxActiveTracks {
        tracks.append(
          NativeTrack(
            number: nextTrackNumber,
            detection: detection,
            evidenceFrame: frameCopy,
            frameNumber: frameNumber,
            timestampMs: timestampMs
          )
        )
        nextTrackNumber += 1
      } else if let weakest = tracks.filter({ $0.state != "REMOVED" }).min(by: { $0.confidence < $1.confidence }),
                detection.confidence > weakest.confidence {
        weakest.replaceWith(
          number: nextTrackNumber,
          detection: detection,
          evidenceFrame: frameCopy,
          frameNumber: frameNumber,
          timestampMs: timestampMs
        )
        nextTrackNumber += 1
      } else {
        frameCopy?.release()
      }
    }

    evidenceFrame?.release()
    ageTracks(frameNumber: frameNumber, timestampMs: timestampMs)
  }

  func snapshot() -> [[String: Any]] {
    tracks
      .filter { $0.state != "REMOVED" }
      .sorted { $0.trackNumber < $1.trackNumber }
      .map { $0.toMap() }
  }

  func ocrCandidates(frameNumber: Int, maxCount: Int) -> [NativeTrack] {
    Array(
      tracks
        .filter { $0.shouldEmitOcr(frameNumber: frameNumber) }
        .sorted { $0.qualityScore > $1.qualityScore }
        .prefix(max(1, maxCount))
    )
  }

  private func ageTracks(frameNumber: Int, timestampMs: Int) {
    tracks.forEach { $0.age(frameNumber: frameNumber, timestampMs: timestampMs) }
    tracks.removeAll { track in
      if track.state == "REMOVED" {
        track.release()
        return true
      }
      return false
    }
  }
}

private final class NativeTrack {
  var trackNumber: Int
  var bbox: NativeBbox
  var state = "VISIBLE"
  var pipelineState = "COLLECTING"
  var confidence: Double
  var detectorConfidence: Double
  private var motionScore: Double
  var qualityScore: Double
  private var qualityClass: String
  private var currentPlate = ""
  private var currentPlateConfidence = 0.0
  private var firstFrame: Int
  private var lastSeenFrame: Int
  private var lastSeenMs: Int
  private var detectionCount = 1
  private var lastOcrFrame = -9999
  private var ocrEmissionCount = 0

  private var bestEvidenceFrame: NativeEvidenceFrame?
  private var bestEvidenceBbox: NativeBbox
  private var bestEvidenceScore: Double

  init(
    number: Int,
    detection: NativeDetection,
    evidenceFrame: NativeEvidenceFrame?,
    frameNumber: Int,
    timestampMs: Int
  ) {
    trackNumber = number
    bbox = detection.bbox
    confidence = detection.confidence
    detectorConfidence = detection.detectorConfidence
    motionScore = detection.motionScore
    qualityScore = detection.qualityScore
    qualityClass = detection.qualityClass
    firstFrame = frameNumber
    lastSeenFrame = frameNumber
    lastSeenMs = timestampMs
    bestEvidenceFrame = evidenceFrame
    bestEvidenceBbox = detection.bbox
    bestEvidenceScore = NativeTrack.evidenceScore(detection: detection, detectionCount: detectionCount)
  }

  func applyDetection(
    _ detection: NativeDetection,
    evidenceFrame: NativeEvidenceFrame?,
    frameNumber: Int,
    timestampMs: Int
  ) {
    bbox = smooth(previous: bbox, next: detection.bbox)
    state = "VISIBLE"
    pipelineState = detectionCount >= 2 && detection.qualityScore >= 0.52 ? "READY_FOR_OCR" : "COLLECTING"
    confidence = roundMetric(max(confidence * 0.85, detection.confidence))
    detectorConfidence = detection.detectorConfidence
    motionScore = detection.motionScore
    qualityScore = detection.qualityScore
    qualityClass = detection.qualityClass
    lastSeenFrame = frameNumber
    lastSeenMs = timestampMs
    detectionCount += 1
    retainBestEvidence(detection: detection, evidenceFrame: evidenceFrame)
  }

  func replaceWith(
    number: Int,
    detection: NativeDetection,
    evidenceFrame: NativeEvidenceFrame?,
    frameNumber: Int,
    timestampMs: Int
  ) {
    release()
    trackNumber = number
    bbox = detection.bbox
    state = "VISIBLE"
    pipelineState = "COLLECTING"
    confidence = detection.confidence
    detectorConfidence = detection.detectorConfidence
    motionScore = detection.motionScore
    qualityScore = detection.qualityScore
    qualityClass = detection.qualityClass
    firstFrame = frameNumber
    lastSeenFrame = frameNumber
    lastSeenMs = timestampMs
    detectionCount = 1
    currentPlate = ""
    currentPlateConfidence = 0.0
    lastOcrFrame = -9999
    ocrEmissionCount = 0
    bestEvidenceFrame = evidenceFrame
    bestEvidenceBbox = detection.bbox
    bestEvidenceScore = NativeTrack.evidenceScore(detection: detection, detectionCount: detectionCount)
  }

  func age(frameNumber: Int, timestampMs: Int) {
    let missedFrames = frameNumber - lastSeenFrame
    let elapsedMs = timestampMs - lastSeenMs
    if elapsedMs > 1200 || missedFrames > 24 {
      state = "REMOVED"
    } else if missedFrames > 2 {
      state = "LOST"
      pipelineState = "PREDICTING"
      confidence = roundMetric(confidence * 0.92)
    }
  }

  func toMap() -> [String: Any] {
    [
      "trackId": "track-\(trackNumber)",
      "trackNumber": trackNumber,
      "state": state,
      "pipelineState": pipelineState,
      "bbox": bbox.toMap(),
      "confidence": confidence,
      "detectorConfidence": detectorConfidence,
      "motionScore": motionScore,
      "qualityScore": qualityScore,
      "qualityClass": qualityClass,
      "currentPlate": currentPlate,
      "currentPlateConfidence": currentPlateConfidence,
      "matchType": "NONE",
      "ageFrames": lastSeenFrame - firstFrame + 1,
      "detections": detectionCount,
    ]
  }

  func shouldEmitOcr(frameNumber: Int) -> Bool {
    if state != "VISIBLE" { return false }
    if pipelineState != "READY_FOR_OCR" { return false }
    if confidence < 0.48 || qualityScore < 0.38 { return false }
    let interval = ocrEmissionCount == 0 ? 0 : 9
    return frameNumber - lastOcrFrame >= interval
  }

  func markOcr(plate: String, confidence: Double, frameNumber: Int) {
    currentPlate = plate
    currentPlateConfidence = confidence
    lastOcrFrame = frameNumber
    ocrEmissionCount += 1
    pipelineState = "OCR_CONFIRMED"
  }

  func markOcrAttempt(frameNumber: Int) {
    lastOcrFrame = frameNumber
    ocrEmissionCount += 1
  }

  func writeBestEvidenceFiles(cacheDirectory: URL, frameNumber: Int) -> NativeEvidencePaths? {
    bestEvidenceFrame?.writeEvidenceFiles(
      cacheDirectory: cacheDirectory,
      trackNumber: trackNumber,
      bbox: bestEvidenceBbox,
      frameNumber: frameNumber
    )
  }

  func recognizeBestPlate(ortRuntime: PlateqOrtRuntime) -> NativeOcrResult? {
    bestEvidenceFrame?.recognizePlate(
      ortRuntime: ortRuntime,
      bbox: bestEvidenceBbox,
      qualityClass: qualityClass
    )
  }

  func release() {
    bestEvidenceFrame?.release()
    bestEvidenceFrame = nil
  }

  private func retainBestEvidence(detection: NativeDetection, evidenceFrame: NativeEvidenceFrame?) {
    guard let evidenceFrame else { return }
    let candidateScore = NativeTrack.evidenceScore(detection: detection, detectionCount: detectionCount)
    if bestEvidenceFrame == nil || candidateScore >= bestEvidenceScore {
      bestEvidenceFrame?.release()
      bestEvidenceFrame = evidenceFrame
      bestEvidenceBbox = detection.bbox
      bestEvidenceScore = candidateScore
    } else {
      evidenceFrame.release()
    }
  }

  private static func evidenceScore(detection: NativeDetection, detectionCount: Int) -> Double {
    let stability = clamp01(Double(detectionCount) / 4.0)
    let sizeScore = clamp01(detection.bbox.width * detection.bbox.height / 0.045)
    return roundMetric(
      detection.qualityScore * 0.42 +
        detection.detectorConfidence * 0.28 +
        sizeScore * 0.18 +
        stability * 0.12
    )
  }

  private func smooth(previous: NativeBbox, next: NativeBbox) -> NativeBbox {
    let keep = 0.72
    let add = 1.0 - keep
    return NativeBbox(
      x: roundMetric(previous.x * keep + next.x * add),
      y: roundMetric(previous.y * keep + next.y * add),
      width: roundMetric(previous.width * keep + next.width * add),
      height: roundMetric(previous.height * keep + next.height * add)
    )
  }
}

private func clamp01(_ value: Double) -> Double {
  clamp(value, 0.0, 1.0)
}

private func clamp(_ value: Double, _ minValue: Double, _ maxValue: Double) -> Double {
  min(maxValue, max(minValue, value))
}

private func roundMetric(_ value: Double) -> Double {
  (value * 1000.0).rounded() / 1000.0
}

final class PlateqSessionStore {
  private let service = "plateq.auth"
  private let account = "session"

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getSession":
      result(readSession())
    case "saveSession":
      let args = call.arguments as? [String: Any]
      saveSession(args?["session"] as? String ?? "")
      result(nil)
    case "clearSession":
      clearSession()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func readSession() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
          let data = item as? Data else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  private func saveSession(_ raw: String) {
    clearSession()
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: Data(raw.utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    SecItemAdd(query as CFDictionary, nil)
  }

  private func clearSession() {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(query as CFDictionary)
  }
}

final class PlateqShareService: NSObject, UIDocumentPickerDelegate {
  private var pickerResult: FlutterResult?

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "shareText":
      let args = call.arguments as? [String: Any]
      let text = args?["text"] as? String ?? ""
      let title = args?["title"] as? String ?? "Share"
      DispatchQueue.main.async {
        guard let controller = self.topViewController() else {
          result(false)
          return
        }
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        activity.title = title
        activity.popoverPresentationController?.sourceView = controller.view
        activity.popoverPresentationController?.sourceRect = CGRect(
          x: controller.view.bounds.midX,
          y: controller.view.bounds.midY,
          width: 0,
          height: 0
        )
        controller.present(activity, animated: true) {
          result(true)
        }
      }
    case "pickCsv":
      DispatchQueue.main.async {
        guard self.pickerResult == nil else {
          result(FlutterError(code: "PICKER_BUSY", message: "A CSV picker is already open.", details: nil))
          return
        }
        guard let controller = self.topViewController() else {
          result(FlutterError(code: "PICKER_UNAVAILABLE", message: "Unable to open the CSV picker.", details: nil))
          return
        }
        self.pickerResult = result
        let picker = UIDocumentPickerViewController(
          documentTypes: [
            "public.comma-separated-values-text",
            "public.plain-text",
            "public.text",
            "public.data",
          ],
          in: .import
        )
        picker.delegate = self
        picker.allowsMultipleSelection = false
        controller.present(picker, animated: true)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pickerResult?(nil)
    pickerResult = nil
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = pickerResult else { return }
    pickerResult = nil
    guard let url = urls.first else {
      result(nil)
      return
    }

    let scoped = url.startAccessingSecurityScopedResource()
    defer {
      if scoped {
        url.stopAccessingSecurityScopedResource()
      }
    }
    do {
      let data = try Data(contentsOf: url)
      if let csv = String(data: data, encoding: .utf8) ??
        String(data: data, encoding: .isoLatin1) {
        result(csv)
      } else {
        result(FlutterError(code: "CSV_READ", message: "Unable to decode selected CSV file.", details: nil))
      }
    } catch {
      result(FlutterError(code: "CSV_READ", message: "Unable to read selected CSV file.", details: error.localizedDescription))
    }
  }

  private func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    var controller = scene?.windows.first { $0.isKeyWindow }?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    return controller
  }
}

final class PlateqAppStorage {
  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "readJson":
      guard let key = validatedKey(from: call.arguments, result: result) else { return }
      do {
        let file = try storageFile(for: key)
        guard FileManager.default.fileExists(atPath: file.path) else {
          result(nil)
          return
        }
        result(try String(contentsOf: file, encoding: .utf8))
      } catch {
        result(FlutterError(code: "STORAGE_READ", message: "Unable to read local app storage.", details: error.localizedDescription))
      }
    case "writeJson":
      guard let key = validatedKey(from: call.arguments, result: result) else { return }
      let args = call.arguments as? [String: Any]
      let rawJson = args?["json"] as? String ?? ""
      do {
        let file = try storageFile(for: key)
        try rawJson.write(to: file, atomically: true, encoding: .utf8)
        result(true)
      } catch {
        result(FlutterError(code: "STORAGE_WRITE", message: "Unable to write local app storage.", details: error.localizedDescription))
      }
    case "clearJson":
      guard let key = validatedKey(from: call.arguments, result: result) else { return }
      do {
        let file = try storageFile(for: key)
        if FileManager.default.fileExists(atPath: file.path) {
          try FileManager.default.removeItem(at: file)
        }
        result(true)
      } catch {
        result(FlutterError(code: "STORAGE_CLEAR", message: "Unable to clear local app storage.", details: error.localizedDescription))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func validatedKey(from arguments: Any?, result: FlutterResult) -> String? {
    let args = arguments as? [String: Any]
    let key = args?["key"] as? String ?? ""
    if key.range(of: "^[A-Za-z0-9._-]{1,64}$", options: .regularExpression) == nil {
      result(FlutterError(code: "STORAGE_KEY", message: "Storage key must be 1-64 URL-safe characters.", details: nil))
      return nil
    }
    return key
  }

  private func storageFile(for key: String) throws -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
      FileManager.default.temporaryDirectory
    let directory = base.appendingPathComponent("plateq-storage", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("\(key).json", isDirectory: false)
  }
}

final class PlateqModelStaging {
  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "stageModelAsset":
      guard let id = validatedId(from: call.arguments, result: result) else { return }
      let args = call.arguments as? [String: Any]
      let path = args?["path"] as? String ?? ""
      let required = args?["required"] as? Bool ?? false
      guard let typedData = args?["bytes"] as? FlutterStandardTypedData,
            !typedData.data.isEmpty else {
        result(FlutterError(code: "MODEL_BYTES", message: "Model asset bytes are empty.", details: nil))
        return
      }
      do {
        let file = try modelFile(for: id, assetPath: path)
        try typedData.data.write(to: file, options: .atomic)
        result([
          "id": id,
          "path": path,
          "required": required,
          "available": true,
          "sizeBytes": typedData.data.count,
          "nativePath": file.path,
        ])
      } catch {
        result(FlutterError(code: "MODEL_STAGE", message: "Unable to stage model asset.", details: error.localizedDescription))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func validatedId(from arguments: Any?, result: FlutterResult) -> String? {
    let args = arguments as? [String: Any]
    let id = args?["id"] as? String ?? ""
    if id.range(of: "^[A-Za-z0-9._-]{1,64}$", options: .regularExpression) == nil {
      result(FlutterError(code: "MODEL_ID", message: "Model id must be 1-64 URL-safe characters.", details: nil))
      return nil
    }
    return id
  }

  private func modelFile(for id: String, assetPath: String) throws -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
      FileManager.default.temporaryDirectory
    let directory = base.appendingPathComponent("plateq-models", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fileExtension = URL(fileURLWithPath: assetPath).pathExtension
    let ext = fileExtension.isEmpty ? "bin" : fileExtension
    return directory.appendingPathComponent("\(id).\(ext)", isDirectory: false)
  }
}

final class PlateqCameraPreviewFactory: NSObject, FlutterPlatformViewFactory {
  private let bridge: PlateqNativeBridge

  init(bridge: PlateqNativeBridge) {
    self.bridge = bridge
    super.init()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    PlateqCameraPreviewView(frame: frame, bridge: bridge)
  }
}

final class PlateqCameraPreviewView: NSObject, FlutterPlatformView, AVCaptureVideoDataOutputSampleBufferDelegate {
  private static let sessionQueueKey = DispatchSpecificKey<UInt8>()
  private static let sessionQueueValue: UInt8 = 1

  private let root: PreviewContainerView
  private let bridge: PlateqNativeBridge
  private let session = AVCaptureSession()
  private let sessionQueue = DispatchQueue(label: "plateq.camera.session")
  private let outputQueue = DispatchQueue(label: "plateq.camera.output")

  init(frame: CGRect, bridge: PlateqNativeBridge) {
    self.bridge = bridge
    root = PreviewContainerView(frame: frame)
    super.init()
    sessionQueue.setSpecific(key: Self.sessionQueueKey, value: Self.sessionQueueValue)
    root.backgroundColor = UIColor(red: 0.008, green: 0.024, blue: 0.090, alpha: 1)

    let previewLayer = AVCaptureVideoPreviewLayer(session: session)
    previewLayer.videoGravity = .resizeAspectFill
    root.previewLayer = previewLayer
    root.layer.addSublayer(previewLayer)
    configureSession()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(startSession),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(stopSession),
      name: UIApplication.willResignActiveNotification,
      object: nil
    )
  }

  func view() -> UIView {
    root
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    teardownSession()
  }

  private func configureSession() {
    sessionQueue.async {
      self.session.beginConfiguration()
      self.session.sessionPreset = .high
      self.session.inputs.forEach { self.session.removeInput($0) }
      self.session.outputs.forEach { self.session.removeOutput($0) }

      guard let device = self.bridge.selectedCaptureDevice(),
            let input = try? AVCaptureDeviceInput(device: device),
            self.session.canAddInput(input) else {
        self.session.commitConfiguration()
        return
      }
      self.session.addInput(input)

      if device.isFocusModeSupported(.continuousAutoFocus) || device.isExposureModeSupported(.continuousAutoExposure) {
        try? device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) {
          device.focusMode = .continuousAutoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
          device.exposureMode = .continuousAutoExposure
        }
        device.unlockForConfiguration()
      }

      let output = AVCaptureVideoDataOutput()
      output.alwaysDiscardsLateVideoFrames = true
      output.videoSettings = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
      ]
      output.setSampleBufferDelegate(self, queue: self.outputQueue)
      if self.session.canAddOutput(output) {
        self.session.addOutput(output)
      }
      self.session.commitConfiguration()
      self.startSession()
    }
  }

  @objc private func startSession() {
    let session = session
    sessionQueue.async {
      if !session.isRunning {
        session.startRunning()
      }
    }
  }

  @objc private func stopSession() {
    let session = session
    sessionQueue.async {
      if session.isRunning {
        session.stopRunning()
      }
    }
  }

  private func teardownSession() {
    let session = session
    let cleanup = {
      session.outputs
        .compactMap { $0 as? AVCaptureVideoDataOutput }
        .forEach { $0.setSampleBufferDelegate(nil, queue: nil) }
      if session.isRunning {
        session.stopRunning()
      }
      session.beginConfiguration()
      session.inputs.forEach { session.removeInput($0) }
      session.outputs.forEach { session.removeOutput($0) }
      session.commitConfiguration()
    }

    if DispatchQueue.getSpecific(key: Self.sessionQueueKey) == Self.sessionQueueValue {
      cleanup()
    } else {
      sessionQueue.sync(execute: cleanup)
    }
  }

  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    bridge.recordFrame(sampleBuffer: sampleBuffer)
  }
}

final class PreviewContainerView: UIView {
  var previewLayer: AVCaptureVideoPreviewLayer?

  override func layoutSubviews() {
    super.layoutSubviews()
    previewLayer?.frame = bounds
  }
}
