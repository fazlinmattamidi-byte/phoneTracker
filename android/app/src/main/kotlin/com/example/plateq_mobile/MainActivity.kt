package com.example.plateq_mobile

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.security.KeyStore
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executor
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

class MainActivity : FlutterActivity() {
    private val csvPickerRequestCode = 7406
    private val handler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var pendingCsvPickResult: MethodChannel.Result? = null
    private var scanning = false
    private var selectedCameraId: String? = null
    private var lastSettings: Map<String, Any?> = emptyMap()
    private var lastFrameWidth = 0
    private var lastFrameHeight = 0
    private var lastFrameRotation = 0
    private var frameCount = 0L
    private var detectorFrameCount = 0L
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
    private var lastRuntimeFrameCount = 0L
    private var lastRuntimeDetectorCount = 0L
    private var lastRuntimeSampleMs = System.currentTimeMillis()
    private val nativeTracker = NativeTrackEngine()

    private val runtimeTick = object : Runnable {
        override fun run() {
            if (!scanning) return
            emitRuntime("SCANNING")
            emitTrackUpdate()
            handler.postDelayed(this, 1000L)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory("plateq.anpr_camera_preview", PlateqCameraPreviewFactory(this))

        MethodChannel(messenger, "plateq.anpr/methods").setMethodCallHandler(::handleAnprMethod)
        EventChannel(messenger, "plateq.anpr/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                emitRuntime(if (scanning) "SCANNING" else "READY")
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
        MethodChannel(messenger, "plateq.auth/session").setMethodCallHandler(::handleSessionMethod)
        MethodChannel(messenger, "plateq.files/share").setMethodCallHandler(::handleShareMethod)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ensureCameraPermission()
    }

    override fun onDestroy() {
        stopRuntimeLoop()
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != csvPickerRequestCode) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }

        val pending = pendingCsvPickResult ?: return
        pendingCsvPickResult = null
        if (resultCode != Activity.RESULT_OK) {
            pending.success(null)
            return
        }

        val uri = data?.data
        if (uri == null) {
            pending.success(null)
            return
        }

        try {
            val csv = contentResolver.openInputStream(uri)
                ?.bufferedReader(Charsets.UTF_8)
                ?.use { it.readText() }
            pending.success(csv)
        } catch (error: Throwable) {
            pending.error("CSV_READ", "Unable to read selected CSV file.", error.message)
        }
    }

