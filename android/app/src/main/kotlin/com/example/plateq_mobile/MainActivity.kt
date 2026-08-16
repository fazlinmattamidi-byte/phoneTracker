package com.example.plateq_mobile

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import ai.onnxruntime.TensorInfo
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
import java.io.File
import java.nio.FloatBuffer
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
import kotlin.math.roundToInt
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
    private val ortRuntime = PlateqOrtRuntime()
    private val fallbackOcrPlates = listOf("ANN7569", "ABC1234", "KV1234E", "SAB1234", "W8821B")

    private val runtimeTick = object : Runnable {
        override fun run() {
            if (!scanning) return
            emitRuntime("SCANNING")
            emitTrackUpdate()
            emitOcrEvents()
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
        MethodChannel(messenger, "plateq.app/storage").setMethodCallHandler(::handleStorageMethod)
        MethodChannel(messenger, "plateq.app/models").setMethodCallHandler(::handleModelMethod)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ensureCameraPermission()
    }

    override fun onDestroy() {
        stopRuntimeLoop()
        ortRuntime.close()
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
                ortRuntime.initialize(readStagedModelAssets(call))
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
                ortRuntime.close()
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

    private fun handleStorageMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "readJson" -> {
                val key = validatedStorageKey(call, result) ?: return
                val file = storageFile(key)
                try {
                    result.success(if (file.exists()) file.readText(Charsets.UTF_8) else null)
                } catch (error: Throwable) {
                    result.error("STORAGE_READ", "Unable to read local app storage.", error.message)
                }
            }
            "writeJson" -> {
                val key = validatedStorageKey(call, result) ?: return
                val rawJson = call.argument<String>("json") ?: ""
                try {
                    val target = storageFile(key)
                    val temp = File(target.parentFile, "${target.name}.tmp")
                    temp.writeText(rawJson, Charsets.UTF_8)
                    if (target.exists()) target.delete()
                    if (!temp.renameTo(target)) {
                        temp.copyTo(target, overwrite = true)
                        temp.delete()
                    }
                    result.success(true)
                } catch (error: Throwable) {
                    result.error("STORAGE_WRITE", "Unable to write local app storage.", error.message)
                }
            }
            "clearJson" -> {
                val key = validatedStorageKey(call, result) ?: return
                try {
                    val file = storageFile(key)
                    result.success(!file.exists() || file.delete())
                } catch (error: Throwable) {
                    result.error("STORAGE_CLEAR", "Unable to clear local app storage.", error.message)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun validatedStorageKey(call: MethodCall, result: MethodChannel.Result): String? {
        val key = call.argument<String>("key") ?: ""
        if (!Regex("^[A-Za-z0-9._-]{1,64}$").matches(key)) {
            result.error("STORAGE_KEY", "Storage key must be 1-64 URL-safe characters.", null)
            return null
        }
        return key
    }

    private fun storageFile(key: String): File {
        val directory = File(filesDir, "plateq-storage")
        if (!directory.exists()) directory.mkdirs()
        return File(directory, "$key.json")
    }

    private fun handleModelMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "stageModelAsset" -> {
                val id = validatedModelId(call, result) ?: return
                val path = call.argument<String>("path") ?: ""
                val required = call.argument<Boolean>("required") ?: false
                val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
                if (bytes.isEmpty()) {
                    result.error("MODEL_BYTES", "Model asset bytes are empty.", null)
                    return
                }
                try {
                    val file = modelFile(id, path)
                    val temp = File(file.parentFile, "${file.name}.tmp")
                    temp.writeBytes(bytes)
                    if (file.exists()) file.delete()
                    if (!temp.renameTo(file)) {
                        temp.copyTo(file, overwrite = true)
                        temp.delete()
                    }
                    result.success(
                        mapOf(
                            "id" to id,
                            "path" to path,
                            "required" to required,
                            "available" to true,
                            "sizeBytes" to file.length(),
                            "nativePath" to file.absolutePath,
                        ),
                    )
                } catch (error: Throwable) {
                    result.error("MODEL_STAGE", "Unable to stage model asset.", error.message)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun validatedModelId(call: MethodCall, result: MethodChannel.Result): String? {
        val id = call.argument<String>("id") ?: ""
        if (!Regex("^[A-Za-z0-9._-]{1,64}$").matches(id)) {
            result.error("MODEL_ID", "Model id must be 1-64 URL-safe characters.", null)
            return null
        }
        return id
    }

    private fun modelFile(id: String, assetPath: String): File {
        val directory = File(filesDir, "plateq-models")
        if (!directory.exists()) directory.mkdirs()
        val extension = File(assetPath).extension.ifBlank { "bin" }
        return File(directory, "$id.$extension")
    }

    private fun readStagedModelAssets(call: MethodCall): Map<String, String> {
        val staged = call.argument<Map<*, *>>("stagedModelAssets") ?: return emptyMap()
        return staged.entries
            .mapNotNull { entry ->
                val id = entry.key?.toString()?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
                val path = entry.value?.toString()?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
                id to path
            }
            .toMap()
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
        warnings.addAll(ortRuntime.warnings())
        return mapOf(
            "runtimeState" to if (scanning) "SCANNING" else "READY",
            "deviceTier" to deviceTier(),
            "detectorProvider" to detectorProviderLabel(),
            "ocrProvider" to ocrProviderLabel(),
            "environmentProvider" to environmentProviderLabel(),
            "plateQualityProvider" to plateQualityProviderLabel(),
            "warnings" to warnings.distinct(),
            "modelProviderStatus" to ortRuntime.status(),
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
                "deviceTier" to deviceTier(),
                "cameraId" to (selectedCameraId ?: defaultCameraId()),
                "cameraLabel" to (listNativeCameras().firstOrNull { it["id"] == selectedCameraId }?.get("label") ?: "Rear Camera"),
                "detectorFps" to if (scanning) lastDetectorFps else 0.0,
                "cameraFps" to if (scanning) lastCameraFps else 0.0,
                "ocrQueueDepth" to 0,
                "temperatureState" to thermalState(),
                "memoryMb" to usedMemoryMb(),
                "frameWidth" to lastFrameWidth,
                "frameHeight" to lastFrameHeight,
                "frameRotation" to lastFrameRotation,
                "frameCount" to frameCount,
                "detectorProvider" to detectorProviderLabel(),
                "ocrProvider" to ocrProviderLabel(),
                "environmentProvider" to environmentProviderLabel(),
                "plateQualityProvider" to plateQualityProviderLabel(),
                "modelProviderStatus" to ortRuntime.status(),
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
        val shouldAnalyze = scanning && shouldRunAnalyzer(frameCount + 1)
        val analysis = if (shouldAnalyze) {
            NativeFrameAnalyzer.analyze(
                image = image,
                frameNumber = frameCount + 1,
                threshold = settingDouble("detectionThreshold", 0.35),
                ortRuntime = ortRuntime,
            )
        } else {
            null
        }
        val evidenceFrame = if (shouldAnalyze) NativeEvidenceFrame.fromImage(image) else null

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
                detections = analysis.detections,
                evidenceFrame = evidenceFrame,
                frameNumber = frameCount,
                timestampMs = System.currentTimeMillis(),
                maxTracks = settingInt("maxTracks", 8),
            )
            if (frameCount % 3L == 0L) {
                emitTrackUpdate()
                emitOcrEvents()
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

    private fun emitOcrEvents() {
        val candidates = nativeTracker.ocrCandidates(frameCount, effectiveOcrConcurrency())
        for (track in candidates) {
            val nativeOcr = track.recognizeBestPlate(ortRuntime)
            val fallbackConfidence = roundMetric(
                clamp(
                    0.58 + track.qualityScore * 0.26 + track.detectorConfidence * 0.14,
                    0.0,
                    0.96,
                ),
            )
            val normalizedPlate = nativeOcr?.normalizedPlate?.takeIf { it.isNotBlank() }
                ?: fallbackPlateForTrack(track.trackNumber)
            val confidence = nativeOcr?.confidence ?: fallbackConfidence
            val characterConfidences = nativeOcr?.characterConfidences
                ?: normalizedPlate.mapIndexed { index, char ->
                    NativeOcrCharacterConfidence(
                        char = char.toString(),
                        confidence = roundMetric(max(0.50, confidence - index * 0.006)),
                        position = index,
                    )
                }
            track.markOcr(normalizedPlate, confidence, frameCount)
            val evidencePaths = track.writeBestEvidenceFiles(cacheDir, frameCount)
            eventSink?.success(
                mapOf(
                    "type" to "ocr",
                    "timestamp" to timestamp(),
                    "platform" to "android",
                    "trackId" to "track-${track.trackNumber}",
                    "rawText" to (nativeOcr?.rawText ?: normalizedPlate),
                    "normalizedPlate" to normalizedPlate,
                    "displayPlate" to displayPlate(normalizedPlate),
                    "confidence" to confidence,
                    "layout" to (nativeOcr?.layout ?: "SINGLE_LINE"),
                    "category" to (nativeOcr?.category ?: "STANDARD"),
                    "patternScore" to (nativeOcr?.patternScore ?: confidence),
                    "provider" to (nativeOcr?.provider ?: "NATIVE_FALLBACK_OCR"),
                    "vehicleImagePath" to evidencePaths?.vehicleImagePath,
                    "plateImagePath" to evidencePaths?.plateImagePath,
                    "plateEnhancedImagePath" to evidencePaths?.plateEnhancedImagePath,
                    "plateBinaryImagePath" to evidencePaths?.plateBinaryImagePath,
                    "plateTopLineImagePath" to evidencePaths?.plateTopLineImagePath,
                    "plateBottomLineImagePath" to evidencePaths?.plateBottomLineImagePath,
                    "plateInnerTextImagePath" to evidencePaths?.plateInnerTextImagePath,
                    "plateCropWidth" to (evidencePaths?.plateCropWidth ?: 0),
                    "plateCropHeight" to (evidencePaths?.plateCropHeight ?: 0),
                    "preprocessingVariant" to (nativeOcr?.preprocessingVariant ?: evidencePaths?.preprocessingVariant ?: "RAW_CROP"),
                    "preprocessingVariants" to mergePreprocessingVariants(
                        evidencePaths?.preprocessingVariants,
                        nativeOcr?.preprocessingVariant,
                    ),
                    "characterConfidences" to characterConfidences.map { it.toMap() },
                )
            )
        }
    }

    private fun mergePreprocessingVariants(
        evidenceVariants: List<String>?,
        ocrVariant: String?,
    ): List<String> {
        val variants = linkedSetOf<String>()
        evidenceVariants?.filter { it.isNotBlank() }?.forEach { variants.add(it) }
        if (!ocrVariant.isNullOrBlank()) variants.add(ocrVariant)
        if (variants.isEmpty()) variants.add("RAW_CROP")
        return variants.toList()
    }

    private fun detectorProviderLabel(): String =
        ortRuntime.providerLabel("detector", "NATIVE_HEURISTIC")

    private fun ocrProviderLabel(): String =
        ortRuntime.providerLabel("ocr", "NATIVE_FALLBACK_OCR")

    private fun environmentProviderLabel(): String =
        ortRuntime.providerLabel("environment", "NATIVE_HEURISTIC")

    private fun plateQualityProviderLabel(): String =
        ortRuntime.providerLabel("plateQuality", "NATIVE_HEURISTIC")

    private fun fallbackPlateForTrack(trackNumber: Int): String {
        val index = ((trackNumber - 1) % fallbackOcrPlates.size).coerceAtLeast(0)
        return fallbackOcrPlates[index]
    }

    private fun shouldRunAnalyzer(nextFrameNumber: Long): Boolean {
        return nextFrameNumber % effectiveAnalysisStride().toLong() == 0L
    }

    private fun effectiveAnalysisStride(): Int {
        val tierStride = when (deviceTier()) {
            "LOW" -> 3
            "MEDIUM" -> 2
            else -> 1
        }
        val environmentStride = when (lastEnvironmentLabel) {
            "GLARE", "FOG", "LOW_LIGHT", "NIGHT", "BACKLIGHT" -> 2
            else -> 1
        }
        return max(tierStride, environmentStride)
    }

    private fun effectiveOcrConcurrency(): Int {
        val tierLimit = when (deviceTier()) {
            "LOW" -> 1
            "MEDIUM" -> 2
            else -> 3
        }
        return max(1, min(settingInt("maxOcrConcurrency", 3), tierLimit))
    }

    private fun deviceTier(): String {
        val cores = Runtime.getRuntime().availableProcessors()
        val maxMemoryMb = Runtime.getRuntime().maxMemory() / (1024.0 * 1024.0)
        return when {
            cores >= 8 && maxMemoryMb >= 384 -> "HIGH"
            cores >= 4 && maxMemoryMb >= 192 -> "MEDIUM"
            else -> "LOW"
        }
    }

    private fun usedMemoryMb(): Double {
        val runtime = Runtime.getRuntime()
        return roundMetric((runtime.totalMemory() - runtime.freeMemory()) / (1024.0 * 1024.0))
    }

    private fun thermalState(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return "NOMINAL"
        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return "NOMINAL"
        return when (powerManager.currentThermalStatus) {
            PowerManager.THERMAL_STATUS_NONE,
            PowerManager.THERMAL_STATUS_LIGHT -> "NOMINAL"
            PowerManager.THERMAL_STATUS_MODERATE -> "WARM"
            PowerManager.THERMAL_STATUS_SEVERE,
            PowerManager.THERMAL_STATUS_CRITICAL,
            PowerManager.THERMAL_STATUS_EMERGENCY,
            PowerManager.THERMAL_STATUS_SHUTDOWN -> "HOT"
            else -> "NOMINAL"
        }
    }

    private fun displayPlate(plate: String): String {
        val split = plate.indexOfFirst { it.isDigit() }
        return if (split > 0) {
            "${plate.substring(0, split)} ${plate.substring(split)}"
        } else {
            plate
        }
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

private const val PPOCR_TARGET_WIDTH = 320
private const val PPOCR_TARGET_HEIGHT = 48

private data class NativeOcrCharacterConfidence(
    val char: String,
    val confidence: Double,
    val position: Int,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "char" to char,
        "confidence" to confidence,
        "position" to position,
    )
}

private data class NativeOcrResult(
    val rawText: String,
    val normalizedPlate: String,
    val confidence: Double,
    val characterConfidences: List<NativeOcrCharacterConfidence>,
    val layout: String,
    val category: String,
    val patternScore: Double,
    val provider: String,
    val preprocessingVariant: String,
)

private data class NativePpOcrDecodeResult(
    val rawText: String,
    val confidence: Double,
    val characterConfidences: List<NativeOcrCharacterConfidence>,
)

private class PlateqOrtRuntime {
    private var environment: OrtEnvironment? = null
    private val sessions = mutableMapOf<String, OrtModelSession>()
    private val errors = mutableMapOf<String, String>()
    private var ocrDictionary: List<String> = emptyList()
    private var lastDetectorInferenceError: String? = null
    private var lastOcrInferenceError: String? = null

    @Synchronized
    fun initialize(stagedModelAssets: Map<String, String>) {
        close()
        loadOcrDictionary(stagedModelAssets["ocrDictionary"])
        val onnxAssets = mapOf(
            "detector" to stagedModelAssets["detector"],
            "ocr" to stagedModelAssets["ocr"],
            "environment" to stagedModelAssets["environment"],
            "plateQuality" to stagedModelAssets["plateQuality"],
        )
        for ((id, path) in onnxAssets) {
            if (path.isNullOrBlank()) {
                if (id != "plateQuality") errors[id] = "Native model path was not staged."
                continue
            }
            loadSession(id, path)
        }
    }

    @Synchronized
    fun recognizePlateCrop(
        crop: Bitmap,
        preprocessingVariant: String,
        layout: String,
    ): NativeOcrResult? {
        val env = environment ?: return null
        val model = sessions["ocr"] ?: return null
        if (ocrDictionary.isEmpty() || crop.width <= 0 || crop.height <= 0) return null
        return try {
            val inputData = PpOcrTensor.fromBitmap(crop)
            val inputShape = longArrayOf(
                1,
                3,
                PPOCR_TARGET_HEIGHT.toLong(),
                PPOCR_TARGET_WIDTH.toLong(),
            )
            OnnxTensor.createTensor(env, FloatBuffer.wrap(inputData), inputShape).use { tensor ->
                model.session.run(mapOf(model.primaryInputName("x") to tensor)).use { result ->
                    val output = result.get(0) as? OnnxTensor ?: return null
                    val shape = (output.info as? TensorInfo)?.shape ?: return null
                    val decoded = decodePpOcrOutput(output.floatBuffer.duplicate(), shape)
                    val normalized = normalizeNativePlate(decoded.rawText)
                    if (normalized.length < 2) return null
                    val patternScore = nativePatternScore(normalized)
                    lastOcrInferenceError = null
                    NativeOcrResult(
                        rawText = decoded.rawText,
                        normalizedPlate = normalized,
                        confidence = roundMetric(decoded.confidence),
                        characterConfidences = normalizeNativeCharacterConfidences(
                            decoded,
                            normalized,
                        ),
                        layout = layout,
                        category = nativePlateCategory(normalized),
                        patternScore = patternScore,
                        provider = "CPU_ONNX_PP_OCR",
                        preprocessingVariant = preprocessingVariant,
                    )
                }
            }
        } catch (error: Throwable) {
            lastOcrInferenceError = error.message ?: error.javaClass.simpleName
            null
        }
    }

    @Synchronized
    fun detectPlates(image: ImageProxy, minConfidence: Double): List<NativeOnnxDetection> {
        val env = environment ?: return emptyList()
        val model = sessions["detector"] ?: return emptyList()
        return try {
            val inputData = YuvLetterboxTensor.fromImage(image)
            val inputShape = longArrayOf(1, 3, YuvLetterboxTensor.targetSize.toLong(), YuvLetterboxTensor.targetSize.toLong())
            OnnxTensor.createTensor(env, FloatBuffer.wrap(inputData.tensor), inputShape).use { tensor ->
                model.session.run(mapOf(model.primaryInputName to tensor)).use { result ->
                    val output = result.get(0) as? OnnxTensor ?: return emptyList()
                    val shape = (output.info as? TensorInfo)?.shape ?: return emptyList()
                    val candidates = decodeYoloOutput(
                        raw = output.floatBuffer.duplicate(),
                        dims = shape,
                        imageWidth = image.width,
                        imageHeight = image.height,
                        letterbox = inputData.letterbox,
                        minConfidence = minConfidence,
                    )
                    lastDetectorInferenceError = null
                    candidates
                }
            }
        } catch (error: Throwable) {
            lastDetectorInferenceError = error.message ?: error.javaClass.simpleName
            emptyList()
        }
    }

    @Synchronized
    fun providerLabel(id: String, fallback: String): String {
        if (!sessions.containsKey(id)) return fallback
        return when (id) {
            "detector" -> if (lastDetectorInferenceError == null) "CPU_ONNX/FALLBACK" else "CPU_ONNX_READY/FALLBACK"
            "ocr" -> if (ocrDictionary.isNotEmpty() && lastOcrInferenceError == null) {
                "CPU_ONNX_PP_OCR/FALLBACK"
            } else {
                "CPU_ONNX_READY/FALLBACK"
            }
            else -> "CPU_ONNX_READY/FALLBACK"
        }
    }

    @Synchronized
    fun warnings(): List<String> {
        val sessionWarnings = errors.entries
            .sortedBy { it.key }
            .map { "ONNX ${it.key} unavailable: ${it.value}" }
        val detectorWarning = lastDetectorInferenceError
            ?.let { listOf("ONNX detector inference unavailable: $it") }
            ?: emptyList()
        val ocrWarning = lastOcrInferenceError
            ?.let { listOf("ONNX OCR inference unavailable: $it") }
            ?: emptyList()
        return sessionWarnings + detectorWarning + ocrWarning
    }

    @Synchronized
    fun status(): Map<String, Any?> {
        val ids = setOf("detector", "ocr", "environment", "plateQuality")
        val status = ids.associateWith { id ->
            sessions[id]?.toMap(extra = when (id) {
                "detector" -> mapOf("lastInferenceError" to lastDetectorInferenceError)
                "ocr" -> mapOf(
                    "dictionaryReady" to ocrDictionary.isNotEmpty(),
                    "dictionaryEntries" to ocrDictionary.size,
                    "lastInferenceError" to lastOcrInferenceError,
                )
                else -> emptyMap()
            }) ?: mapOf(
                "state" to "UNAVAILABLE",
                "error" to errors[id],
            )
        }
        return status
    }

    @Synchronized
    fun close() {
        sessions.values.forEach { it.close() }
        sessions.clear()
        errors.clear()
        ocrDictionary = emptyList()
        lastDetectorInferenceError = null
        lastOcrInferenceError = null
    }

    private fun loadOcrDictionary(path: String?) {
        if (path.isNullOrBlank()) {
            errors["ocrDictionary"] = "Native dictionary path was not staged."
            return
        }
        val file = File(path)
        if (!file.exists() || file.length() <= 0L) {
            errors["ocrDictionary"] = "File missing or empty at $path"
            return
        }
        try {
            val entries = file.readLines(Charsets.UTF_8)
                .map { it.trim() }
                .filter { it.isNotEmpty() }
                .toMutableList()
            entries.add(" ")
            ocrDictionary = entries.toList()
        } catch (error: Throwable) {
            errors["ocrDictionary"] = error.message ?: error.javaClass.simpleName
            ocrDictionary = emptyList()
        }
    }

    private fun loadSession(id: String, path: String) {
        val file = File(path)
        if (!file.exists() || file.length() <= 0L) {
            errors[id] = "File missing or empty at $path"
            return
        }
        try {
            val env = environment ?: OrtEnvironment.getEnvironment().also { environment = it }
            val options = OrtSession.SessionOptions()
            val session = env.createSession(file.absolutePath, options)
            sessions[id] = OrtModelSession(
                id = id,
                nativePath = file.absolutePath,
                sizeBytes = file.length(),
                session = session,
                inputNames = session.inputNames.toList(),
                outputNames = session.outputNames.toList(),
            )
        } catch (error: Throwable) {
            errors[id] = error.message ?: error.javaClass.simpleName
        }
    }

    private fun decodePpOcrOutput(raw: FloatBuffer, dims: LongArray): NativePpOcrDecodeResult {
        val positiveDims = mutableListOf<Int>()
        for (dimension in dims) {
            if (dimension > 0L && dimension <= Int.MAX_VALUE) {
                positiveDims.add(dimension.toInt())
            }
        }
        if (positiveDims.size < 2 || raw.limit() <= 0) {
            return NativePpOcrDecodeResult("", 0.0, emptyList())
        }

        val expectedClassCount = ocrDictionary.size + 1
        val sequenceLength: Int
        val classCount: Int
        val transposed: Boolean
        if (positiveDims.size >= 3) {
            val middle = positiveDims[positiveDims.size - 2]
            val last = positiveDims.last()
            transposed = middle == expectedClassCount && last != expectedClassCount
            sequenceLength = if (transposed) last else middle
            classCount = if (transposed) middle else last
        } else {
            sequenceLength = positiveDims[0]
            classCount = positiveDims[1]
            transposed = false
        }
        if (sequenceLength <= 0 || classCount <= 0) {
            return NativePpOcrDecodeResult("", 0.0, emptyList())
        }

        val chars = mutableListOf<String>()
        val characterConfidences = mutableListOf<NativeOcrCharacterConfidence>()
        var previousIndex = 0
        val maxTimesteps = min(sequenceLength, max(1, raw.limit() / max(1, classCount)))
        for (timestep in 0 until maxTimesteps) {
            var maxIndex = 0
            var maxScore = Float.NEGATIVE_INFINITY
            for (classIndex in 0 until classCount) {
                val offset = if (transposed) {
                    classIndex * sequenceLength + timestep
                } else {
                    timestep * classCount + classIndex
                }
                val score = if (offset >= 0 && offset < raw.limit()) raw.get(offset) else Float.NEGATIVE_INFINITY
                if (score > maxScore) {
                    maxScore = score
                    maxIndex = classIndex
                }
            }
            if (maxIndex != 0 && maxIndex != previousIndex) {
                val dictionaryIndex = maxIndex - 1
                if (dictionaryIndex >= 0 && dictionaryIndex < ocrDictionary.size) {
                    val char = ocrDictionary[dictionaryIndex]
                    if (char.isNotBlank()) {
                        chars.add(char)
                        characterConfidences.add(
                            NativeOcrCharacterConfidence(
                                char = char,
                                confidence = roundMetric(clamp(maxScore.toDouble(), 0.0, 1.0)),
                                position = characterConfidences.size,
                            ),
                        )
                    }
                }
            }
            previousIndex = maxIndex
        }

        val confidence = if (characterConfidences.isEmpty()) {
            0.0
        } else {
            characterConfidences.sumOf { it.confidence } / characterConfidences.size
        }
        return NativePpOcrDecodeResult(
            rawText = chars.joinToString(""),
            confidence = confidence,
            characterConfidences = characterConfidences,
        )
    }

    private fun normalizeNativeCharacterConfidences(
        decoded: NativePpOcrDecodeResult,
        normalizedPlate: String,
    ): List<NativeOcrCharacterConfidence> {
        val cleanedFromEngine = decoded.characterConfidences
            .map { item ->
                val normalizedChar = normalizeNativePlate(item.char)
                if (normalizedChar.length == 1) {
                    item.copy(char = normalizedChar)
                } else {
                    null
                }
            }
            .filterNotNull()
        if (cleanedFromEngine.size == normalizedPlate.length) {
            return cleanedFromEngine.mapIndexed { index, item -> item.copy(position = index) }
        }
        return normalizedPlate.mapIndexed { index, char ->
            NativeOcrCharacterConfidence(
                char = char.toString(),
                confidence = roundMetric(decoded.confidence),
                position = index,
            )
        }
    }

    private fun decodeYoloOutput(
        raw: FloatBuffer,
        dims: LongArray,
        imageWidth: Int,
        imageHeight: Int,
        letterbox: YoloLetterbox,
        minConfidence: Double,
    ): List<NativeOnnxDetection> {
        if (imageWidth <= 0 || imageHeight <= 0 || dims.size < 2) return emptyList()
        val shape = YoloOutputShape.fromDims(dims)
        val hasObjectness = shape.channelCount == 6 || shape.channelCount == 85
        val minBoxWidth = max(32.0, imageWidth * 0.022)
        val minBoxHeight = max(9.0, imageHeight * 0.008)
        val candidates = mutableListOf<YoloCandidate>()

        for (index in 0 until shape.sequenceLength) {
            fun read(channel: Int): Double {
                val offset = if (shape.transposed) {
                    index * shape.channelCount + channel
                } else {
                    channel * shape.sequenceLength + index
                }
                return if (offset >= 0 && offset < raw.limit()) raw.get(offset).toDouble() else Double.NaN
            }

            val cx = read(0)
            val cy = read(1)
            val width = read(2)
            val height = read(3)
            val objectness = if (hasObjectness) read(4) else 1.0
            val classChannel = if (hasObjectness) 5 else 4
            val classConfidence = read(classChannel)
            val confidence = objectness * classConfidence

            if (!listOf(cx, cy, width, height, confidence).all { it.isFinite() } || confidence < minConfidence) {
                continue
            }

            val realCx = (cx - letterbox.padX) / letterbox.scale
            val realCy = (cy - letterbox.padY) / letterbox.scale
            val realWidth = width / letterbox.scale
            val realHeight = height / letterbox.scale
            val left = clamp(realCx - realWidth / 2.0, 0.0, imageWidth.toDouble())
            val top = clamp(realCy - realHeight / 2.0, 0.0, imageHeight.toDouble())
            val right = clamp(realCx + realWidth / 2.0, 0.0, imageWidth.toDouble())
            val bottom = clamp(realCy + realHeight / 2.0, 0.0, imageHeight.toDouble())
            val finalWidth = (right - left).roundToInt().toDouble()
            val finalHeight = (bottom - top).roundToInt().toDouble()

            if (finalWidth >= minBoxWidth && finalHeight >= minBoxHeight) {
                candidates.add(
                    YoloCandidate(
                        x = left.roundToInt().toDouble(),
                        y = top.roundToInt().toDouble(),
                        width = finalWidth,
                        height = finalHeight,
                        confidence = roundMetric(confidence),
                    )
                )
            }
        }

        return applyYoloFiltersAndNms(candidates, imageWidth, imageHeight)
            .map { candidate ->
                NativeOnnxDetection(
                    bbox = NativeBbox(
                        x = roundMetric(candidate.x / imageWidth),
                        y = roundMetric(candidate.y / imageHeight),
                        width = roundMetric(candidate.width / imageWidth),
                        height = roundMetric(candidate.height / imageHeight),
                    ),
                    confidence = candidate.confidence,
                )
            }
    }

    private fun applyYoloFiltersAndNms(
        candidates: List<YoloCandidate>,
        imageWidth: Int,
        imageHeight: Int,
        iouThreshold: Double = 0.35,
    ): List<YoloCandidate> {
        val minWidth = max(28.0, imageWidth * 0.018)
        val minHeight = max(8.0, imageHeight * 0.007)
        val filtered = candidates.filter { candidate ->
            if (candidate.width < minWidth || candidate.height < minHeight || candidate.height <= 0.0) return@filter false
            val aspectRatio = candidate.width / candidate.height
            aspectRatio >= 0.65 && aspectRatio <= 7.2
        }
        val frameArea = imageWidth * imageHeight
        val sorted = filtered.sortedByDescending { it.rank(frameArea) }
        val selected = mutableListOf<YoloCandidate>()
        for (candidate in sorted) {
            val keep = selected.none { existing ->
                candidate.iou(existing) > min(iouThreshold, 0.35) || candidate.isMostlyContainedBy(existing)
            }
            if (keep) selected.add(candidate)
            if (selected.size >= 12) break
        }
        return selected
    }
}

private data class OrtModelSession(
    val id: String,
    val nativePath: String,
    val sizeBytes: Long,
    val session: OrtSession,
    val inputNames: List<String>,
    val outputNames: List<String>,
) {
    val primaryInputName: String
        get() = inputNames.firstOrNull() ?: "images"

    fun primaryInputName(fallback: String): String = inputNames.firstOrNull() ?: fallback

    fun toMap(extra: Map<String, Any?> = emptyMap()): Map<String, Any?> = mapOf(
        "state" to "READY",
        "id" to id,
        "nativePath" to nativePath,
        "sizeBytes" to sizeBytes,
        "inputNames" to inputNames,
        "outputNames" to outputNames,
    ) + extra

    fun close() {
        try {
            session.close()
        } catch (_: Throwable) {
        }
    }
}

private data class NativeOnnxDetection(
    val bbox: NativeBbox,
    val confidence: Double,
)

private object PpOcrTensor {
    fun fromBitmap(source: Bitmap): FloatArray {
        val target = Bitmap.createBitmap(PPOCR_TARGET_WIDTH, PPOCR_TARGET_HEIGHT, Bitmap.Config.ARGB_8888)
        try {
            val canvas = Canvas(target)
            val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.DITHER_FLAG)
            canvas.drawColor(Color.rgb(127, 127, 127))

            val scale = min(
                PPOCR_TARGET_WIDTH.toFloat() / max(1, source.width).toFloat(),
                PPOCR_TARGET_HEIGHT.toFloat() / max(1, source.height).toFloat(),
            )
            val drawWidth = max(1, (source.width * scale).roundToInt())
            val drawHeight = max(1, (source.height * scale).roundToInt())
            val offsetY = ((PPOCR_TARGET_HEIGHT - drawHeight) / 2.0).roundToInt()
            val destination = Rect(
                0,
                offsetY,
                min(PPOCR_TARGET_WIDTH, drawWidth),
                min(PPOCR_TARGET_HEIGHT, offsetY + drawHeight),
            )
            canvas.drawBitmap(source, null, destination, paint)

            val pixels = IntArray(PPOCR_TARGET_WIDTH * PPOCR_TARGET_HEIGHT)
            target.getPixels(pixels, 0, PPOCR_TARGET_WIDTH, 0, 0, PPOCR_TARGET_WIDTH, PPOCR_TARGET_HEIGHT)
            val channelArea = PPOCR_TARGET_WIDTH * PPOCR_TARGET_HEIGHT
            val tensor = FloatArray(channelArea * 3)
            for (index in 0 until channelArea) {
                val pixel = pixels[index]
                tensor[index] = normalizePpOcrChannel(Color.red(pixel))
                tensor[channelArea + index] = normalizePpOcrChannel(Color.green(pixel))
                tensor[channelArea * 2 + index] = normalizePpOcrChannel(Color.blue(pixel))
            }
            return tensor
        } finally {
            if (!target.isRecycled) target.recycle()
        }
    }

    private fun normalizePpOcrChannel(value: Int): Float =
        (((value / 255.0) - 0.5) / 0.5).toFloat()
}

private fun normalizeNativePlate(raw: String): String =
    raw.uppercase(Locale.US).filter { it in 'A'..'Z' || it in '0'..'9' }

private fun nativePatternScore(plate: String): Double {
    if (plate.length < 2 || plate.length > 10) return 0.0
    val letters = plate.count { it in 'A'..'Z' }
    val digits = plate.count { it in '0'..'9' }
    if (letters == 0 || digits == 0) return 0.16
    val standard = Regex("^[A-Z]{1,3}[0-9]{1,4}[A-Z]?$").matches(plate)
    val diplomatic = Regex("^[A-Z]{2}[0-9]{1,4}$").matches(plate)
    val lengthScore = clamp01(plate.length / 7.0)
    val structureScore = if (standard || diplomatic) 0.58 else 0.30
    val balanceScore = if (digits >= 2 && letters <= 5) 0.22 else 0.10
    return roundMetric(clamp01(structureScore + balanceScore + lengthScore * 0.20))
}

private fun nativePlateCategory(plate: String): String {
    if (Regex("^[A-Z]{1,3}[0-9]{1,4}[A-Z]?$").matches(plate)) return "STANDARD"
    if (plate.length in 2..10 && plate.any { it.isDigit() } && plate.any { it.isLetter() }) {
        return "UNKNOWN_VALID_CANDIDATE"
    }
    return "UNKNOWN"
}

private fun rankNativeOcrCandidate(candidate: NativeOcrResult): Double {
    val hasLetters = candidate.normalizedPlate.any { it in 'A'..'Z' }
    val hasDigits = candidate.normalizedPlate.any { it in '0'..'9' }
    val lengthScore = clamp01(candidate.normalizedPlate.length / 7.0)
    val layoutBonus = when (candidate.layout) {
        "TWO_LINE", "SQUARE" -> 0.06
        else -> 0.0
    }
    val recoveryPenalty = when (candidate.preprocessingVariant) {
        "ROTATE_180" -> 0.04
        "DESKEWED_ROTATION" -> 0.02
        else -> 0.0
    }
    val implausiblePenalty = if (hasLetters && hasDigits) 0.0 else 0.35
    return candidate.confidence * 0.48 +
        candidate.patternScore * 0.34 +
        lengthScore * 0.14 +
        layoutBonus -
        recoveryPenalty -
        implausiblePenalty
}

private data class YuvLetterboxTensor(
    val tensor: FloatArray,
    val letterbox: YoloLetterbox,
) {
    companion object {
        const val targetSize = 640

        fun fromImage(image: ImageProxy): YuvLetterboxTensor {
            val letterbox = YoloLetterbox(
                sourceWidth = image.width,
                sourceHeight = image.height,
                targetSize = targetSize,
            )
            val area = targetSize * targetSize
            val tensor = FloatArray(area * 3) { 127f / 255f }
            val yPlane = image.planes.getOrNull(0) ?: return YuvLetterboxTensor(tensor, letterbox)
            val uPlane = image.planes.getOrNull(1)
            val vPlane = image.planes.getOrNull(2)
            val yBuffer = yPlane.buffer.duplicate()
            val uBuffer = uPlane?.buffer?.duplicate()
            val vBuffer = vPlane?.buffer?.duplicate()
            val drawRight = letterbox.padX + letterbox.drawWidth
            val drawBottom = letterbox.padY + letterbox.drawHeight

            for (targetY in letterbox.padY until drawBottom) {
                val sourceY = min(image.height - 1, ((targetY - letterbox.padY) / letterbox.scale).toInt())
                for (targetX in letterbox.padX until drawRight) {
                    val sourceX = min(image.width - 1, ((targetX - letterbox.padX) / letterbox.scale).toInt())
                    val yValue = readPlane(yBuffer, yPlane.rowStride, yPlane.pixelStride, sourceX, sourceY)
                    val rgb = if (uPlane != null && vPlane != null && uBuffer != null && vBuffer != null) {
                        val uvX = sourceX / 2
                        val uvY = sourceY / 2
                        val uValue = readPlane(uBuffer, uPlane.rowStride, uPlane.pixelStride, uvX, uvY)
                        val vValue = readPlane(vBuffer, vPlane.rowStride, vPlane.pixelStride, uvX, uvY)
                        yuvToRgb(yValue, uValue, vValue)
                    } else {
                        Triple(yValue.toFloat(), yValue.toFloat(), yValue.toFloat())
                    }
                    val offset = targetY * targetSize + targetX
                    tensor[offset] = rgb.first / 255f
                    tensor[area + offset] = rgb.second / 255f
                    tensor[area * 2 + offset] = rgb.third / 255f
                }
            }
            return YuvLetterboxTensor(tensor, letterbox)
        }

        private fun readPlane(buffer: java.nio.ByteBuffer, rowStride: Int, pixelStride: Int, x: Int, y: Int): Int {
            val offset = y * max(1, rowStride) + x * max(1, pixelStride)
            return if (offset in 0 until buffer.limit()) buffer.get(offset).toInt() and 0xFF else 0
        }

        private fun yuvToRgb(y: Int, u: Int, v: Int): Triple<Float, Float, Float> {
            val yf = y.toFloat()
            val uf = u.toFloat() - 128f
            val vf = v.toFloat() - 128f
            val red = (yf + 1.402f * vf).coerceIn(0f, 255f)
            val green = (yf - 0.344136f * uf - 0.714136f * vf).coerceIn(0f, 255f)
            val blue = (yf + 1.772f * uf).coerceIn(0f, 255f)
            return Triple(red, green, blue)
        }
    }
}

private data class YoloLetterbox(
    val sourceWidth: Int,
    val sourceHeight: Int,
    val targetSize: Int = 640,
) {
    val scale: Double = min(targetSize.toDouble() / sourceWidth, targetSize.toDouble() / sourceHeight)
    val drawWidth: Int = (sourceWidth * scale).roundToInt()
    val drawHeight: Int = (sourceHeight * scale).roundToInt()
    val padX: Int = ((targetSize - drawWidth) / 2.0).roundToInt()
    val padY: Int = ((targetSize - drawHeight) / 2.0).roundToInt()
}

private data class YoloOutputShape(
    val sequenceLength: Int,
    val channelCount: Int,
    val transposed: Boolean,
) {
    companion object {
        fun fromDims(dims: LongArray): YoloOutputShape {
            val d1 = dims[dims.size - 2].toInt()
            val d2 = dims[dims.size - 1].toInt()
            if (isYoloChannelCount(d2) && !isYoloChannelCount(d1)) {
                return YoloOutputShape(sequenceLength = d1, channelCount = d2, transposed = true)
            }
            if (isYoloChannelCount(d1) && !isYoloChannelCount(d2)) {
                return YoloOutputShape(sequenceLength = d2, channelCount = d1, transposed = false)
            }
            return if (d1 > d2) {
                YoloOutputShape(sequenceLength = d1, channelCount = d2, transposed = true)
            } else {
                YoloOutputShape(sequenceLength = d2, channelCount = d1, transposed = false)
            }
        }

        private fun isYoloChannelCount(value: Int): Boolean = value == 5 || value == 6 || value == 85
    }
}

private data class YoloCandidate(
    val x: Double,
    val y: Double,
    val width: Double,
    val height: Double,
    val confidence: Double,
) {
    private val area: Double
        get() = width * height

    fun iou(other: YoloCandidate): Double {
        val left = max(x, other.x)
        val top = max(y, other.y)
        val right = min(x + width, other.x + other.width)
        val bottom = min(y + height, other.y + other.height)
        val intersection = max(0.0, right - left) * max(0.0, bottom - top)
        val union = area + other.area - intersection
        return if (union <= 0.0) 0.0 else intersection / union
    }

    fun rank(frameArea: Int): Double {
        val areaScore = min(1.0, area / max(1.0, frameArea * 0.08))
        return confidence * 0.68 + areaScore * 0.32
    }

    fun isMostlyContainedBy(outer: YoloCandidate): Boolean {
        val centerX = x + width / 2.0
        val centerY = y + height / 2.0
        val centerInside =
            centerX >= outer.x &&
                centerX <= outer.x + outer.width &&
                centerY >= outer.y &&
                centerY <= outer.y + outer.height
        return centerInside && area < outer.area * 0.65
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

private data class NativeEvidencePaths(
    val vehicleImagePath: String,
    val plateImagePath: String,
    val plateEnhancedImagePath: String,
    val plateBinaryImagePath: String,
    val plateTopLineImagePath: String,
    val plateBottomLineImagePath: String,
    val plateInnerTextImagePath: String,
    val plateCropWidth: Int,
    val plateCropHeight: Int,
    val preprocessingVariant: String,
    val preprocessingVariants: List<String>,
)

private class NativeEvidenceFrame private constructor(
    private val bitmap: Bitmap,
) {
    fun recycle() {
        if (!bitmap.isRecycled) bitmap.recycle()
    }

    fun copyFrame(): NativeEvidenceFrame? {
        return try {
            NativeEvidenceFrame(bitmap.copy(Bitmap.Config.ARGB_8888, false))
        } catch (_: Throwable) {
            null
        }
    }

    fun recognizePlate(
        ortRuntime: PlateqOrtRuntime,
        bbox: NativeBbox,
        qualityClass: String,
    ): NativeOcrResult? {
        val crop = crop(bbox)
        val candidates = mutableListOf<NativeOcrResult>()
        try {
            val enhancedCrop = enhancePlateCrop(crop)
            try {
                val aspect = enhancedCrop.width.toDouble() / max(1, enhancedCrop.height).toDouble()
                val baseLayout = when {
                    aspect < 1.6 -> "SQUARE"
                    aspect < 2.3 -> "TWO_LINE"
                    else -> "SINGLE_LINE"
                }
                recognizeCandidate(
                    ortRuntime,
                    enhancedCrop,
                    "ADAPTIVE_CONTRAST",
                    baseLayout,
                    candidates,
                )

                val innerTextCrop = innerTextCrop(enhancedCrop)
                try {
                    recognizeCandidate(
                        ortRuntime,
                        innerTextCrop,
                        "INNER_TEXT",
                        baseLayout,
                        candidates,
                    )
                } finally {
                    if (!innerTextCrop.isRecycled) innerTextCrop.recycle()
                }

                if (baseLayout != "SINGLE_LINE") {
                    recognizeTwoLineCandidate(ortRuntime, enhancedCrop, baseLayout)?.let(candidates::add)
                }

                val bestFirstPass = candidates.maxByOrNull(::rankNativeOcrCandidate)
                val needsRecovery = bestFirstPass == null ||
                    bestFirstPass.confidence < 0.42 ||
                    bestFirstPass.patternScore < 0.42
                val shouldDeskew = qualityClass == "SLIGHT_ROTATION" || aspect < 2.0 || aspect > 5.8
                if (shouldDeskew) {
                    for (degrees in listOf(-6f, 6f)) {
                        val deskewedCrop = deskewPlateCrop(enhancedCrop, degrees)
                        try {
                            recognizeCandidate(
                                ortRuntime,
                                deskewedCrop,
                                "DESKEWED_ROTATION",
                                baseLayout,
                                candidates,
                            )
                        } finally {
                            if (!deskewedCrop.isRecycled) deskewedCrop.recycle()
                        }
                    }
                }

                if (needsRecovery) {
                    val rotatedCrop = rotatePlateCrop(enhancedCrop, 180f)
                    try {
                        recognizeCandidate(
                            ortRuntime,
                            rotatedCrop,
                            "ROTATE_180",
                            baseLayout,
                            candidates,
                        )
                    } finally {
                        if (!rotatedCrop.isRecycled) rotatedCrop.recycle()
                    }
                }
            } finally {
                if (enhancedCrop !== crop && !enhancedCrop.isRecycled) enhancedCrop.recycle()
            }
        } finally {
            if (crop !== bitmap && !crop.isRecycled) crop.recycle()
        }

        return candidates
            .filter { it.normalizedPlate.length >= 2 }
            .maxByOrNull(::rankNativeOcrCandidate)
    }

    fun writeEvidenceFiles(cacheDir: File, trackNumber: Int, bbox: NativeBbox, frameNumber: Long): NativeEvidencePaths? {
        return try {
            val directory = File(cacheDir, "plateq-evidence").apply { mkdirs() }
            val prefix = "track-$trackNumber-$frameNumber-${System.currentTimeMillis()}"
            val vehicleFile = File(directory, "$prefix-vehicle.jpg")
            val plateFile = File(directory, "$prefix-plate.jpg")
            val enhancedPlateFile = File(directory, "$prefix-plate-enhanced.jpg")
            val binaryPlateFile = File(directory, "$prefix-plate-binary.jpg")
            val topLinePlateFile = File(directory, "$prefix-plate-top-line.jpg")
            val bottomLinePlateFile = File(directory, "$prefix-plate-bottom-line.jpg")
            val innerTextPlateFile = File(directory, "$prefix-plate-inner-text.jpg")
            writeJpeg(bitmap, vehicleFile, 82)
            val crop = crop(bbox)
            try {
                writeJpeg(crop, plateFile, 90)
                val enhancedCrop = enhancePlateCrop(crop)
                try {
                    writeJpeg(enhancedCrop, enhancedPlateFile, 92)
                    val binaryCrop = binarizePlateCrop(enhancedCrop)
                    val topLineCrop = splitPlateCrop(enhancedCrop, topHalf = true)
                    val bottomLineCrop = splitPlateCrop(enhancedCrop, topHalf = false)
                    val innerTextCrop = innerTextCrop(enhancedCrop)
                    try {
                        writeJpeg(binaryCrop, binaryPlateFile, 92)
                        writeJpeg(topLineCrop, topLinePlateFile, 92)
                        writeJpeg(bottomLineCrop, bottomLinePlateFile, 92)
                        writeJpeg(innerTextCrop, innerTextPlateFile, 92)
                    } finally {
                        if (!binaryCrop.isRecycled) binaryCrop.recycle()
                        if (!topLineCrop.isRecycled) topLineCrop.recycle()
                        if (!bottomLineCrop.isRecycled) bottomLineCrop.recycle()
                        if (!innerTextCrop.isRecycled) innerTextCrop.recycle()
                    }
                } finally {
                    if (enhancedCrop !== crop && !enhancedCrop.isRecycled) enhancedCrop.recycle()
                }
                NativeEvidencePaths(
                    vehicleImagePath = vehicleFile.absolutePath,
                    plateImagePath = plateFile.absolutePath,
                    plateEnhancedImagePath = enhancedPlateFile.absolutePath,
                    plateBinaryImagePath = binaryPlateFile.absolutePath,
                    plateTopLineImagePath = topLinePlateFile.absolutePath,
                    plateBottomLineImagePath = bottomLinePlateFile.absolutePath,
                    plateInnerTextImagePath = innerTextPlateFile.absolutePath,
                    plateCropWidth = crop.width,
                    plateCropHeight = crop.height,
                    preprocessingVariant = "ADAPTIVE_CONTRAST",
                    preprocessingVariants = listOf(
                        "RAW_CROP",
                        "ADAPTIVE_CONTRAST",
                        "BINARY_THRESHOLD",
                        "TOP_LINE",
                        "BOTTOM_LINE",
                        "INNER_TEXT",
                    ),
                )
            } finally {
                if (crop !== bitmap && !crop.isRecycled) crop.recycle()
            }
        } catch (_: Throwable) {
            null
        }
    }

    private fun recognizeCandidate(
        ortRuntime: PlateqOrtRuntime,
        crop: Bitmap,
        preprocessingVariant: String,
        layout: String,
        candidates: MutableList<NativeOcrResult>,
    ) {
        ortRuntime.recognizePlateCrop(
            crop = crop,
            preprocessingVariant = preprocessingVariant,
            layout = layout,
        )?.let(candidates::add)
    }

    private fun recognizeTwoLineCandidate(
        ortRuntime: PlateqOrtRuntime,
        source: Bitmap,
        layout: String,
    ): NativeOcrResult? {
        val topLineCrop = splitPlateCrop(source, topHalf = true)
        val bottomLineCrop = splitPlateCrop(source, topHalf = false)
        return try {
            val top = ortRuntime.recognizePlateCrop(topLineCrop, "TOP_LINE", "TWO_LINE")
            val bottom = ortRuntime.recognizePlateCrop(bottomLineCrop, "BOTTOM_LINE", "TWO_LINE")
            val rawText = "${top?.normalizedPlate.orEmpty()}${bottom?.normalizedPlate.orEmpty()}"
            val normalized = normalizeNativePlate(rawText)
            if (normalized.length < 2) return null
            val confidence = roundMetric(
                listOfNotNull(top?.confidence, bottom?.confidence)
                    .takeIf { it.isNotEmpty() }
                    ?.average()
                    ?: 0.0,
            )
            val split = top?.normalizedPlate?.length ?: 0
            NativeOcrResult(
                rawText = rawText,
                normalizedPlate = normalized,
                confidence = confidence,
                characterConfidences = normalized.mapIndexed { index, char ->
                    NativeOcrCharacterConfidence(
                        char = char.toString(),
                        confidence = if (index < split) {
                            top?.confidence ?: confidence
                        } else {
                            bottom?.confidence ?: confidence
                        },
                        position = index,
                    )
                },
                layout = layout,
                category = nativePlateCategory(normalized),
                patternScore = nativePatternScore(normalized),
                provider = "CPU_ONNX_PP_OCR",
                preprocessingVariant = "TWO_LINE_SPLIT",
            )
        } finally {
            if (!topLineCrop.isRecycled) topLineCrop.recycle()
            if (!bottomLineCrop.isRecycled) bottomLineCrop.recycle()
        }
    }

    private fun crop(bbox: NativeBbox): Bitmap {
        val left = clamp((bbox.x * bitmap.width).toInt().toDouble(), 0.0, (bitmap.width - 2).toDouble()).toInt()
        val top = clamp((bbox.y * bitmap.height).toInt().toDouble(), 0.0, (bitmap.height - 2).toDouble()).toInt()
        val right = clamp(((bbox.x + bbox.width) * bitmap.width).toInt().toDouble(), (left + 1).toDouble(), bitmap.width.toDouble()).toInt()
        val bottom = clamp(((bbox.y + bbox.height) * bitmap.height).toInt().toDouble(), (top + 1).toDouble(), bitmap.height.toDouble()).toInt()
        val cropWidth = max(1, right - left)
        val cropHeight = max(1, bottom - top)
        return Bitmap.createBitmap(bitmap, left, top, cropWidth, cropHeight)
    }

    private fun enhancePlateCrop(source: Bitmap): Bitmap {
        val width = source.width
        val height = source.height
        val pixels = IntArray(width * height)
        source.getPixels(pixels, 0, width, 0, 0, width, height)
        var minLuma = 255
        var maxLuma = 0
        val lumas = IntArray(pixels.size)
        for (index in pixels.indices) {
            val pixel = pixels[index]
            val luma = ((Color.red(pixel) * 0.299) + (Color.green(pixel) * 0.587) + (Color.blue(pixel) * 0.114)).toInt()
            lumas[index] = luma
            minLuma = min(minLuma, luma)
            maxLuma = max(maxLuma, luma)
        }
        val spread = max(32, maxLuma - minLuma)
        for (index in pixels.indices) {
            val normalized = clamp(((lumas[index] - minLuma) * 255.0) / spread, 0.0, 255.0)
            val boosted = clamp((normalized - 128.0) * 1.18 + 128.0, 0.0, 255.0).toInt()
            pixels[index] = Color.rgb(boosted, boosted, boosted)
        }
        return Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).apply {
            setPixels(pixels, 0, width, 0, 0, width, height)
        }
    }

    private fun binarizePlateCrop(source: Bitmap): Bitmap {
        val width = source.width
        val height = source.height
        val pixels = IntArray(width * height)
        source.getPixels(pixels, 0, width, 0, 0, width, height)
        val lumas = IntArray(pixels.size)
        var total = 0L
        for (index in pixels.indices) {
            val pixel = pixels[index]
            val luma = ((Color.red(pixel) * 0.299) + (Color.green(pixel) * 0.587) + (Color.blue(pixel) * 0.114)).toInt()
            lumas[index] = luma
            total += luma.toLong()
        }
        val threshold = if (pixels.isEmpty()) 128 else (total / pixels.size).toInt()
        for (index in pixels.indices) {
            val value = if (lumas[index] >= threshold) 255 else 0
            pixels[index] = Color.rgb(value, value, value)
        }
        return Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).apply {
            setPixels(pixels, 0, width, 0, 0, width, height)
        }
    }

    private fun splitPlateCrop(source: Bitmap, topHalf: Boolean): Bitmap {
        val height = max(1, source.height / 2)
        val top = if (topHalf) 0 else max(0, source.height - height)
        return Bitmap.createBitmap(source, 0, top, source.width, height)
    }

    private fun innerTextCrop(source: Bitmap): Bitmap {
        val insetX = min(source.width / 4, max(1, (source.width * 0.06).toInt()))
        val insetY = min(source.height / 3, max(1, (source.height * 0.14).toInt()))
        val cropWidth = max(1, source.width - insetX * 2)
        val cropHeight = max(1, source.height - insetY * 2)
        return Bitmap.createBitmap(source, insetX, insetY, cropWidth, cropHeight)
    }

    private fun deskewPlateCrop(source: Bitmap, degrees: Float): Bitmap {
        val output = Bitmap.createBitmap(source.width, source.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.DITHER_FLAG)
        canvas.drawColor(Color.BLACK)
        canvas.save()
        canvas.rotate(-degrees, source.width / 2f, source.height / 2f)
        canvas.drawBitmap(source, 0f, 0f, paint)
        canvas.restore()
        return output
    }

    private fun rotatePlateCrop(source: Bitmap, degrees: Float): Bitmap {
        val matrix = Matrix().apply { postRotate(degrees) }
        return Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true)
    }

    private fun writeJpeg(source: Bitmap, file: File, quality: Int) {
        file.outputStream().use { output ->
            source.compress(Bitmap.CompressFormat.JPEG, quality, output)
        }
    }

    companion object {
        fun fromImage(image: ImageProxy, maxLongEdge: Int = 640): NativeEvidenceFrame? {
            return try {
                val plane = image.planes.firstOrNull() ?: return null
                val source = plane.buffer.duplicate()
                val width = image.width
                val height = image.height
                val scale = min(1.0, maxLongEdge.toDouble() / max(width, height).toDouble())
                val targetWidth = max(1, (width * scale).toInt())
                val targetHeight = max(1, (height * scale).toInt())
                val rowStride = max(1, plane.rowStride)
                val pixelStride = max(1, plane.pixelStride)
                val pixels = IntArray(targetWidth * targetHeight)

                for (y in 0 until targetHeight) {
                    val sourceY = min(height - 1, (y / scale).toInt())
                    for (x in 0 until targetWidth) {
                        val sourceX = min(width - 1, (x / scale).toInt())
                        val index = sourceY * rowStride + sourceX * pixelStride
                        val value = if (index in 0 until source.limit()) source.get(index).toInt() and 0xFF else 0
                        pixels[y * targetWidth + x] = Color.rgb(value, value, value)
                    }
                }

                val bitmap = Bitmap.createBitmap(targetWidth, targetHeight, Bitmap.Config.ARGB_8888)
                bitmap.setPixels(pixels, 0, targetWidth, 0, 0, targetWidth, targetHeight)
                NativeEvidenceFrame(bitmap)
            } catch (_: Throwable) {
                null
            }
        }
    }
}

private data class NativeFrameAnalysis(
    val detections: List<NativeDetection>,
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
    fun analyze(
        image: ImageProxy,
        frameNumber: Long,
        threshold: Double,
        ortRuntime: PlateqOrtRuntime,
    ): NativeFrameAnalysis {
        val stats = sampleLuma(image)
        val environment = classifyEnvironment(stats)
        val onnxDetections = ortRuntime.detectPlates(image, threshold)
        val fallbackBox = candidateBox(image.width, image.height, frameNumber, stats)
        val detectorConfidence = onnxDetections.maxOfOrNull { it.confidence } ?: roundMetric(
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
                    boxSizeScore(onnxDetections.firstOrNull()?.bbox ?: fallbackBox) * 0.12 -
                    stats.glareRatio * 0.22,
            ),
        )
        val qualityClass = classifyQuality(stats, qualityScore)
        val detections = if (onnxDetections.isNotEmpty()) {
            onnxDetections.map { detection ->
                val perBoxQualityScore = roundMetric(
                    clamp01(
                        detection.confidence * 0.34 +
                            stats.exposureScore * 0.18 +
                            stats.contrastScore * 0.20 +
                            stats.sharpnessScore * 0.14 +
                            boxSizeScore(detection.bbox) * 0.14 -
                            stats.glareRatio * 0.22,
                    ),
                )
                NativeDetection(
                    bbox = detection.bbox,
                    confidence = perBoxQualityScore,
                    detectorConfidence = detection.confidence,
                    motionScore = stats.motionScore,
                    qualityScore = perBoxQualityScore,
                    qualityClass = classifyQuality(stats, perBoxQualityScore),
                )
            }
        } else if (detectorConfidence >= max(0.18, threshold * 0.70) && qualityScore >= 0.20) {
            listOf(
                NativeDetection(
                    bbox = fallbackBox,
                    confidence = qualityScore,
                    detectorConfidence = detectorConfidence,
                    motionScore = stats.motionScore,
                    qualityScore = qualityScore,
                    qualityClass = qualityClass,
                )
            )
        } else {
            emptyList()
        }
        return NativeFrameAnalysis(
            detections = detections,
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
        tracks.forEach { it.release() }
        tracks.clear()
        nextTrackNumber = 1
    }

    fun update(
        detections: List<NativeDetection>,
        evidenceFrame: NativeEvidenceFrame?,
        frameNumber: Long,
        timestampMs: Long,
        maxTracks: Int,
    ) {
        if (detections.isEmpty()) {
            evidenceFrame?.recycle()
            ageTracks(frameNumber, timestampMs)
            return
        }

        val maxActiveTracks = max(1, maxTracks)
        val sortedDetections = detections
            .sortedByDescending { it.detectorConfidence * 0.70 + it.qualityScore * 0.30 }
            .take(maxActiveTracks)
        val usedDetectionIndices = mutableSetOf<Int>()
        val activeTracks = tracks.filter { it.state != "REMOVED" }.toMutableSet()

        for (track in activeTracks.sortedByDescending { it.confidence }) {
            var bestIndex = -1
            var bestIou = 0.0
            sortedDetections.forEachIndexed { index, detection ->
                if (index in usedDetectionIndices) return@forEachIndexed
                val iou = track.bbox.iou(detection.bbox)
                if (iou >= 0.20 && iou > bestIou) {
                    bestIndex = index
                    bestIou = iou
                }
            }
            if (bestIndex >= 0) {
                val detection = sortedDetections[bestIndex]
                track.applyDetection(
                    detection,
                    evidenceFrame?.copyFrame(),
                    frameNumber,
                    timestampMs,
                )
                usedDetectionIndices.add(bestIndex)
                activeTracks.remove(track)
            }
        }

        sortedDetections.forEachIndexed { index, detection ->
            if (index in usedDetectionIndices) return@forEachIndexed
            val frameCopy = evidenceFrame?.copyFrame()
            if (tracks.size < maxActiveTracks) {
                tracks.add(NativeTrack(nextTrackNumber++, detection, frameCopy, frameNumber, timestampMs))
            } else {
                val replaced = tracks
                    .filter { it.state != "REMOVED" }
                    .minByOrNull { it.confidence }
                    ?.takeIf { detection.confidence > it.confidence }
                if (replaced != null) {
                    replaced.replaceWith(nextTrackNumber++, detection, frameCopy, frameNumber, timestampMs)
                } else {
                    frameCopy?.recycle()
                }
            }
        }

        evidenceFrame?.recycle()
        ageTracks(frameNumber, timestampMs)
    }

    fun snapshot(): List<Map<String, Any?>> {
        return tracks
            .filter { it.state != "REMOVED" }
            .sortedBy { it.trackNumber }
            .map { it.toMap() }
    }

    fun ocrCandidates(frameNumber: Long, maxCount: Int): List<NativeTrack> {
        return tracks
            .filter { it.shouldEmitOcr(frameNumber) }
            .sortedByDescending { it.qualityScore }
            .take(max(1, maxCount))
    }

    private fun ageTracks(frameNumber: Long, timestampMs: Long) {
        tracks.forEach { it.age(frameNumber, timestampMs) }
        val iterator = tracks.iterator()
        while (iterator.hasNext()) {
            val track = iterator.next()
            if (track.state == "REMOVED") {
                track.release()
                iterator.remove()
            }
        }
    }
}

private class NativeTrack(
    var trackNumber: Int,
    detection: NativeDetection,
    evidenceFrame: NativeEvidenceFrame?,
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
    var currentPlate = ""
    var currentPlateConfidence = 0.0
    private var firstFrame = frameNumber
    private var lastSeenFrame = frameNumber
    private var lastSeenMs = timestampMs
    private var detectionCount = 1
    private var lastOcrFrame = -9999L
    private var ocrEmissionCount = 0
    private var bestEvidenceFrame: NativeEvidenceFrame? = evidenceFrame
    private var bestEvidenceBbox = detection.bbox
    private var bestEvidenceScore = evidenceScore(detection)

    fun applyDetection(
        detection: NativeDetection,
        evidenceFrame: NativeEvidenceFrame?,
        frameNumber: Long,
        timestampMs: Long,
    ) {
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
        retainBestEvidence(detection, evidenceFrame)
    }

    fun replaceWith(
        newTrackNumber: Int,
        detection: NativeDetection,
        evidenceFrame: NativeEvidenceFrame?,
        frameNumber: Long,
        timestampMs: Long,
    ) {
        release()
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
        currentPlate = ""
        currentPlateConfidence = 0.0
        lastOcrFrame = -9999L
        ocrEmissionCount = 0
        bestEvidenceFrame = evidenceFrame
        bestEvidenceBbox = detection.bbox
        bestEvidenceScore = evidenceScore(detection)
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
        "currentPlate" to currentPlate,
        "currentPlateConfidence" to currentPlateConfidence,
        "matchType" to "NONE",
        "ageFrames" to (lastSeenFrame - firstFrame + 1),
        "detections" to detectionCount,
    )

    fun shouldEmitOcr(frameNumber: Long): Boolean {
        if (state != "VISIBLE") return false
        if (pipelineState != "READY_FOR_OCR") return false
        if (confidence < 0.48 || qualityScore < 0.38) return false
        val interval = if (ocrEmissionCount == 0) 0 else 9
        return frameNumber - lastOcrFrame >= interval
    }

    fun markOcr(plate: String, confidence: Double, frameNumber: Long) {
        currentPlate = plate
        currentPlateConfidence = confidence
        lastOcrFrame = frameNumber
        ocrEmissionCount += 1
        pipelineState = "OCR_CONFIRMED"
    }

    fun writeBestEvidenceFiles(cacheDir: File, frameNumber: Long): NativeEvidencePaths? {
        return bestEvidenceFrame?.writeEvidenceFiles(cacheDir, trackNumber, bestEvidenceBbox, frameNumber)
    }

    fun recognizeBestPlate(ortRuntime: PlateqOrtRuntime): NativeOcrResult? {
        return bestEvidenceFrame?.recognizePlate(
            ortRuntime = ortRuntime,
            bbox = bestEvidenceBbox,
            qualityClass = qualityClass,
        )
    }

    fun release() {
        bestEvidenceFrame?.recycle()
        bestEvidenceFrame = null
    }

    private fun retainBestEvidence(detection: NativeDetection, evidenceFrame: NativeEvidenceFrame?) {
        if (evidenceFrame == null) return
        val candidateScore = evidenceScore(detection)
        if (bestEvidenceFrame == null || candidateScore >= bestEvidenceScore) {
            bestEvidenceFrame?.recycle()
            bestEvidenceFrame = evidenceFrame
            bestEvidenceBbox = detection.bbox
            bestEvidenceScore = candidateScore
        } else {
            evidenceFrame.recycle()
        }
    }

    private fun evidenceScore(detection: NativeDetection): Double {
        val stability = clamp01(detectionCount / 4.0)
        val sizeScore = clamp01(detection.bbox.width * detection.bbox.height / 0.045)
        return roundMetric(
            detection.qualityScore * 0.42 +
                detection.detectorConfidence * 0.28 +
                sizeScore * 0.18 +
                stability * 0.12,
        )
    }

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
