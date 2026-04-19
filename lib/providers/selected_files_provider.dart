import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/video_file.dart';

class SelectedFilesNotifier extends StateNotifier<List<VideoFile>> {
  SelectedFilesNotifier() : super([]);

  void addFiles(List<VideoFile> files) {
    final existing = {for (final f in state) f.path};
    final newFiles = files.where((f) => !existing.contains(f.path)).toList();
    state = [...state, ...newFiles];
  }

  /// Replace the full list (used by date range scanner).
  void replaceAll(List<VideoFile> files) {
    state = files;
  }

  void toggleSelection(int index) {
    final file = state[index];
    if (!file.isEligible) return;
    final updated = List<VideoFile>.from(state);
    updated[index] = file.copyWith(selected: !file.selected);
    state = updated;
  }

  void selectAllEligible() {
    state = state.map((f) => f.isEligible ? f.copyWith(selected: true) : f).toList();
  }

  void deselectAll() {
    state = state.map((f) => f.copyWith(selected: false)).toList();
  }

  /// Updates metadata fields for the file at [path]. Null values keep existing.
  void updateMetadata(String path, {int? durationMs, String? resolution, Uint8List? thumbnail}) {
    final idx = state.indexWhere((f) => f.path == path);
    if (idx < 0) return;
    final updated = List<VideoFile>.from(state);
    updated[idx] = state[idx].withMetadata(
      durationMs: durationMs,
      resolution: resolution,
      thumbnail: thumbnail,
    );
    state = updated;
  }

  void clear() => state = [];
}

final selectedFilesProvider =
    StateNotifierProvider<SelectedFilesNotifier, List<VideoFile>>(
  (ref) => SelectedFilesNotifier(),
);

VideoFile buildVideoFile(String path, {String? displayName}) {
  final name = path.split('/').last;
  final origName = displayName ?? name;
  final sizeBytes = File(path).existsSync() ? File(path).lengthSync() : 0;
  final alreadyCompressed = origName.endsWith('_compressed.mp4');
  return VideoFile(
    path: path,
    name: name,
    displayName: origName,
    sizeBytes: sizeBytes,
    alreadyCompressed: alreadyCompressed,
    outputExists: false, // checked at encode time or by DateRangeScanner
    selected: !alreadyCompressed,
  );
}