    private fun handleAnprMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                ensureCameraPermission()
                result.success(runtimeStatus())
                emitRuntime("READY")
            }
            "listCameras" -> result.success(listNativeCameras())
            "selectCamera" -> {
                selectedCameraId = call.argument<String>("cameraId")
                result.success(null)
            }
            "startScanning" -> {
                if (!hasCameraPermission()) {
                    ensureCameraPermission()
                    result.error("CAMERA_PERMISSION", "Camera permission is required before scanning.", null)
                    emitError("CAMERA_PERMISSION", "Camera permission is required before scanning.", true)
                    return
                }
                selectedCameraId = call.argument<String>("cameraId") ?: selectedCameraId ?: defaultCameraId()
                lastSettings = call.argument<Map<String, Any?>>("settings") ?: emptyMap()
                nativeTracker.reset()
                frameCount = 0
                detectorFrameCount = 0
                lastRuntimeFrameCount = 0
                lastRuntimeDetectorCount = 0
                lastRuntimeSampleMs = System.currentTimeMillis()
                scanning = true
                result.success(null)
                emitRuntime("SCANNING")
                emitTrackUpdate()
                handler.removeCallbacks(runtimeTick)
                handler.postDelayed(runtimeTick, 1000L)
            }
            "stopScanning" -> {
                stopRuntimeLoop()
                nativeTracker.reset()
                result.success(null)
                emitRuntime("READY")
            }
            "updateSettings" -> {
                lastSettings = call.argument<Map<String, Any?>>("settings") ?: emptyMap()
                result.success(null)
                emitRuntime(if (scanning) "SCANNING" else "READY")
            }
            "setFacing" -> {
                selectedCameraId = cameraIdForFacing(call.argument<String>("facing") ?: "BACK") ?: selectedCameraId
                result.success(null)
            }
            "dispose" -> {
                stopRuntimeLoop()
                nativeTracker.reset()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun handleSessionMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getSession" -> result.success(readSecureSession())
            "saveSession" -> {
                writeSecureSession(call.argument<String>("session") ?: "")
                result.success(null)
            }
            "clearSession" -> {
                clearSecureSession()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun handleShareMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "shareText" -> {
                val title = call.argument<String>("title") ?: "Share"
                val text = call.argument<String>("text") ?: ""
                val mimeType = call.argument<String>("mimeType") ?: "text/plain"
                val intent = Intent(Intent.ACTION_SEND).apply {
                    type = mimeType
                    putExtra(Intent.EXTRA_SUBJECT, title)
                    putExtra(Intent.EXTRA_TEXT, text)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(Intent.createChooser(intent, title))
                result.success(true)
            }
            "pickCsv" -> {
                if (pendingCsvPickResult != null) {
                    result.error("PICKER_BUSY", "A CSV picker is already open.", null)
                    return
                }
                pendingCsvPickResult = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "text/*"
                    putExtra(
                        Intent.EXTRA_MIME_TYPES,
                        arrayOf(
                            "text/csv",
                            "text/comma-separated-values",
                            "application/csv",
                            "application/vnd.ms-excel",
                            "text/plain",
                        ),
                    )
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                try {
                    startActivityForResult(Intent.createChooser(intent, "Import Vehicles CSV"), csvPickerRequestCode)
                } catch (error: Throwable) {
                    pendingCsvPickResult = null
                    result.error("PICKER_UNAVAILABLE", "CSV picker is unavailable on this device.", error.message)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun readSecureSession(): String? {
        val prefs = getSharedPreferences("plateq_auth", Context.MODE_PRIVATE)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return prefs.getString("session", null)
        }
        val iv = prefs.getString("session_iv", null) ?: return prefs.getString("session", null)
        val cipherText = prefs.getString("session_ct", null) ?: return prefs.getString("session", null)
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                getOrCreateSessionKey(),
                GCMParameterSpec(128, Base64.decode(iv, Base64.NO_WRAP)),
            )
            String(cipher.doFinal(Base64.decode(cipherText, Base64.NO_WRAP)), Charsets.UTF_8)
        } catch (_: Throwable) {
            null
        }
    }

    private fun writeSecureSession(raw: String) {
        val prefs = getSharedPreferences("plateq_auth", Context.MODE_PRIVATE)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            prefs.edit().putString("session", raw).apply()
            return
        }
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, getOrCreateSessionKey())
            val encodedIv = Base64.encodeToString(cipher.iv, Base64.NO_WRAP)
            val encodedCipherText = Base64.encodeToString(cipher.doFinal(raw.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
            prefs.edit()
                .remove("session")
                .putString("session_iv", encodedIv)
                .putString("session_ct", encodedCipherText)
                .apply()
        } catch (_: Throwable) {
            prefs.edit().putString("session", raw).apply()
        }
    }

    private fun clearSecureSession() {
        getSharedPreferences("plateq_auth", Context.MODE_PRIVATE)
            .edit()
            .remove("session")
            .remove("session_iv")
            .remove("session_ct")
            .apply()
    }

    private fun getOrCreateSessionKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getKey("plateq_auth_session", null)
        if (existing is SecretKey) return existing

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        val spec = KeyGenParameterSpec.Builder(
            "plateq_auth_session",
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .build()
        generator.init(spec)
        return generator.generateKey()
    }

    private fun runtimeStatus(): Map<String, Any?> {
        val warnings = mutableListOf<String>()
        if (!hasCameraPermission()) warnings.add("Camera permission has not been granted yet.")
        return mapOf(
            "runtimeState" to if (scanning) "SCANNING" else "READY",
            "deviceTier" to "AUTO",
            "detectorProvider" to "NATIVE_HEURISTIC",
            "ocrProvider" to "PENDING_PHASE_11",
            "environmentProvider" to "NATIVE_HEURISTIC",
            "plateQualityProvider" to "NATIVE_HEURISTIC",
            "warnings" to warnings,
        )
    }

    private fun listNativeCameras(): List<Map<String, Any?>> {
        return try {
            val manager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val cameraIds = manager.cameraIdList.toList()
            cameraIds.mapIndexed { index, id ->
                val characteristics = manager.getCameraCharacteristics(id)
                val facing = readFacing(characteristics)
                val fps = characteristics
                    .get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
                    ?.map { it.upper }
                    ?.distinct()
                    ?.sorted()
                    ?: emptyList()
                val sizes = characteristics
                    .get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                    ?.getOutputSizes(SurfaceTexture::class.java)
                    ?.take(8)
                    ?.map { "${it.width}x${it.height}" }
                    ?: emptyList()
                val afModes = characteristics.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES)
                mapOf(
                    "id" to id,
                    "label" to "${facing.lowercase().replaceFirstChar { it.titlecase() }} Camera ${index + 1}",
                    "facing" to facing,
                    "isDefault" to (selectedCameraId == id || (selectedCameraId == null && facing == "BACK")),
                    "supportsAutofocus" to (afModes?.any { it != CameraCharacteristics.CONTROL_AF_MODE_OFF } ?: false),
                    "supportsExposure" to true,
                    "supportedResolutions" to sizes,
                    "supportedFps" to fps,
                )
            }
        } catch (error: Throwable) {
            listOf(fallbackCamera())
        }
    }

    private fun fallbackCamera(): Map<String, Any?> {
        return mapOf(
            "id" to "native-back",
            "label" to "Rear Camera",
            "facing" to "BACK",
            "isDefault" to true,
            "supportsAutofocus" to false,
            "supportsExposure" to false,
            "supportedResolutions" to emptyList<String>(),
            "supportedFps" to emptyList<Int>(),
        )
    }

    private fun readFacing(characteristics: CameraCharacteristics): String {
        return when (characteristics.get(CameraCharacteristics.LENS_FACING)) {
            CameraCharacteristics.LENS_FACING_FRONT -> "FRONT"
            CameraCharacteristics.LENS_FACING_EXTERNAL -> "EXTERNAL"
            else -> "BACK"
        }
    }

    private fun defaultCameraId(): String {
        return cameraIdForFacing("BACK") ?: listNativeCameras().firstOrNull()?.get("id")?.toString() ?: "native-back"
    }

    private fun cameraIdForFacing(facing: String): String? {
        return listNativeCameras().firstOrNull { it["facing"] == facing }?.get("id")?.toString()
    }

    private fun stopRuntimeLoop() {
        scanning = false
        handler.removeCallbacks(runtimeTick)
    }

    private fun emitRuntime(state: String) {
        updateRuntimeFps()
        eventSink?.success(
            mapOf(
                "type" to "runtime",
                "timestamp" to timestamp(),
                "platform" to "android",
                "runtimeState" to state,
                "deviceTier" to "AUTO",
                "cameraId" to (selectedCameraId ?: defaultCameraId()),
                "cameraLabel" to (listNativeCameras().firstOrNull { it["id"] == selectedCameraId }?.get("label") ?: "Rear Camera"),
                "detectorFps" to if (scanning) lastDetectorFps else 0.0,
                "cameraFps" to if (scanning) lastCameraFps else 0.0,
                "ocrQueueDepth" to 0,
                "temperatureState" to "NOMINAL",
                "memoryMb" to 0.0,
                "frameWidth" to lastFrameWidth,
                "frameHeight" to lastFrameHeight,
                "frameRotation" to lastFrameRotation,
                "frameCount" to frameCount,
                "detectorProvider" to "NATIVE_HEURISTIC",
                "ocrProvider" to "PENDING_PHASE_11",
                "environmentProvider" to "NATIVE_HEURISTIC",
                "plateQualityProvider" to "NATIVE_HEURISTIC",
                "environmentLabel" to lastEnvironmentLabel,
                "environmentConfidence" to lastEnvironmentConfidence,
                "environmentStats" to mapOf(
                    "brightness" to lastEnvironmentBrightness,
                    "contrast" to lastEnvironmentContrast,
                    "glareRatio" to lastEnvironmentGlareRatio,
                ),
                "plateQualityScore" to lastPlateQualityScore,
                "plateQualityClass" to lastPlateQualityClass,
                "settings" to lastSettings,
            )
        )
    }

    internal fun selectedLensFacing(): Int {
        val selected = listNativeCameras().firstOrNull { it["id"] == selectedCameraId }
        return when (selected?.get("facing")?.toString()) {
            "FRONT" -> CameraSelector.LENS_FACING_FRONT
            else -> CameraSelector.LENS_FACING_BACK
        }
    }

    internal fun recordAnalyzedFrame(image: ImageProxy) {
        val width = image.width
        val height = image.height
        val rotation = image.imageInfo.rotationDegrees
        val shouldAnalyze = scanning
        val analysis = if (shouldAnalyze) {
            NativeFrameAnalyzer.analyze(
                image = image,
                frameNumber = frameCount + 1,
                threshold = settingDouble("detectionThreshold", 0.35),
            )
        } else {
            null
        }

        handler.post {
            lastFrameWidth = width
            lastFrameHeight = height
            lastFrameRotation = rotation
            frameCount += 1
            if (!scanning || analysis == null) return@post

            detectorFrameCount += 1
            lastDetectorConfidence = analysis.detectorConfidence
            lastEnvironmentLabel = analysis.environmentLabel
            lastEnvironmentConfidence = analysis.environmentConfidence
            lastEnvironmentBrightness = analysis.brightness
            lastEnvironmentContrast = analysis.contrast
            lastEnvironmentGlareRatio = analysis.glareRatio
            lastPlateQualityScore = analysis.qualityScore
            lastPlateQualityClass = analysis.qualityClass
            nativeTracker.update(
                detection = analysis.detection,
                frameNumber = frameCount,
                timestampMs = System.currentTimeMillis(),
                maxTracks = settingInt("maxTracks", 8),
            )
            if (frameCount % 3L == 0L) {
                emitTrackUpdate()
            }
        }
    }

    private fun emitTrackUpdate() {
        eventSink?.success(
            mapOf(
                "type" to "trackUpdate",
                "timestamp" to timestamp(),
                "platform" to "android",
                "tracks" to nativeTracker.snapshot(),
            )
        )
    }

    private fun updateRuntimeFps() {
        val now = System.currentTimeMillis()
        val elapsedSeconds = max(0.001, (now - lastRuntimeSampleMs) / 1000.0)
        if (elapsedSeconds < 0.75) return
        lastCameraFps = clamp01((frameCount - lastRuntimeFrameCount) / elapsedSeconds / 30.0) * 30.0
        lastDetectorFps = (detectorFrameCount - lastRuntimeDetectorCount) / elapsedSeconds
        lastRuntimeFrameCount = frameCount
        lastRuntimeDetectorCount = detectorFrameCount
        lastRuntimeSampleMs = now
    }

    private fun settingDouble(key: String, fallback: Double): Double {
        val value = lastSettings[key]
        return when (value) {
            is Number -> value.toDouble()
            is String -> value.toDoubleOrNull() ?: fallback
            else -> fallback
        }
    }

    private fun settingInt(key: String, fallback: Int): Int {
        val value = lastSettings[key]
        return when (value) {
            is Number -> value.toInt()
            is String -> value.toIntOrNull() ?: fallback
            else -> fallback
        }
    }

    private fun emitError(code: String, message: String, recoverable: Boolean) {
        eventSink?.success(
            mapOf(
                "type" to "error",
                "timestamp" to timestamp(),
                "platform" to "android",
                "code" to code,
                "message" to message,
                "recoverable" to recoverable,
            )
        )
    }

    private fun hasCameraPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
    }

    private fun ensureCameraPermission() {
        if (!hasCameraPermission() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            requestPermissions(arrayOf(Manifest.permission.CAMERA), 4204)
        }
    }

    private fun timestamp(): String {
        val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        format.timeZone = TimeZone.getTimeZone("UTC")
        return format.format(Date())
    }
}

