import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shrinkemvids/models/encoding_preset.dart';
import 'package:shrinkemvids/providers/selected_preset_provider.dart';

ProviderContainer _container() => ProviderContainer();

void main() {
  group('resolutionProvider', () {
    test('defaults to 1080p', () {
      final container = _container();
      addTearDown(container.dispose);
      expect(container.read(resolutionProvider), ResolutionOption.p1080);
    });

    test('can be changed', () {
      final container = _container();
      addTearDown(container.dispose);
      container.read(resolutionProvider.notifier).state = ResolutionOption.p720;
      expect(container.read(resolutionProvider), ResolutionOption.p720);
    });
  });

  group('bitrateKbpsProvider', () {
    test('defaults to 1080p default bitrate', () {
      final container = _container();
      addTearDown(container.dispose);
      expect(
        container.read(bitrateKbpsProvider),
        ResolutionOption.p1080.defaultBitrateKbps,
      );
    });

    test('accepts custom value', () {
      final container = _container();
      addTearDown(container.dispose);
      container.read(bitrateKbpsProvider.notifier).state = 2500;
      expect(container.read(bitrateKbpsProvider), 2500);
    });
  });
}
