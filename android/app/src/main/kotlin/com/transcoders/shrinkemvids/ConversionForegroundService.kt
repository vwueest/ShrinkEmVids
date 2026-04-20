package com.transcoders.shrinkemvids

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ContentValues
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.MediaStore
import androidx.core.app.NotificationCompat
import com.antonkarpenko.ffmpegkit.FFmpegKit
import com.antonkarpenko.ffmpegkit.FFmpegSession
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import java.io.File
import kotlin.coroutines.resume

class ConversionForegroundService : Service() {

    companion object {
        const val ACTION_START = "com.transcoders.shrinkemvids.ACTION_START"
        const val ACTION_CANCEL = "com.transcoders.shrinkemvids.ACTION_CANCEL"
        const val ACTION_SKIP = "com.transcoders.shrinkemvids.ACTION_SKIP"

        private const val NOTIFICATION_ID = 1001
        private const val DONE_NOTIFICATION_ID = 1002
        const val CHANNEL_ID = "shrinkemvids_conversion"

        private val mainHandler = Handler(Looper.getMainLooper())

        // Set by MainActivity's EventChannel StreamHandler
        var eventSink: EventChannel.EventSink? = null

        // Live state (read by getState MethodChannel handler)
        @Volatile var isRunning = false
        @Volatile var currentFileIndex = 0
        @Volatile var totalFiles = 0
        @Volatile var currentFileName = ""
        @Volatile var currentProgress = 0.0

        // Skip / cancel flags (written from MethodChannel, read from IO coroutine)
        @Volatile var skipRequested = false
        @Volatile var cancelRequested = false
        @Volatile var currentSessionId: Long? = null

        fun sendEvent(event: Map<String, Any?>) {
            mainHandler.post { eventSink?.success(event) }
        }
    }

    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val notificationManager by lazy {
        getSystemService(NotificationManager::class.java)
    }
    private lateinit var wakeLock: PowerManager.WakeLock
    private var lastNotifUpdateMs = 0L