private data class NativeDetection(
    val bbox: NativeBbox,
    val confidence: Double,
    val detectorConfidence: Double,
    val motionScore: Double,
    val qualityScore: Double,
    val qualityClass: String,
)

private data class NativeBbox(
    val x: Double,
    val y: Double,
    val width: Double,
    val height: Double,
) {
    fun iou(other: NativeBbox): Double {
        val left = max(x, other.x)
        val top = max(y, other.y)
        val right = min(x + width, other.x + other.width)
        val bottom = min(y + height, other.y + other.height)
        val intersection = max(0.0, right - left) * max(0.0, bottom - top)
        val union = width * height + other.width * other.height - intersection
        return if (union <= 0.0) 0.0 else intersection / union
    }

    fun toMap(): Map<String, Any> = mapOf(
        "x" to x,
        "y" to y,
        "width" to width,
        "height" to height,
    )
}

private data class NativeFrameAnalysis(
    val detection: NativeDetection?,
    val detectorConfidence: Double,
    val environmentLabel: String,
    val environmentConfidence: Double,
    val brightness: Double,
    val contrast: Double,
    val glareRatio: Double,
    val qualityScore: Double,
    val qualityClass: String,
)

private object NativeFrameAnalyzer {
    fun analyze(image: ImageProxy, frameNumber: Long, threshold: Double): NativeFrameAnalysis {
        val stats = sampleLuma(image)
        val environment = classifyEnvironment(stats)
        val box = candidateBox(image.width, image.height, frameNumber, stats)
        val detectorConfidence = roundMetric(
            clamp01(
                0.20 +
                    stats.exposureScore * 0.30 +
                    stats.contrastScore * 0.34 +
                    stats.sharpnessScore * 0.10 -
                    stats.glareRatio * 0.45 -
                    stats.darkRatio * 0.18,
            ),
        )
        val qualityScore = roundMetric(
            clamp01(
                detectorConfidence * 0.30 +
                    stats.exposureScore * 0.20 +
                    stats.contrastScore * 0.22 +
                    stats.sharpnessScore * 0.16 +
                    boxSizeScore(box) * 0.12 -
                    stats.glareRatio * 0.22,
            ),
        )
        val qualityClass = classifyQuality(stats, qualityScore)
        val detection = if (detectorConfidence >= max(0.18, threshold * 0.70) && qualityScore >= 0.20) {
            NativeDetection(
                bbox = box,
                confidence = qualityScore,
                detectorConfidence = detectorConfidence,
                motionScore = stats.motionScore,
                qualityScore = qualityScore,
                qualityClass = qualityClass,
            )
        } else {
            null
        }
        return NativeFrameAnalysis(
            detection = detection,
            detectorConfidence = detectorConfidence,
            environmentLabel = environment.first,
            environmentConfidence = environment.second,
            brightness = roundMetric(stats.brightness),
            contrast = roundMetric(stats.contrast),
            glareRatio = roundMetric(stats.glareRatio),
            qualityScore = qualityScore,
            qualityClass = qualityClass,
        )
    }

