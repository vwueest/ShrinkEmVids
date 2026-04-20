import 'package:flutter_test/flutter_test.dart';
import 'package:shrinkemvids/models/video_file.dart';

VideoFile _make({
  String path = '/sdcard/DCIM/Camera/video.mp4',
  String displayName = 'video.mp4',
  int sizeBytes = 1024 * 1024 * 100, // 100 MB
  bool alreadyCompressed = false,
  bool outputExists = false,
  bool selected = true,
  int? durationMs,
  String? resolution,
}) => VideoFile(
  path: path,
  name: path.split('/').last,
  displayName: displayName,
  sizeBytes: sizeBytes,
  alreadyCompressed: alreadyCompressed,
  outputExists: outputExists,
  selected: selected,
  durationMs: durationMs,
  resolution: resolution,
);

void main() {
  group('VideoFile.isEligible', () {
    test('regular video is eligible', () {
      expect(_make().isEligible, isTrue);
    });

    test('already compressed is not eligible', () {
      expect(_make(alreadyCompressed: true).isEligible, isFalse);
    });

    test('output already exists is not eligible', () {
      expect(_make(outputExists: true).isEligible, isFalse);
    });

    test('both flags set is not eligible', () {
      expect(
        _make(alreadyCompressed: true, outputExists: true).isEligible,
        isFalse,
      );
    });
  });

  group('VideoFile.outputFileName', () {
    test('appends _compressed suffix for .mp4 file', () {
      final f = _make(displayName: 'holiday.mp4');
      expect(f.outputFileName, 'holiday_compressed.mp4');
    });

    test('appends _compressed.mp4 when extension is not .mp4', () {
      final f = _make(displayName: 'clip.mov');
      expect(f.outputFileName, 'clip.mov_compressed.mp4');
    });

    test(
      'already-compressed display name produces double-compressed output name',
      () {
        // This documents the current behaviour: detection is on the file itself,
        // not on the output name math.
        final f = _make(displayName: 'clip_compressed.mp4');
        expect(f.outputFileName, 'clip_compressed_compressed.mp4');
      },
    );
  });

  group('VideoFile.formattedDuration', () {
    test('returns empty string when durationMs is null', () {
      expect(_make().formattedDuration, '');
    });

    test('formats 90 seconds as 1:30', () {
      expect(_make(durationMs: 90000).formattedDuration, '1:30');
    });

    test('pads single-digit seconds', () {
      expect(_make(durationMs: 65000).formattedDuration, '1:05');
    });

    test('formats exactly 0 ms', () {
      expect(_make(durationMs: 0).formattedDuration, '0:00');
    });

    test('rounds down sub-second remainder', () {
      // 90 999 ms → 90 s → 1:30
      expect(_make(durationMs: 90999).formattedDuration, '1:30');
    });
  });

  group('VideoFile.copyWith', () {
    test('toggles selected', () {
      final original = _make(selected: true);
      final toggled = original.copyWith(selected: false);
      expect(toggled.selected, isFalse);
      expect(toggled.path, original.path); // other fields unchanged
    });

    test('sets outputExists', () {
      final updated = _make().copyWith(outputExists: true);
      expect(updated.outputExists, isTrue);
      expect(updated.isEligible, isFalse);
    });

    test('preserves fields not in copyWith signature', () {
      final original = _make(durationMs: 5000, resolution: '1920x1080');
      final copy = original.copyWith(selected: false);
      expect(copy.durationMs, 5000);
      expect(copy.resolution, '1920x1080');
    });
  });

  group('VideoFile.withMetadata', () {
    test('sets all metadata fields', () {
      final updated = _make().withMetadata(
        durationMs: 12000,
        resolution: '1280x720',
      );
      expect(updated.durationMs, 12000);
      expect(updated.resolution, '1280x720');
    });

    test('null values keep existing metadata', () {
      final original = _make(durationMs: 5000, resolution: '1920x1080');
      final updated = original.withMetadata(durationMs: null, resolution: null);
      expect(updated.durationMs, 5000);
      expect(updated.resolution, '1920x1080');
    });

    test('preserves selected and eligibility flags', () {
      final original = _make(alreadyCompressed: true, selected: false);
      final updated = original.withMetadata(durationMs: 3000);
      expect(updated.isEligible, isFalse);
      expect(updated.selected, isFalse);
    });
  });
}
