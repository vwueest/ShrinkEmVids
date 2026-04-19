import 'dart:async';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import '../models/conversion_result.dart';
import '../models/encoding_preset.dart';
import '../models/video_file.dart';

import 'media_scanner_service.dart';

typedef ProgressCallback = void Function(double progress);

class EncoderService {
  int? _currentSessionId;
  bool _skipCurrent = false;
  bool _cancelAll = false;

  bool get isCancelAllRequested => _cancelAll;

  /// Cancels the currently encoding file and moves on to the next.
  void skipCurrentFile() {
    _skipCurrent = true;
    final id = _currentSessionId;
    if (id != null) FFmpegKit.cancel(id);
  }

  /// Cancels the entire batch.
  void cancelAll() {
    _cancelAll = true;
    FFmpegKit.cancel();
  }

  /// Call before starting a new batch.
  void reset() {
    _cancelAll = false;
    _skipCurrent = false;
    _currentSessionId = null;
  }

  Future<int?> _getDurationMs(String path) async {
    final session = await FFprobeKit.getMediaInformation(path);
    final info = session.getMediaInformation();
    final durationStr = info?.getDuration();
    if (durationStr == null) return null;
    final seconds = double.tryParse(durationStr);
    return seconds != null ? (seconds * 1000).toInt() : null;
  }

  Future<ConversionResult> encode(
    VideoFile file,
    ResolutionOption resolution,
    int bitrateKbps, {
    required ProgressCallback onProgress,
  }) async {
    _skipCurrent = false;

    final extDir = await getExternalStorageDirectory();
    final tempPath = '${extDir!.path}/${file.outputFileName}';

    // Early exit if cancel was already requested
    if (_cancelAll) {
      return ConversionResult(
        inputPath: file.path,
        outputPath: tempPath,
        inputSize: file.sizeBytes,
        outputSize: 0,
        success: false,
        error: 'Cancelled',
      );
    }

    // Use durationMs from model if already loaded (avoids a second ffprobe call)
    final durationMs = file.durationMs ?? await _getDurationMs(file.path);

    if (_skipCurrent || _cancelAll) {
      return ConversionResult(
        inputPath: file.path,
        outputPath: tempPath,
        inputSize: file.sizeBytes,
        outputSize: 0,
        success: false,
        error: _cancelAll ? 'Cancelled' : 'Skipped',
      );
    }

    final args = ['-i', file.path, ...resolution.buildFfmpegArgs(bitrateKbps), '-y', tempPath];

    // executeWithArgumentsAsync starts encoding immediately and returns the
    // session so we can store its ID for skip support, then we await a
    // Completer that fires when encoding completes.
    final completer = Completer<void>();
    final session = await FFmpegKit.executeWithArgumentsAsync(
      args,
      (_) => completer.complete(),
      null,
      (stats) {
        if (durationMs != null && durationMs > 0) {
          final progress = stats.getTime() / durationMs;
          onProgress(progress.clamp(0.0, 1.0));
        }
      },
    );
    _currentSessionId = session.getSessionId();
    await completer.future;
    _currentSessionId = null;

    if (_skipCurrent) {
      _deleteIfExists(tempPath);
      return ConversionResult(
        inputPath: file.path,
        outputPath: tempPath,
        inputSize: file.sizeBytes,
        outputSize: 0,
        success: false,
        error: 'Skipped',
      );
    }

    if (_cancelAll) {
      _deleteIfExists(tempPath);
      return ConversionResult(
        inputPath: file.path,
        outputPath: tempPath,
        inputSize: file.sizeBytes,
        outputSize: 0,
        success: false,
        error: 'Cancelled',
      );
    }

    final returnCode = await session.getReturnCode();
    final logs = await session.getAllLogsAsString();

    if (ReturnCode.isSuccess(returnCode)) {
      final outputSize =
          File(tempPath).existsSync() ? File(tempPath).lengthSync() : 0;
      final moviesPath = await MediaScannerService.copyToMovies(
        tempPath,
        file.outputFileName,
      );
      if (moviesPath != null) _deleteIfExists(tempPath);
      return ConversionResult(
        inputPath: file.path,
        outputPath: moviesPath ?? tempPath,
        inputSize: file.sizeBytes,
        outputSize: outputSize,
        success: true,
      );
    } else {
      _deleteIfExists(tempPath);
      return ConversionResult(
        inputPath: file.path,
        outputPath: tempPath,
        inputSize: file.sizeBytes,
        outputSize: 0,
        success: false,
        error: logs ?? 'Unknown ffmpeg error (return code: $returnCode)',
      );
    }
  }

  void _deleteIfExists(String path) {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  }
}