    private fun sampleLuma(image: ImageProxy): LumaStats {
        val plane = image.planes.firstOrNull()
            ?: return LumaStats.empty()
        val buffer = plane.buffer.duplicate()
        val width = image.width
        val height = image.height
        val rowStride = max(1, plane.rowStride)
        val pixelStride = max(1, plane.pixelStride)
        val stepY = max(1, height / 72)
        val stepX = max(1, width / 96)
        var sum = 0.0
        var sumSquares = 0.0
        var count = 0
        var bright = 0
        var dark = 0
        var edge = 0.0
        var edgeCount = 0
        var previous = -1

        var y = 0
        while (y < height) {
            val row = y * rowStride
            var x = 0
            while (x < width) {
                val index = row + x * pixelStride
                if (index >= 0 && index < buffer.limit()) {
                    val value = buffer.get(index).toInt() and 0xFF
                    sum += value.toDouble()
                    sumSquares += value.toDouble() * value.toDouble()
                    if (value > 242) bright += 1
                    if (value < 28) dark += 1
                    if (previous >= 0) {
                        edge += abs(value - previous).toDouble()
                        edgeCount += 1
                    }
                    previous = value
                    count += 1
                }
                x += stepX
            }
            y += stepY
        }

        if (count == 0) return LumaStats.empty()
        val meanRaw = sum / count
        val variance = max(0.0, sumSquares / count - meanRaw * meanRaw)
        val stdDev = sqrt(variance)
        val brightness = meanRaw / 255.0
        val contrast = clamp01(stdDev / 96.0)
        val sharpness = clamp01((edge / max(1, edgeCount)) / 48.0)
        return LumaStats(
            brightness = brightness,
            contrast = contrast,
            glareRatio = bright.toDouble() / count,
            darkRatio = dark.toDouble() / count,
            exposureScore = clamp01(1.0 - abs(brightness - 0.52) / 0.52),
            contrastScore = contrast,
            sharpnessScore = sharpness,
            motionScore = clamp01(abs(contrast - sharpness) * 0.35),
        )
    }

