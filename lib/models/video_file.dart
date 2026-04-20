import 'dart:typed_data';

class VideoFile {
  final String path;
  final String name; // cached path filename (may have ~N suffix)
  final String displayName; // original filename from media store
  final int sizeBytes;
  final bool alreadyCompressed;
  final bool outputExists;
  final bool selected;
  final int? durationMs; // from ffprobe, null until loaded
  final String? resolution; // e.g. "3840x2160", null until loaded
  final Uint8List? thumbnail; // JPEG bytes, null until loaded

  VideoFile({
    required this.path,
    required this.name,
    required this.displayName,
    required this.sizeBytes,
    required this.alreadyCompressed,
    required this.outputExists,
    this.selected = true,
    this.durationMs,
    this.resolution,
    this.thumbnail,
  });

  bool get isEligible => !alreadyCompressed && !outputExists;

  /// Output filename (original name, _compressed suffix).
  /// Actual write location is decided by EncoderService at encode time.
  String get outputFileName {
    final base = displayName.endsWith('.mp4')
        ? displayName.substring(0, displayName.length - 4)
        : displayName;
    return '${base}_compressed.mp4';
  }

  String get formattedDuration {
    if (durationMs == null) return '';
    final total = durationMs! ~/ 1000;
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  VideoFile copyWith({bool? selected, bool? outputExists}) {
    return VideoFile(
      path: path,
      name: name,
      displayName: displayName,
      sizeBytes: sizeBytes,
      alreadyCompressed: alreadyCompressed,
      outputExists: outputExists ?? this.outputExists,
      selected: selected ?? this.selected,
      durationMs: durationMs,
      resolution: resolution,
      thumbnail: thumbnail,
    );
  }

  /// Returns a copy with updated metadata fields (null values keep existing).
  VideoFile withMetadata({
    int? durationMs,
    String? resolution,
    Uint8List? thumbnail,
  }) {
    return VideoFile(
      path: path,
      name: name,
      displayName: displayName,
      sizeBytes: sizeBytes,
      alreadyCompressed: alreadyCompressed,
      outputExists: outputExists,
      selected: selected,
      durationMs: durationMs ?? this.durationMs,
      resolution: resolution ?? this.resolution,
      thumbnail: thumbnail ?? this.thumbnail,
    );
  }
}
