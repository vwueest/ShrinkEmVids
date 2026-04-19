import 'package:flutter/services.dart';
import '../models/encoding_preset.dart';
import '../models/video_file.dart';

/// Delegates encoding work to [ConversionForegroundService] via MethodChannel.
/// All heavy lifting (ffmpeg, MediaStore copy, notification) happens in Kotlin.
class EncoderService {
  static const _channel = MethodChannel('com.transcoders.shrinkemvids/conversion');

  static Future<void> startConversion(
    List<VideoFile> files,
    ResolutionOption resolution,
    int bitrateKbps,
  ) async {
    final audioBitrateKbps = bitrateKbps >= 4000
        ? 192
        : bitrateKbps >= 2000
            ? 128
            : 96;
    await _channel.invokeMethod('startConversion', {
      'filePaths': files.map((f) => f.path).toList(),
      'displayNames': files.map((f) => f.displayName).toList(),
      'outputFileNames': files.map((f) => f.outputFileName).toList(),
      'inputSizes': files.map((f) => f.sizeBytes).toList(),
      'durationMsList': files.map((f) => f.durationMs ?? 0).toList(),
      'maxHeight': resolution.maxHeight ?? -1,
      'videoBitrateKbps': bitrateKbps,
      'audioBitrateKbps': audioBitrateKbps,
      'maxRateKbps': (bitrateKbps * 1.13).round(),
      'bufSizeKbps': bitrateKbps * 2,
    });
  }

  static Future<void> skipCurrentFile() async {
    await _channel.invokeMethod('skipFile');
  }

  static Future<void> cancelAll() async {
    await _channel.invokeMethod('cancelConversion');
  }

  static Future<Map<String, dynamic>?> getState() async {
    final raw = await _channel.invokeMethod<Map>('getState');
    return raw?.cast<String, dynamic>();
  }
}

