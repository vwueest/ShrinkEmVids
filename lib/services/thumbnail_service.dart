import 'package:flutter/services.dart';

class ThumbnailService {
  static const _channel = MethodChannel(
    'com.transcoders.shrinkemvids/media_scanner',
  );

  static Future<Uint8List?> getThumbnail(String path) async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>(
        'getVideoThumbnail',
        {'path': path},
      );
      return bytes;
    } on PlatformException catch (_) {
      return null;
    }
  }
}