    private fun candidateBox(width: Int, height: Int, frameNumber: Long, stats: LumaStats): NativeBbox {
        val frameAspect = max(0.5, width.toDouble() / max(1, height).toDouble())
        val boxWidth = clamp(0.24 + stats.contrast * 0.12 + stats.sharpnessScore * 0.06, 0.24, 0.42)
        val boxHeight = clamp((boxWidth * frameAspect) / 4.6, 0.045, 0.135)
        val drift = ((frameNumber % 40L).toDouble() - 20.0) / 6000.0
        val centerX = clamp(0.50 + drift, boxWidth / 2.0, 1.0 - boxWidth / 2.0)
        val centerY = clamp(0.61 + (0.5 - stats.brightness) * 0.08, boxHeight / 2.0, 1.0 - boxHeight / 2.0)
        return NativeBbox(
            x = roundMetric(centerX - boxWidth / 2.0),
            y = roundMetric(centerY - boxHeight / 2.0),
            width = roundMetric(boxWidth),
            height = roundMetric(boxHeight),
        )
    }

    private fun classifyEnvironment(stats: LumaStats): Pair<String, Double> {
        return when {
            stats.glareRatio >= 0.10 -> "GLARE" to 0.88
            stats.glareRatio >= 0.045 && stats.brightness >= 0.56 -> "BACKLIGHT" to 0.78
            stats.brightness <= 0.16 -> "NIGHT" to 0.88
            stats.brightness <= 0.30 -> "LOW_LIGHT" to 0.80
            stats.contrast <= 0.16 && stats.brightness >= 0.34 -> "FOG" to 0.66
            stats.brightness >= 0.58 && stats.contrast >= 0.24 && stats.glareRatio < 0.025 -> "DAY" to 0.74
            stats.brightness >= 0.38 && stats.contrast >= 0.22 && stats.sharpnessScore >= 0.32 -> "GOOD_CONDITION" to 0.72
            else -> "DAY" to 0.58
        }
    }

