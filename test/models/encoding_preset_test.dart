import 'package:flutter_test/flutter_test.dart';
import 'package:shrinkemvids/models/encoding_preset.dart';

void main() {
  group('ResolutionOptionX.label', () {
    test('p720 label is 720p', () => expect(ResolutionOption.p720.label, '720p'));
    test('p1080 label is 1080p', () => expect(ResolutionOption.p1080.label, '1080p'));
    test('original label is 4K', () => expect(ResolutionOption.original.label, '4K'));
  });

  group('ResolutionOptionX.maxHeight', () {
    test('p720 maxHeight is 720', () => expect(ResolutionOption.p720.maxHeight, 720));
    test('p1080 maxHeight is 1080', () => expect(ResolutionOption.p1080.maxHeight, 1080));
    test('original maxHeight is null (keep source)', () =>
        expect(ResolutionOption.original.maxHeight, isNull));
  });

  group('ResolutionOptionX bitrate range', () {
    for (final opt in ResolutionOption.values) {
      test('${opt.name}: defaultBitrateKbps is within [min, max]', () {
        expect(opt.defaultBitrateKbps, greaterThanOrEqualTo(opt.minBitrateKbps));
        expect(opt.defaultBitrateKbps, lessThanOrEqualTo(opt.maxBitrateKbps));
      });

      test('${opt.name}: stepBitrateKbps is positive', () {
        expect(opt.stepBitrateKbps, greaterThan(0));
      });
    }
  });

  group('ResolutionOptionX.buildFfmpegArgs', () {
    test('p720 includes scale filter', () {
      final args = ResolutionOption.p720.buildFfmpegArgs(1600);
      expect(args.contains('-vf'), isTrue);
      final vfArg = args[args.indexOf('-vf') + 1];
      expect(vfArg, contains('720'));
    });

    test('original has no scale filter', () {
      final args = ResolutionOption.original.buildFfmpegArgs(6400);
      expect(args.contains('-vf'), isFalse);
    });

    test('bitrate flags reflect provided value', () {
      final args = ResolutionOption.p1080.buildFfmpegArgs(4000);
      expect(args[args.indexOf('-b:v') + 1], '4000k');
    });

    test('maxrate is ~13% above bitrate', () {
      final args = ResolutionOption.p1080.buildFfmpegArgs(3200);
      final maxrate = args[args.indexOf('-maxrate') + 1]; // e.g. "3616k"
      final kbps = int.parse(maxrate.replaceAll('k', ''));
      expect(kbps, (3200 * 1.13).round());
    });

    test('bufsize is 2x bitrate', () {
      final args = ResolutionOption.p1080.buildFfmpegArgs(3200);
      final bufsize = args[args.indexOf('-bufsize') + 1];
      expect(bufsize, '${3200 * 2}k');
    });

    test('uses hevc_mediacodec codec', () {
      final args = ResolutionOption.p1080.buildFfmpegArgs(3200);
      expect(args[args.indexOf('-c:v') + 1], 'hevc_mediacodec');
    });

    test('audio bitrate is 96k for low video bitrate', () {
      final args = ResolutionOption.p720.buildFfmpegArgs(500);
      expect(args[args.indexOf('-b:a') + 1], '96k');
    });

    test('audio bitrate is 128k for mid video bitrate', () {
      final args = ResolutionOption.p1080.buildFfmpegArgs(2000);
      expect(args[args.indexOf('-b:a') + 1], '128k');
    });

    test('audio bitrate is 192k for high video bitrate', () {
      final args = ResolutionOption.original.buildFfmpegArgs(6400);
      expect(args[args.indexOf('-b:a') + 1], '192k');
    });

    test('always includes faststart movflag', () {
      for (final opt in ResolutionOption.values) {
        final args = opt.buildFfmpegArgs(opt.defaultBitrateKbps);
        expect(args.contains('+faststart'), isTrue,
            reason: '${opt.name} should include faststart');
      }
    });
  });
}
