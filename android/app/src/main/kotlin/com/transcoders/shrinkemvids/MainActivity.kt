package com.transcoders.shrinkemvids

import android.app.Activity
import android.content.ContentUris
import android.net.Uri
import android.content.ContentValues
import android.content.Intent
import android.os.Bundle
import android.graphics.Bitmap
import android.media.MediaScannerConnection
import android.media.ThumbnailUtils
import android.os.Build
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Size
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {

    private val mediaChannel = "com.transcoders.shrinkemvids/media_scanner"
    private val PICK_VIDEO_REQUEST = 2001
    private var pickVideosResult: MethodChannel.Result? = null
    private val convChannel = "com.transcoders.shrinkemvids/conversion"
    private val progressChannel = "com.transcoders.shrinkemvids/conversion_progress"

    /**
     * Raw URIs buffered from incoming share intents, consumed lazily by [getSharedFiles].
     * We deliberately defer path resolution / cache-copy to the background thread in
     * getSharedFiles so that the main thread is never blocked by IO.
     */
    private val pendingSharedUris = mutableListOf<Uri>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        parseShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        parseShareIntent(intent)
    }

    /**
     * Collects video URIs from a share intent into [pendingSharedUris].
     * Only MIME-type filtering is done here; actual path resolution happens later
     * on a background thread inside [getSharedFiles].
     */
    private fun parseShareIntent(intent: Intent) {
        val uris = mutableListOf<Uri>()
        when (intent.action) {
            Intent.ACTION_SEND -> {
                val uri: Uri? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM)
                }
                uri?.let { uris.add(it) }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val list: ArrayList<Uri>? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
                }
                list?.let { uris.addAll(it) }
            }
            else -> return
        }
        for (uri in uris) {
            val mime = contentResolver.getType(uri)
            if (mime == null || !mime.startsWith("video/")) continue
            pendingSharedUris.add(uri)
        }
    }

    /**
     * Resolves a shared URI to a directly readable file path.
     *
     * Fast path: query MediaStore DATA column — works for normal DCIM recordings
     * shared via Files/Gallery apps that map straight to MediaStore entries.
     *
     * Slow path: if the DATA path is missing or not readable (e.g. Google Photos
     * wraps URIs through its own content provider, sometimes pointing to a temp
     * path in its private storage), copy the content via ContentResolver into the
     * app's cache directory and return that path instead.
     */
    private fun resolveOrCopyUri(uri: Uri): Map<String, Any?>? {
        // Fast path
        val resolved = resolvePickedUri(uri)
        if (resolved != null) {
            val path = resolved["path"] as? String
            if (path != null && File(path).canRead()) {
                return resolved
            }
        }
        // Slow path: copy the stream to our cache
        return copyUriToCache(uri)
    }

    private fun copyUriToCache(uri: Uri): Map<String, Any?>? {
        return try {
            var displayName: String? = null
            var size: Long = 0L
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                null, null, null
            )?.use { c ->
                if (c.moveToFirst()) {
                    val nameIdx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val sizeIdx = c.getColumnIndex(OpenableColumns.SIZE)
                    if (nameIdx >= 0) displayName = c.getString(nameIdx)
                    if (sizeIdx >= 0) size = c.getLong(sizeIdx)
                }
            }
            if (displayName.isNullOrEmpty()) {
                displayName = "shared_video_${System.currentTimeMillis()}.mp4"
            }
            val shareDir = File(cacheDir, "shrinkemvids_share").also { it.mkdirs() }
            val outFile = File(shareDir, displayName!!)
            contentResolver.openInputStream(uri)?.use { input ->
                outFile.outputStream().use { output -> input.copyTo(output) }
            }
            android.util.Log.d("ShrinkEmVids", "copyUriToCache: $uri -> ${outFile.absolutePath}")
            mapOf(
                "path" to outFile.absolutePath,
                "displayName" to displayName,
                "size" to size,
            )
        } catch (e: Exception) {
            android.util.Log.e("ShrinkEmVids", "copyUriToCache failed for $uri", e)
            null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── EventChannel: streams progress events from the service to Flutter ──
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, progressChannel)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    ConversionForegroundService.eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    ConversionForegroundService.eventSink = null
                }
            })

        // ── MethodChannel: conversion commands ───────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, convChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startConversion" -> {
                        val filePaths = call.argument<List<String>>("filePaths") ?: emptyList()
                        val displayNames = call.argument<List<String>>("displayNames") ?: emptyList()
                        val outputFileNames = call.argument<List<String>>("outputFileNames") ?: emptyList()
                        val inputSizes = call.argument<List<Long>>("inputSizes") ?: emptyList()
                        val durationsMsList = call.argument<List<Long>>("durationMsList") ?: emptyList()
                        val maxHeight = call.argument<Int>("maxHeight") ?: -1
                        val videoBitrateKbps = call.argument<Int>("videoBitrateKbps") ?: 3200
                        val audioBitrateKbps = call.argument<Int>("audioBitrateKbps") ?: 128
                        val maxRateKbps = call.argument<Int>("maxRateKbps") ?: (videoBitrateKbps * 1.13).toInt()
                        val bufSizeKbps = call.argument<Int>("bufSizeKbps") ?: videoBitrateKbps * 2

                        val intent = Intent(this, ConversionForegroundService::class.java).apply {
                            action = ConversionForegroundService.ACTION_START
                            putStringArrayListExtra("filePaths", ArrayList(filePaths))
                            putStringArrayListExtra("displayNames", ArrayList(displayNames))
                            putStringArrayListExtra("outputFileNames", ArrayList(outputFileNames))
                            putExtra("inputSizes", inputSizes.toLongArray())
                            putExtra("durationMsList", durationsMsList.toLongArray())
                            putExtra("maxHeight", maxHeight)
                            putExtra("videoBitrateKbps", videoBitrateKbps)
                            putExtra("audioBitrateKbps", audioBitrateKbps)
                            putExtra("maxRateKbps", maxRateKbps)
                            putExtra("bufSizeKbps", bufSizeKbps)
                        }
                        startForegroundService(intent)
                        result.success(null)
                    }
                    "cancelConversion" -> {
                        ConversionForegroundService.cancelRequested = true
                        startService(Intent(this, ConversionForegroundService::class.java).apply {
                            action = ConversionForegroundService.ACTION_CANCEL
                        })
                        result.success(null)
                    }
                    "skipFile" -> {
                        ConversionForegroundService.skipRequested = true
                        ConversionForegroundService.currentSessionId?.let {
                            com.antonkarpenko.ffmpegkit.FFmpegKit.cancel(it)
                        }
                        result.success(null)
                    }
                    "getState" -> {
                        if (ConversionForegroundService.isRunning) {
                            result.success(mapOf(
                                "running" to true,
                                "currentFileIndex" to ConversionForegroundService.currentFileIndex,
                                "totalFiles" to ConversionForegroundService.totalFiles,
                                "currentFileName" to ConversionForegroundService.currentFileName,
                                "currentProgress" to ConversionForegroundService.currentProgress,
                            ))
                        } else {
                            result.success(mapOf("running" to false))
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ── MethodChannel: media scanner + existing helpers ──────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSharedFiles" -> {
                        val uris = pendingSharedUris.toList()
                        pendingSharedUris.clear()
                        if (uris.isEmpty()) {
                            result.success(emptyList<Map<String, Any?>?>())
                        } else {
                            // Resolve/copy on IO thread — may involve reading from another
                            // app's content provider or copying large files to cache.
                            CoroutineScope(Dispatchers.IO).launch {
                                val files = uris.mapNotNull { resolveOrCopyUri(it) }
                                withContext(Dispatchers.Main) { result.success(files) }
                            }
                        }
                    }

                    "pickVideos" -> {
                        pickVideosResult = result
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                                putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, 50)
                                type = "video/*"
                            }
                        } else {
                            Intent(Intent.ACTION_GET_CONTENT).apply {
                                type = "video/*"
                                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                                addCategory(Intent.CATEGORY_OPENABLE)
                            }
                        }
                        startActivityForResult(intent, PICK_VIDEO_REQUEST)
                    }

                    "scanFile" -> {
                        val path = call.argument<String>("path")
                        if (path != null) {
                            MediaScannerConnection.scanFile(
                                applicationContext,
                                arrayOf(path),
                                arrayOf("video/mp4"),
                                null
                            )
                        }
                        result.success(null)
                    }
                    "copyToMovies" -> {
                        val sourcePath = call.argument<String>("sourcePath")
                        val filename = call.argument<String>("filename")
                        if (sourcePath == null || filename == null) {
                            result.error("INVALID_ARGS", "sourcePath and filename required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val values = ContentValues().apply {
                                put(MediaStore.Video.Media.DISPLAY_NAME, filename)
                                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                                put(MediaStore.Video.Media.RELATIVE_PATH, "DCIM/Camera")
                                put(MediaStore.Video.Media.IS_PENDING, 1)
                            }
                            val uri = contentResolver.insert(
                                MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values
                            )
                            if (uri == null) {
                                result.error("MEDIASTORE_ERROR", "Failed to create MediaStore entry", null)
                                return@setMethodCallHandler
                            }
                            contentResolver.openOutputStream(uri)?.use { out ->
                                File(sourcePath).inputStream().use { it.copyTo(out) }
                            }
                            values.clear()
                            values.put(MediaStore.Video.Media.IS_PENDING, 0)
                            contentResolver.update(uri, values, null, null)
                            result.success("DCIM/Camera/$filename")
                        } catch (e: Exception) {
                            result.error("COPY_ERROR", e.message, null)
                        }
                    }

                    "getVideoThumbnail" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        try {
                            val bitmap = ThumbnailUtils.createVideoThumbnail(
                                File(path), Size(256, 256), null
                            )
                            if (bitmap == null) {
                                result.success(null)
                                return@setMethodCallHandler
                            }
                            val stream = ByteArrayOutputStream()
                            bitmap.compress(Bitmap.CompressFormat.JPEG, 75, stream)
                            bitmap.recycle()
                            result.success(stream.toByteArray())
                        } catch (e: Exception) {
                            result.success(null) // best-effort
                        }
                    }

                    "queryDcimVideos" -> {
                        val fromMs = call.argument<Long>("fromMs") ?: 0L
                        val toMs = call.argument<Long>("toMs") ?: Long.MAX_VALUE
                        val projection = arrayOf(
                            MediaStore.Video.Media.DATA,
                            MediaStore.Video.Media.DISPLAY_NAME,
                            MediaStore.Video.Media.SIZE,
                        )
                        val selection =
                            "${MediaStore.Video.Media.RELATIVE_PATH} LIKE ? AND " +
                            "${MediaStore.Video.Media.DATE_TAKEN} BETWEEN ? AND ?"
                        val selArgs = arrayOf("DCIM/Camera%", fromMs.toString(), toMs.toString())
                        val cursor = contentResolver.query(
                            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                            projection, selection, selArgs,
                            "${MediaStore.Video.Media.DATE_TAKEN} DESC"
                        )
                        val videos = mutableListOf<Map<String, Any?>>()
                        cursor?.use { c ->
                            val dataIdx = c.getColumnIndex(MediaStore.Video.Media.DATA)
                            val nameIdx = c.getColumnIndex(MediaStore.Video.Media.DISPLAY_NAME)
                            val sizeIdx = c.getColumnIndex(MediaStore.Video.Media.SIZE)
                            while (c.moveToNext()) {
                                val p = if (dataIdx >= 0) c.getString(dataIdx) else null
                                    ?: continue
                                videos.add(mapOf(
                                    "path" to p,
                                    "displayName" to if (nameIdx >= 0) c.getString(nameIdx) else null,
                                    "size" to if (sizeIdx >= 0) c.getLong(sizeIdx) else 0L,
                                ))
                            }
                        }
                        result.success(videos)
                    }

                    "getExistingOutputNames" -> {                        val projection = arrayOf(MediaStore.Video.Media.DISPLAY_NAME)
                        val selection =
                            "${MediaStore.Video.Media.DISPLAY_NAME} LIKE ? AND " +
                            "${MediaStore.Video.Media.RELATIVE_PATH} LIKE ?"
                        val selArgs = arrayOf("%_compressed.mp4", "DCIM/Camera%")
                        val cursor = contentResolver.query(
                            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                            projection, selection, selArgs, null
                        )
                        val names = mutableListOf<String>()
                        cursor?.use { c ->
                            val idx = c.getColumnIndex(MediaStore.Video.Media.DISPLAY_NAME)
                            while (c.moveToNext()) {
                                if (idx >= 0) c.getString(idx)?.let { names.add(it) }
                            }
                        }
                        result.success(names)
                    }

                    "resolveDisplayName" -> {
                        val mediaId = call.argument<String>("mediaId")
                        if (mediaId == null) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        var displayName: String? = null
                        try {
                            // Try 1: query via direct content URI for the item
                            val itemUri = ContentUris.withAppendedId(
                                MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                                mediaId.toLong()
                            )
                            contentResolver.query(
                                itemUri,
                                arrayOf(MediaStore.Video.Media.DISPLAY_NAME),
                                null, null, null
                            )?.use { c ->
                                if (c.moveToFirst()) {
                                    val idx = c.getColumnIndex(MediaStore.Video.Media.DISPLAY_NAME)
                                    if (idx >= 0) displayName = c.getString(idx)
                                }
                            }
                            // Try 2: fallback — query all videos table by _ID
                            if (displayName == null) {
                                contentResolver.query(
                                    MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                                    arrayOf(MediaStore.Video.Media.DISPLAY_NAME),
                                    "${MediaStore.Video.Media._ID} = ?",
                                    arrayOf(mediaId), null
                                )?.use { c ->
                                    if (c.moveToFirst()) {
                                        val idx = c.getColumnIndex(MediaStore.Video.Media.DISPLAY_NAME)
                                        if (idx >= 0) displayName = c.getString(idx)
                                    }
                                }
                            }
                            // Try 3: query Files table (catches all media types)
                            if (displayName == null) {
                                contentResolver.query(
                                    MediaStore.Files.getContentUri("external"),
                                    arrayOf(MediaStore.MediaColumns.DISPLAY_NAME),
                                    "${MediaStore.MediaColumns._ID} = ?",
                                    arrayOf(mediaId), null
                                )?.use { c ->
                                    if (c.moveToFirst()) {
                                        val idx = c.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                                        if (idx >= 0) displayName = c.getString(idx)
                                    }
                                }
                            }
                        } catch (e: Exception) {
                            android.util.Log.e("ShrinkEmVids", "resolveDisplayName failed", e)
                        }
                        android.util.Log.d("ShrinkEmVids", "resolveDisplayName($mediaId) -> $displayName")
                        result.success(displayName)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_VIDEO_REQUEST) return
        val pending = pickVideosResult ?: return
        pickVideosResult = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            pending.success(emptyList<Map<String, Any?>>()); return
        }

        val uris = mutableListOf<Uri>()
        data.clipData?.let { clip ->
            for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
        } ?: data.data?.let { uris.add(it) }

        val videos = mutableListOf<Map<String, Any?>>()
        for (uri in uris) {
            resolvePickedUri(uri)?.let { videos.add(it) }
        }
        pending.success(videos)
    }

    private fun resolvePickedUri(uri: Uri): Map<String, Any?>? {
        // Try direct query: works for standard MediaStore content:// URIs
        try {
            contentResolver.query(
                uri,
                arrayOf(MediaStore.Video.Media.DATA, MediaStore.Video.Media.DISPLAY_NAME, MediaStore.Video.Media.SIZE),
                null, null, null
            )?.use { c ->
                if (c.moveToFirst()) {
                    val dataIdx = c.getColumnIndex(MediaStore.Video.Media.DATA)
                    val nameIdx = c.getColumnIndex(MediaStore.Video.Media.DISPLAY_NAME)
                    val sizeIdx = c.getColumnIndex(MediaStore.Video.Media.SIZE)
                    val path = if (dataIdx >= 0) c.getString(dataIdx) else null
                    if (!path.isNullOrEmpty()) {
                        return mapOf(
                            "path" to path,
                            "displayName" to if (nameIdx >= 0) c.getString(nameIdx) else null,
                            "size" to if (sizeIdx >= 0) c.getLong(sizeIdx) else 0L,
                        )
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("ShrinkEmVids", "Direct query failed for $uri", e)
        }

        // Fallback: photo picker URIs (content://media/picker/.../media/{id})
        // Extract the numeric ID from the last path segment and re-query MediaStore
        try {
            val mediaId = uri.lastPathSegment?.toLong() ?: return null
            val mediaUri = ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, mediaId)
            contentResolver.query(
                mediaUri,
                arrayOf(MediaStore.Video.Media.DATA, MediaStore.Video.Media.DISPLAY_NAME, MediaStore.Video.Media.SIZE),
                null, null, null
            )?.use { c ->
                if (c.moveToFirst()) {
                    val dataIdx = c.getColumnIndex(MediaStore.Video.Media.DATA)
                    val nameIdx = c.getColumnIndex(MediaStore.Video.Media.DISPLAY_NAME)
                    val sizeIdx = c.getColumnIndex(MediaStore.Video.Media.SIZE)
                    val path = if (dataIdx >= 0) c.getString(dataIdx) else null
                    if (!path.isNullOrEmpty()) {
                        return mapOf(
                            "path" to path,
                            "displayName" to if (nameIdx >= 0) c.getString(nameIdx) else null,
                            "size" to if (sizeIdx >= 0) c.getLong(sizeIdx) else 0L,
                        )
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("ShrinkEmVids", "MediaStore ID fallback failed for $uri", e)
        }

        android.util.Log.e("ShrinkEmVids", "Could not resolve path for URI: $uri")
        return null
    }
}