    // ── Lifecycle ────────────────────────────────────────────────────────────

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        val pm = getSystemService(PowerManager::class.java)
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ShrinkEmVids::Encoding")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CANCEL -> {
                cancelRequested = true
                FFmpegKit.cancel()
                return START_NOT_STICKY
            }
            ACTION_SKIP -> {
                skipRequested = true
                currentSessionId?.let { FFmpegKit.cancel(it) }
                return START_NOT_STICKY
            }
        }

        // ── Extract encoding parameters from intent ───────────────────────────
        val filePaths = intent?.getStringArrayListExtra("filePaths") ?: return START_NOT_STICKY
        val displayNames = intent.getStringArrayListExtra("displayNames") ?: ArrayList()
        val outputFileNames = intent.getStringArrayListExtra("outputFileNames") ?: ArrayList()
        val inputSizesArr = intent.getLongArrayExtra("inputSizes") ?: LongArray(0)
        val durationsArr = intent.getLongArrayExtra("durationMsList") ?: LongArray(0)
        val maxHeight = intent.getIntExtra("maxHeight", -1).takeIf { it > 0 }
        val videoBitrateKbps = intent.getIntExtra("videoBitrateKbps", 3200)
        val audioBitrateKbps = intent.getIntExtra("audioBitrateKbps", 128)
        val maxRateKbps = intent.getIntExtra("maxRateKbps", (videoBitrateKbps * 1.13).toInt())
        val bufSizeKbps = intent.getIntExtra("bufSizeKbps", videoBitrateKbps * 2)

        isRunning = true
        cancelRequested = false
        skipRequested = false

        // Enter foreground immediately with an indeterminate notification
        startForeground(NOTIFICATION_ID, buildNotification("Starting…", -1, 0, filePaths.size))

        serviceScope.launch {
            try {
                if (!wakeLock.isHeld) wakeLock.acquire(12 * 60 * 60 * 1000L) // max 12 h
                runEncoding(
                    filePaths, displayNames, outputFileNames,
                    inputSizesArr, durationsArr,
                    maxHeight, videoBitrateKbps, audioBitrateKbps, maxRateKbps, bufSizeKbps
                )
            } finally {
                if (wakeLock.isHeld) wakeLock.release()
                isRunning = false
                stopSelf()
            }
        }

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        serviceScope.cancel()
        if (::wakeLock.isInitialized && wakeLock.isHeld) wakeLock.release()
    }

    // ── Encoding loop ────────────────────────────────────────────────────────

    private suspend fun runEncoding(
        filePaths: List<String>,
        displayNames: List<String>,
        outputFileNames: List<String>,
        inputSizes: LongArray,
        durationsMsList: LongArray,
        maxHeight: Int?,
        videoBitrateKbps: Int,
        audioBitrateKbps: Int,
        maxRateKbps: Int,
        bufSizeKbps: Int,
    ) {
        val results = mutableListOf<Map<String, Any?>>()
        val total = filePaths.size

        for (i in filePaths.indices) {
            if (cancelRequested) break
            skipRequested = false

            val path = filePaths[i]
            val displayName = displayNames.getOrElse(i) { File(path).name }
            val outputFileName = outputFileNames.getOrElse(i) { "${displayName}_compressed.mp4" }
            val inputSize = if (i < inputSizes.size) inputSizes[i] else 0L
            val durationMs = if (i < durationsMsList.size && durationsMsList[i] > 0) durationsMsList[i] else null

            currentFileIndex = i
            totalFiles = total
            currentFileName = displayName
            currentProgress = 0.0

            pushNotif(displayName, 0, i, total)
            sendEvent(progressEvent(displayName, 0, i, total))

            val extDir = getExternalFilesDir(null)
            val tempPath = "${extDir?.absolutePath}/$outputFileName"

            val args = buildArgs(path, tempPath, maxHeight, videoBitrateKbps, audioBitrateKbps, maxRateKbps, bufSizeKbps)

            // ── Run ffmpeg ────────────────────────────────────────────────────
            val completedSession = suspendCancellableCoroutine<FFmpegSession> { cont ->
                val session = FFmpegKit.executeWithArgumentsAsync(
                    args.toTypedArray(),
                    { s -> if (cont.isActive) cont.resume(s) },
                    null, // log callback – omit to avoid noise
                    { stats ->
                        if (durationMs != null && durationMs > 0) {
                            val pct = ((stats.time.toDouble() / durationMs.toDouble()) * 100)
                                .coerceIn(0.0, 100.0).toInt()
                            currentProgress = pct / 100.0
                            val now = System.currentTimeMillis()
                            if (now - lastNotifUpdateMs >= 800) {
                                lastNotifUpdateMs = now
                                pushNotif(displayName, pct, i, total)
                                sendEvent(progressEvent(displayName, pct, i, total))
                            }
                        }
                    }
                )
                currentSessionId = session.sessionId
                cont.invokeOnCancellation { FFmpegKit.cancel(session.sessionId) }
            }
            currentSessionId = null

            // ── Post-session handling ─────────────────────────────────────────
            if (skipRequested) {
                File(tempPath).delete()
                results.add(resultMap(path, tempPath, inputSize, 0L, false, "Skipped"))
                sendEvent(mapOf("type" to "fileSkipped", "file" to displayName, "fileIndex" to i))
                skipRequested = false
                continue
            }

            if (cancelRequested) {
                File(tempPath).delete()
                break
            }

            if (completedSession.returnCode?.isValueSuccess == true) {
                val outputSize = File(tempPath).length()
                val destPath = copyToMovies(tempPath, outputFileName)
                File(tempPath).delete()
                results.add(resultMap(path, destPath ?: tempPath, inputSize, outputSize, true, null))
                sendEvent(mapOf(
                    "type" to "fileComplete",
                    "file" to displayName,
                    "fileIndex" to i,
                    "inputSize" to inputSize,
                    "outputSize" to outputSize,
                ))
            } else {
                File(tempPath).delete()
                val errMsg = "FFmpeg error: ${completedSession.returnCode?.value}"
                results.add(resultMap(path, tempPath, inputSize, 0L, false, errMsg))
                sendEvent(mapOf("type" to "error", "file" to displayName, "fileIndex" to i, "message" to errMsg))
            }
        }

        // ── Batch finished ────────────────────────────────────────────────────
        val successCount = results.count { it["success"] == true }
        if (cancelRequested) {
            sendEvent(mapOf("type" to "cancelled", "results" to results))
            showDoneNotification("Conversion cancelled", "$successCount file(s) completed")
        } else {
            sendEvent(mapOf("type" to "done", "results" to results))
            showDoneNotification("Conversion complete", "$successCount of $total file(s) converted")
        }
    }

    // ── FFmpeg args builder ──────────────────────────────────────────────────

    private fun buildArgs(
        input: String, output: String, maxHeight: Int?,
        videoBitrateKbps: Int, audioBitrateKbps: Int, maxRateKbps: Int, bufSizeKbps: Int,
    ): List<String> {
        val args = mutableListOf("-i", input)
        if (maxHeight != null) {
            // Handles both landscape and portrait sources correctly
            args += listOf("-vf", "scale='if(gte(iw,ih),-2,$maxHeight)':'if(gte(ih,iw),-2,$maxHeight)'")
        }
        args += listOf(
            "-c:v", "hevc_mediacodec",
            "-pix_fmt", "yuv420p",
            "-profile:v", "main",
            "-level", "4.0",
            "-b:v", "${videoBitrateKbps}k",
            "-maxrate", "${maxRateKbps}k",
            "-bufsize", "${bufSizeKbps}k",
            "-g", "30",
            "-force_key_frames", "expr:gte(t,n_forced*2)",
            "-movflags", "+faststart",
            "-map_metadata", "0",
            "-c:a", "aac",
            "-b:a", "${audioBitrateKbps}k",
            "-y", output,
        )
        return args
    }

    // ── MediaStore copy ──────────────────────────────────────────────────────

    private fun copyToMovies(sourcePath: String, filename: String): String? {
        // Look up the original file's DATE_TAKEN so Google Photos places the
        // compressed copy right next to the original in the timeline.
        var dateTakenMs: Long? = null
        try {
            contentResolver.query(
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.Video.Media.DATE_TAKEN),
                "${MediaStore.Video.Media.DATA} = ?",
                arrayOf(sourcePath), null
            )?.use { c ->
                if (c.moveToFirst()) {
                    val idx = c.getColumnIndex(MediaStore.Video.Media.DATE_TAKEN)
                    if (idx >= 0 && !c.isNull(idx)) dateTakenMs = c.getLong(idx)
                }
            }
        } catch (_: Exception) { /* best-effort */ }

        return try {
            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, filename)
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                put(MediaStore.Video.Media.RELATIVE_PATH, "DCIM/Camera")
                dateTakenMs?.let { put(MediaStore.Video.Media.DATE_TAKEN, it) }
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
                ?: return null
            contentResolver.openOutputStream(uri)?.use { out ->
                File(sourcePath).inputStream().use { it.copyTo(out) }
            }
            values.clear()
            values.put(MediaStore.Video.Media.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            "DCIM/Camera/$filename"
        } catch (e: Exception) {
            null
        }
    }

    // ── Notifications ────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID, "Video Conversion", NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Shows progress while converting videos"
            setSound(null, null)
        }
        notificationManager.createNotificationChannel(channel)
    }

    private fun buildNotification(fileName: String, percent: Int, fileIndex: Int, total: Int): Notification {
        val cancelIntent = Intent(this, ConversionForegroundService::class.java).apply {
            action = ACTION_CANCEL
        }
        val cancelPi = PendingIntent.getService(
            this, 0, cancelIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val openPi = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_IMMUTABLE
        )
        val title = if (total > 0) "Converting ${fileIndex + 1}/$total" else "Converting…"
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(fileName)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setOngoing(true)
            .setContentIntent(openPi)
            .addAction(android.R.drawable.ic_delete, "Cancel", cancelPi)
        if (percent < 0) {
            builder.setProgress(0, 0, true) // indeterminate
        } else {
            builder.setProgress(100, percent, false)
        }
        return builder.build()
    }

    private fun pushNotif(fileName: String, percent: Int, fileIndex: Int, total: Int) {
        notificationManager.notify(NOTIFICATION_ID, buildNotification(fileName, percent, fileIndex, total))
    }

    private fun showDoneNotification(title: String, text: String) {
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setAutoCancel(true)
            .build()
        notificationManager.notify(DONE_NOTIFICATION_ID, notification)
    }

    // ── Event helpers ────────────────────────────────────────────────────────

    private fun progressEvent(file: String, percent: Int, index: Int, total: Int) = mapOf(
        "type" to "progress",
        "file" to file,
        "percent" to percent,
        "fileIndex" to index,
        "totalFiles" to total,
    )

    private fun resultMap(
        inputPath: String, outputPath: String,
        inputSize: Long, outputSize: Long,
        success: Boolean, error: String?,
    ) = mapOf(
        "inputPath" to inputPath,
        "outputPath" to outputPath,
        "inputSize" to inputSize,
        "outputSize" to outputSize,
        "success" to success,
        "error" to error,
    )
}
