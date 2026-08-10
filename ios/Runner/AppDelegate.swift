import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var plateqBridge: PlateqNativeBridge?
  private var plateqFileService: PlateqShareService?

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
    plateqBridge = bridge
    plateqFileService = fileService

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

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      requestCameraPermissionIfNeeded()
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
    return [
      "runtimeState": scanning ? "SCANNING" : "READY",
      "deviceTier": "AUTO",
      "detectorProvider": "NATIVE_HEURISTIC",
      "ocrProvider": "PENDING_PHASE_11",
      "environmentProvider": "NATIVE_HEURISTIC",
      "plateQualityProvider": "NATIVE_HEURISTIC",
      "warnings": warnings,
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
      "deviceTier": "AUTO",
      "cameraId": selectedCameraId ?? defaultCameraId(),
      "cameraLabel": listNativeCameras().first { $0["id"] as? String == selectedCameraId }?["label"] as? String ?? "Rear Camera",
      "detectorFps": scanning ? lastDetectorFps : 0.0,
      "cameraFps": scanning ? lastCameraFps : 0.0,
      "ocrQueueDepth": 0,
      "temperatureState": "NOMINAL",
      "memoryMb": 0.0,
      "frameWidth": lastFrameWidth,
      "frameHeight": lastFrameHeight,
      "frameRotation": lastFrameRotation,
      "frameCount": frameCount,
      "detectorProvider": "NATIVE_HEURISTIC",
      "ocrProvider": "PENDING_PHASE_11",
      "environmentProvider": "NATIVE_HEURISTIC",
      "plateQualityProvider": "NATIVE_HEURISTIC",
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
    let analysis = NativeFrameAnalyzer.analyze(
      pixelBuffer: pixelBuffer,
      frameNumber: nextFrame,
      threshold: settingDouble("detectionThreshold", fallback: 0.35)
    )
    DispatchQueue.main.async {
      self.lastFrameWidth = width
      self.lastFrameHeight = height
      self.lastFrameRotation = 0
      self.frameCount += 1
      guard self.scanning else { return }
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
        detection: analysis.detection,
        frameNumber: self.frameCount,
        timestampMs: Int(Date().timeIntervalSince1970 * 1000),
        maxTracks: self.settingInt("maxTracks", fallback: 8)
      )
      if self.frameCount % 3 == 0 {
        self.emitTrackUpdate()
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

private struct NativeFrameAnalysis {
  let detection: NativeDetection?
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
    threshold: Double
  ) -> NativeFrameAnalysis {
    let stats = sampleLuma(pixelBuffer)
    let environment = classifyEnvironment(stats)
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let box = candidateBox(width: width, height: height, frameNumber: frameNumber, stats: stats)
    let detectorConfidence = roundMetric(
      clamp01(
        0.20 +
          stats.exposureScore * 0.30 +
          stats.contrastScore * 0.34 +
          stats.sharpnessScore * 0.10 -
          stats.glareRatio * 0.45 -
          stats.darkRatio * 0.18
      )
    )
    let qualityScore = roundMetric(
      clamp01(
        detectorConfidence * 0.30 +
          stats.exposureScore * 0.20 +
          stats.contrastScore * 0.22 +
          stats.sharpnessScore * 0.16 +
          boxSizeScore(box) * 0.12 -
          stats.glareRatio * 0.22
      )
    )
    let qualityClass = classifyQuality(stats: stats, qualityScore: qualityScore)
    let detection: NativeDetection?
    if detectorConfidence >= max(0.18, threshold * 0.70), qualityScore >= 0.20 {
      detection = NativeDetection(
        bbox: box,
        confidence: qualityScore,
        detectorConfidence: detectorConfidence,
        motionScore: stats.motionScore,
        qualityScore: qualityScore,
        qualityClass: qualityClass
      )
    } else {
      detection = nil
    }

    return NativeFrameAnalysis(
      detection: detection,
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

  private static func candidateBox(
    width: Int,
    height: Int,
    frameNumber: Int,
    stats: LumaStats
  ) -> NativeBbox {
    let frameAspect = max(0.5, Double(width) / Double(max(1, height)))
    let boxWidth = clamp(0.24 + stats.contrast * 0.12 + stats.sharpnessScore * 0.06, 0.24, 0.42)
    let boxHeight = clamp((boxWidth * frameAspect) / 4.6, 0.045, 0.135)
    let drift = (Double(frameNumber % 40) - 20.0) / 6000.0
    let centerX = clamp(0.50 + drift, boxWidth / 2.0, 1.0 - boxWidth / 2.0)
    let centerY = clamp(0.61 + (0.5 - stats.brightness) * 0.08, boxHeight / 2.0, 1.0 - boxHeight / 2.0)
    return NativeBbox(
      x: roundMetric(centerX - boxWidth / 2.0),
      y: roundMetric(centerY - boxHeight / 2.0),
      width: roundMetric(boxWidth),
      height: roundMetric(boxHeight)
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
    tracks.removeAll()
    nextTrackNumber = 1
  }

  func update(detection: NativeDetection?, frameNumber: Int, timestampMs: Int, maxTracks: Int) {
    guard let detection else {
      ageTracks(frameNumber: frameNumber, timestampMs: timestampMs)
      return
    }

    let matched = tracks
      .filter { $0.state != "REMOVED" }
      .max { $0.bbox.iou(detection.bbox) < $1.bbox.iou(detection.bbox) }

    if let matched, matched.bbox.iou(detection.bbox) >= 0.20 {
      matched.applyDetection(detection, frameNumber: frameNumber, timestampMs: timestampMs)
    } else if tracks.count < max(1, maxTracks) {
      tracks.append(NativeTrack(number: nextTrackNumber, detection: detection, frameNumber: frameNumber, timestampMs: timestampMs))
      nextTrackNumber += 1
    } else if let weakest = tracks.min(by: { $0.confidence < $1.confidence }), detection.confidence > weakest.confidence {
      weakest.replaceWith(number: nextTrackNumber, detection: detection, frameNumber: frameNumber, timestampMs: timestampMs)
      nextTrackNumber += 1
    }

    ageTracks(frameNumber: frameNumber, timestampMs: timestampMs)
  }

  func snapshot() -> [[String: Any]] {
    tracks
      .filter { $0.state != "REMOVED" }
      .sorted { $0.trackNumber < $1.trackNumber }
      .map { $0.toMap() }
  }

  private func ageTracks(frameNumber: Int, timestampMs: Int) {
    tracks.forEach { $0.age(frameNumber: frameNumber, timestampMs: timestampMs) }
    tracks.removeAll { $0.state == "REMOVED" }
  }
}

private final class NativeTrack {
  var trackNumber: Int
  var bbox: NativeBbox
  var state = "VISIBLE"
  var pipelineState = "COLLECTING"
  var confidence: Double
  private var detectorConfidence: Double
  private var motionScore: Double
  private var qualityScore: Double
  private var qualityClass: String
  private var firstFrame: Int
  private var lastSeenFrame: Int
  private var lastSeenMs: Int
  private var detectionCount = 1

  init(number: Int, detection: NativeDetection, frameNumber: Int, timestampMs: Int) {
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
  }

  func applyDetection(_ detection: NativeDetection, frameNumber: Int, timestampMs: Int) {
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
  }

  func replaceWith(number: Int, detection: NativeDetection, frameNumber: Int, timestampMs: Int) {
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
      "currentPlate": "",
      "currentPlateConfidence": 0.0,
      "matchType": "NONE",
      "ageFrames": lastSeenFrame - firstFrame + 1,
      "detections": detectionCount,
    ]
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
  private let root: PreviewContainerView
  private let bridge: PlateqNativeBridge
  private let session = AVCaptureSession()
  private let sessionQueue = DispatchQueue(label: "plateq.camera.session")
  private let outputQueue = DispatchQueue(label: "plateq.camera.output")

  init(frame: CGRect, bridge: PlateqNativeBridge) {
    self.bridge = bridge
    root = PreviewContainerView(frame: frame)
    super.init()
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
    stopSession()
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
    sessionQueue.async {
      if !self.session.isRunning {
        self.session.startRunning()
      }
    }
  }

  @objc private func stopSession() {
    sessionQueue.async {
      if self.session.isRunning {
        self.session.stopRunning()
      }
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
