import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shrinkemvids/models/video_file.dart';
import 'package:shrinkemvids/providers/selected_files_provider.dart';

/// Helper – builds a [VideoFile] without touching the filesystem.
VideoFile _file({
  String path = '/sdcard/DCIM/Camera/video.mp4',
  String displayName = 'video.mp4',
  int sizeBytes = 50 * 1024 * 1024,
  bool alreadyCompressed = false,
  bool outputExists = false,
  bool selected = true,
}) => VideoFile(
  path: path,
  name: path.split('/').last,
  displayName: displayName,
  sizeBytes: sizeBytes,
  alreadyCompressed: alreadyCompressed,
  outputExists: outputExists,
  selected: selected,
);

ProviderContainer _container() => ProviderContainer();

void main() {
  group('SelectedFilesNotifier.addFiles', () {
    test('adds files to empty list', () {
      final container = _container();
      addTearDown(container.dispose);
      final notifier = container.read(selectedFilesProvider.notifier);
      notifier.addFiles([
        _file(),
        _file(path: '/sdcard/b.mp4', displayName: 'b.mp4'),
      ]);
      expect(container.read(selectedFilesProvider).length, 2);
    });

    test('does not add duplicate paths', () {
      final container = _container();
      addTearDown(container.dispose);
      final notifier = container.read(selectedFilesProvider.notifier);
      final f = _file();
      notifier.addFiles([f]);
      notifier.addFiles([f]); // same path again
      expect(container.read(selectedFilesProvider).length, 1);
    });

    test('adds new paths while skipping duplicates', () {
      final container = _container();
      addTearDown(container.dispose);
      final notifier = container.read(selectedFilesProvider.notifier);
      notifier.addFiles([_file()]);
      notifier.addFiles([
        _file(), // duplicate
        _file(path: '/sdcard/new.mp4', displayName: 'new.mp4'),
      ]);
      expect(container.read(selectedFilesProvider).length, 2);
    });
  });

  group('SelectedFilesNotifier.replaceAll', () {
    test('replaces existing list', () {
      final container = _container();
      addTearDown(container.dispose);
      final notifier = container.read(selectedFilesProvider.notifier);
      notifier.addFiles([_file(), _file(path: '/a.mp4', displayName: 'a.mp4')]);
      notifier.replaceAll([_file(path: '/only.mp4', displayName: 'only.mp4')]);
      expect(container.read(selectedFilesProvider).length, 1);
      expect(container.read(selectedFilesProvider).first.path, '/only.mp4');
    });
  });

  group('SelectedFilesNotifier.toggleSelection', () {
    test('deselects a selected eligible file', () {
      final container = _container();
      addTearDown(container.dispose);
      final notifier = container.read(selectedFilesProvider.notifier);
      notifier.addFiles([_file(selected: true)]);
      notifier.toggleSelection(0);
      expect(container.read(selectedFilesProvider).first.selected, isFalse);
    });

    test('selects a deselected eligible file', () {
      final container = _container();
      addTearDown(container.dispose);
      final notifier = container.read(selectedFilesProvider.notifier);
      notifier.addFiles([_file(selected: false)]);
      notifier.toggleSelection(0);
      expect(container.read(selectedFilesProvider).first.selected, isTrue);
    });

    test('cannot toggle an ineligible (already compressed) file', () {
      final container = _container();
      addTearDown(container.dispose);
      final notifier = container.read(selectedFilesProvider.notifier);
      notifier.addFiles([_file(alreadyCompressed: true, selected: false)]);
      notifier.toggleSelection(0); // should be a no-op
      expect(container.read(selectedFilesProvider).first.selected, isFalse);
    });
  });

  group('SelectedFilesNotifier.selectAllEligible / deselectAll', () {
    test('selectAllEligible only selects eligible files', () {
      final container = _container();
      addTearDown(container.dispose);
      final notifier = container.read(selectedFilesProvider.notifier);
      notifier.addFiles([
        _file(path: '/a.mp4', displayName: 'a.mp4', selected: false),
        _file(
          path: '/b.mp4',
          displayName: 'b.mp4',
          alreadyCompressed: true,
          selected: false,
        ),
      ]);
      notifier.selectAllEligible();
      final files = container.read(selectedFilesProvider);
      expect(files[0].selected, isTrue); // eligible → selected
      expect(files[1].selected, isFalse); // ineligible → unchanged
    });

    test('deselectAll deselects everything regardless of eligibility', () {
      final container = _container();
      addTearDown(container.dispose);
      final notifier = container.read(selectedFilesProvider.notifier);
      notifier.addFiles([
        _file(path: '/a.mp4', displayName: 'a.mp4', selected: true),
        _file(path: '/b.mp4', displayName: 'b.mp4', selected: true),
      ]);
      notifier.deselectAll();
      for (final f in container.read(selectedFilesProvider)) {
        expect(f.selected, isFalse);
      }
    });
  });

  group('SelectedFilesNotifier.updateMetadata', () {
    test('updates metadata for a known path', () {
      final container = _container();
      addTearDown(container.dispose);
      final notifier = container.read(selectedFilesProvider.notifier);
      notifier.addFiles([_file()]);
      notifier.updateMetadata(
        '/sdcard/DCIM/Camera/video.mp4',
        durationMs: 30000,
        resolution: '1920x1080',
      );
      final f = container.read(selectedFilesProvider).first;
      expect(f.durationMs, 30000);
      expect(f.resolution, '1920x1080');
    });

    test('is a no-op for an unknown path', () {
      final container = _container();
      addTearDown(container.dispose);
      final notifier = container.read(selectedFilesProvider.notifier);
      notifier.addFiles([_file()]);
      notifier.updateMetadata('/does/not/exist.mp4', durationMs: 9999);
      // Should not throw; original file unchanged
      expect(container.read(selectedFilesProvider).first.durationMs, isNull);
    });
  });

  group('SelectedFilesNotifier.clear', () {
    test('empties the list', () {
      final container = _container();
      addTearDown(container.dispose);
      final notifier = container.read(selectedFilesProvider.notifier);
      notifier.addFiles([_file()]);
      notifier.clear();
      expect(container.read(selectedFilesProvider), isEmpty);
    });
  });
}