    private fun classifyQuality(stats: LumaStats, qualityScore: Double): String {
        return when {
            stats.glareRatio >= 0.10 -> "GLARE_REFLECTION"
            stats.brightness <= 0.18 -> "UNDEREXPOSED"
            stats.brightness >= 0.88 -> "OVEREXPOSED"
            stats.contrast <= 0.16 -> "LOW_CONTRAST"
            stats.sharpnessScore <= 0.16 -> "OUT_OF_FOCUS"
            qualityScore >= 0.72 -> "STANDARD_RECTANGLE"
            qualityScore >= 0.52 -> "SLIGHT_ROTATION"
            else -> "LOW_CONTRAST"
        }
    }

    private fun boxSizeScore(box: NativeBbox): Double {
        val area = box.width * box.height
        return clamp01(area / 0.045)
    }
}

private data class LumaStats(
    val brightness: Double,
    val contrast: Double,
    val glareRatio: Double,
    val darkRatio: Double,
    val exposureScore: Double,
    val contrastScore: Double,
    val sharpnessScore: Double,
    val motionScore: Double,
) {
    companion object {
        fun empty(): LumaStats = LumaStats(
            brightness = 0.0,
            contrast = 0.0,
            glareRatio = 0.0,
            darkRatio = 1.0,
            exposureScore = 0.0,
            contrastScore = 0.0,
            sharpnessScore = 0.0,
            motionScore = 0.0,
        )
    }
}

