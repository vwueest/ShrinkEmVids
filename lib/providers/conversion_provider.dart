import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/conversion_result.dart';

sealed class ConversionState {
  const ConversionState();
}

class ConversionIdle extends ConversionState {
  const ConversionIdle();
}

class ConversionInProgress extends ConversionState {
  final int currentIndex;
  final int totalFiles;
  final double currentFileProgress; // 0.0 – 1.0
  final String currentFileName;

  const ConversionInProgress({
    required this.currentIndex,
    required this.totalFiles,
    required this.currentFileProgress,
    required this.currentFileName,
  });
}

class ConversionDone extends ConversionState {
  final List<ConversionResult> results;
  const ConversionDone(this.results);
}

class ConversionCancelled extends ConversionState {
  final List<ConversionResult> partial;
  const ConversionCancelled(this.partial);
}

class ConversionStateNotifier extends StateNotifier<ConversionState> {
  ConversionStateNotifier() : super(const ConversionIdle());

  void setProgress(int index, int total, double progress, String fileName) {
    state = ConversionInProgress(
      currentIndex: index,
      totalFiles: total,
      currentFileProgress: progress,
      currentFileName: fileName,
    );
  }

  void setDone(List<ConversionResult> results) {
    state = ConversionDone(results);
  }

  void setCancelled(List<ConversionResult> partial) {
    state = ConversionCancelled(partial);
  }

  void reset() => state = const ConversionIdle();
}

final conversionStateProvider =
    StateNotifierProvider<ConversionStateNotifier, ConversionState>(
  (ref) => ConversionStateNotifier(),
);
