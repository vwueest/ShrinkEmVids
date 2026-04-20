import 'package:flutter/services.dart';
import '../models/video_file.dart';
import '../providers/selected_files_provider.dart';
import 'media_scanner_service.dart';

class DateRangeScanner {
  static const _channel = MethodChannel(
    'com.transcoders.shrinkemvids/media_scanner',
  );

  /// Queries MediaStore for videos in DCIM/Camera taken between [from] and [to]
  /// (inclusive of the full [to] day). Flags files whose compressed output
  /// already exists in DCIM/Camera.
  static Future<List<VideoFile>> scan(DateTime from, DateTime to) async {
    final fromMs = from.millisecondsSinceEpoch;
    final toMs = DateTime(
      to.year,
      to.month,
      to.day,
      23,
      59,
      59,
      999,
    ).millisecondsSinceEpoch;

    final List<dynamic> raw;
    try {
      raw = await _channel.invokeMethod('queryDcimVideos', {
        'fromMs': fromMs,
        'toMs': toMs,
      });
    } on PlatformException catch (e) {
      throw Exception('Failed to query MediaStore: ${e.message}');
    }

    // Batch-fetch existing compressed output names from DCIM/Camera
    final existingOutputs = await MediaScannerService.getExistingOutputNames();

    return raw.cast<Map>().map((m) {
      final path = m['path'] as String;
      final displayName = (m['displayName'] as String?) ?? path.split('/').last;
      final file = buildVideoFile(path, displayName: displayName);
      final outputExists = existingOutputs.contains(file.outputFileName);
      if (outputExists) {
        return VideoFile(
          path: file.path,
          name: file.name,
          displayName: file.displayName,
          sizeBytes: file.sizeBytes,
          alreadyCompressed: file.alreadyCompressed,
          outputExists: true,
          selected: false,
        );
      }
      return file;
    }).toList();
  }
}