private class NativeTrackEngine {
    private val tracks = mutableListOf<NativeTrack>()
    private var nextTrackNumber = 1

    fun reset() {
        tracks.clear()
        nextTrackNumber = 1
    }

    fun update(detection: NativeDetection?, frameNumber: Long, timestampMs: Long, maxTracks: Int) {
        if (detection == null) {
            ageTracks(frameNumber, timestampMs)
            return
        }

        val matched = tracks
            .filter { it.state != "REMOVED" }
            .maxByOrNull { it.bbox.iou(detection.bbox) }
            ?.takeIf { it.bbox.iou(detection.bbox) >= 0.20 }

        if (matched != null) {
            matched.applyDetection(detection, frameNumber, timestampMs)
        } else if (tracks.size < max(1, maxTracks)) {
            tracks.add(NativeTrack(nextTrackNumber++, detection, frameNumber, timestampMs))
        } else {
            tracks
                .minByOrNull { it.confidence }
                ?.takeIf { detection.confidence > it.confidence }
                ?.replaceWith(nextTrackNumber++, detection, frameNumber, timestampMs)
        }

        ageTracks(frameNumber, timestampMs)
    }

    fun snapshot(): List<Map<String, Any?>> {
        return tracks
            .filter { it.state != "REMOVED" }
            .sortedBy { it.trackNumber }
            .map { it.toMap() }
    }

    private fun ageTracks(frameNumber: Long, timestampMs: Long) {
        tracks.forEach { it.age(frameNumber, timestampMs) }
        tracks.removeAll { it.state == "REMOVED" }
    }
}

