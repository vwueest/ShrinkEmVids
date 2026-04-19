package com.transcoders.shrinkemvids

import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaScannerConnection
import android.media.ThumbnailUtils
import android.provider.MediaStore
import android.util.Size
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

class MainActivity : FlutterActivity() {

    private val mediaChannel = "com.transcoders.shrinkemvids/media_scanner"
    private val convChannel = "com.transcoders.shrinkemvids/conversion"
    private val progressChannel = "com.transcoders.shrinkemvids/conversion_progress"

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
}
