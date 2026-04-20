import 'package:flutter/services.dart';

class MediaScannerService {
  static const _channel = MethodChannel('com.transcoders.shrinkemvids/media_scanner');

  static Future<void> scan(String path) async {
    try {
      await _channel.invokeMethod('scanFile', {'path': path});
    } on PlatformException catch (_) {
      // Best-effort — if it fails the file just won't appear in the gallery
      // until the next automatic scan.
    }
  }

  /// Copies [sourcePath] into DCIM/Camera via MediaStore (Android 10+).
  /// Returns the display path or null on failure.
  static Future<String?> copyToMovies(String sourcePath, String filename) async {
    try {
      final result = await _channel.invokeMethod<String>(
        'copyToMovies',
        {'sourcePath': sourcePath, 'filename': filename},
      );
      return result;
    } on PlatformException catch (_) {
      return null;
    }
  }

  /// Returns a set of all `*_compressed.mp4` filenames already in DCIM/Camera.
  static Future<Set<String>> getExistingOutputNames() async {
    try {
      final result = await _channel.invokeListMethod<String>('getExistingOutputNames');
      return result?.toSet() ?? {};
    } on PlatformException catch (_) {
      return {};
    }
  }

  /// Launches the native Android video picker.
  /// Returns a list of maps with keys: path, displayName, size.
  static Future<List<Map<String, dynamic>>> pickVideos() async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('pickVideos');
      return raw
              ?.whereType<Map<Object?, Object?>>()
              .map((m) => m.cast<String, dynamic>())
              .toList() ??
          [];
    } on PlatformException catch (_) {
      return [];
    }
  }

  /// Resolves the real MediaStore DISPLAY_NAME for a given numeric media ID.
  /// Returns null if not found or on error.
  static Future<String?> resolveDisplayName(String mediaId) async {
    try {
      return await _channel.invokeMethod<String>(
        'resolveDisplayName',
        {'mediaId': mediaId},
      );
    } on PlatformException catch (_) {
      return null;
    }
  }
}