private class NativeTrack(
    var trackNumber: Int,
    detection: NativeDetection,
    frameNumber: Long,
    timestampMs: Long,
) {
    var bbox = detection.bbox
    var state = "VISIBLE"
    var pipelineState = "COLLECTING"
    var confidence = detection.confidence
    var detectorConfidence = detection.detectorConfidence
    var motionScore = detection.motionScore
    var qualityScore = detection.qualityScore
    var qualityClass = detection.qualityClass
    private var firstFrame = frameNumber
    private var lastSeenFrame = frameNumber
    private var lastSeenMs = timestampMs
    private var detectionCount = 1

    fun applyDetection(detection: NativeDetection, frameNumber: Long, timestampMs: Long) {
        bbox = smooth(bbox, detection.bbox)
        state = "VISIBLE"
        pipelineState = if (detectionCount >= 2 && detection.qualityScore >= 0.52) "READY_FOR_OCR" else "COLLECTING"
        confidence = roundMetric(max(confidence * 0.85, detection.confidence))
        detectorConfidence = detection.detectorConfidence
        motionScore = detection.motionScore
        qualityScore = detection.qualityScore
        qualityClass = detection.qualityClass
        lastSeenFrame = frameNumber
        lastSeenMs = timestampMs
        detectionCount += 1
    }

    fun replaceWith(newTrackNumber: Int, detection: NativeDetection, frameNumber: Long, timestampMs: Long) {
        trackNumber = newTrackNumber
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

    fun age(frameNumber: Long, timestampMs: Long) {
        val missedFrames = frameNumber - lastSeenFrame
        val elapsedMs = timestampMs - lastSeenMs
        state = when {
            elapsedMs > 1200 || missedFrames > 24 -> "REMOVED"
            missedFrames > 2 -> "LOST"
            else -> state
        }
        if (state == "LOST") {
            pipelineState = "PREDICTING"
            confidence = roundMetric(confidence * 0.92)
        }
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "trackId" to "track-$trackNumber",
        "trackNumber" to trackNumber,
        "state" to state,
        "pipelineState" to pipelineState,
        "bbox" to bbox.toMap(),
        "confidence" to confidence,
        "detectorConfidence" to detectorConfidence,
        "motionScore" to motionScore,
        "qualityScore" to qualityScore,
        "qualityClass" to qualityClass,
        "currentPlate" to "",
        "currentPlateConfidence" to 0.0,
        "matchType" to "NONE",
        "ageFrames" to (lastSeenFrame - firstFrame + 1),
        "detections" to detectionCount,
    )

    private fun smooth(previous: NativeBbox, next: NativeBbox): NativeBbox {
        val keep = 0.72
        val add = 1.0 - keep
        return NativeBbox(
            x = roundMetric(previous.x * keep + next.x * add),
            y = roundMetric(previous.y * keep + next.y * add),
            width = roundMetric(previous.width * keep + next.width * add),
            height = roundMetric(previous.height * keep + next.height * add),
        )
    }
}

private fun clamp01(value: Double): Double = clamp(value, 0.0, 1.0)

private fun clamp(value: Double, minValue: Double, maxValue: Double): Double =
    min(maxValue, max(minValue, value))

private fun roundMetric(value: Double): Double = kotlin.math.round(value * 1000.0) / 1000.0

private class PlateqCameraPreviewFactory(private val activity: MainActivity) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return PlateqCameraPreviewView(context, activity)
    }
}

private class PlateqCameraPreviewView(
    private val context: Context,
    private val activity: MainActivity,
) : PlatformView {
    private val analysisExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainExecutor: Executor = Executor { command -> Handler(Looper.getMainLooper()).post(command) }
    private var cameraProvider: ProcessCameraProvider? = null
    private val previewView = PreviewView(context).apply {
        implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        scaleType = PreviewView.ScaleType.FILL_CENTER
    }
    private val root = FrameLayout(context).apply {
        setBackgroundColor(Color.rgb(2, 6, 23))
        addView(
            previewView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        val label = TextView(context).apply {
            text = "Starting CameraX preview..."
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.argb(96, 2, 6, 23))
            textSize = 12f
            gravity = Gravity.CENTER
        }
        addView(
            label,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
    }

    init {
        bindCamera()
    }

    override fun getView(): View = root

    override fun dispose() {
        cameraProvider?.unbindAll()
        analysisExecutor.shutdown()
    }

    private fun bindCamera() {
        val providerFuture = ProcessCameraProvider.getInstance(context)
        providerFuture.addListener(
            {
                try {
                    val provider = providerFuture.get()
                    cameraProvider = provider
                    val preview = Preview.Builder().build().also {
                        it.setSurfaceProvider(previewView.surfaceProvider)
                    }
                    val analysis = ImageAnalysis.Builder()
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .build()
                        .also { analyzer ->
                            analyzer.setAnalyzer(analysisExecutor) { image ->
                                activity.recordAnalyzedFrame(image)
                                image.close()
                            }
                        }
                    val selector = CameraSelector.Builder()
                        .requireLensFacing(activity.selectedLensFacing())
                        .build()
                    provider.unbindAll()
                    provider.bindToLifecycle(activity, selector, preview, analysis)
                } catch (error: Throwable) {
                    showFallback("CameraX preview unavailable: ${error.message ?: error.javaClass.simpleName}")
                }
            },
            mainExecutor,
        )
    }

    private fun showFallback(message: String) {
        root.removeAllViews()
        root.addView(
            TextView(context).apply {
                text = message
                setTextColor(Color.WHITE)
                textSize = 14f
                gravity = Gravity.CENTER
                setBackgroundColor(Color.rgb(2, 6, 23))
            },
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
    }
}
