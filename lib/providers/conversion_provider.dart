import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/conversion_result.dart';
import '../services/encoder_service.dart';

sealed class ConversionState {
  const ConversionState();
}

class ConversionIdle extends ConversionState {
  const ConversionIdle();
}

/// Briefly shown while re-subscribing to a service that is already running.
class ConversionConnecting extends ConversionState {
  const ConversionConnecting();
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

class ConversionStateNotifier extends Notifier<ConversionState> {
  static const _eventChannel = EventChannel(
    'com.transcoders.shrinkemvids/conversion_progress',
  );

  StreamSubscription<dynamic>? _subscription;

  @override
  ConversionState build() {
    ref.onDispose(() => _subscription?.cancel());
    _subscribeToEvents();
    _checkRunningService();
    return const ConversionIdle();
  }

  // ── EventChannel subscription ────────────────────────────────────────────

  void _subscribeToEvents() {
    _subscription = _eventChannel.receiveBroadcastStream().listen((event) {
      if (event is Map) _handleEvent(Map<String, dynamic>.from(event));
    }, onError: (_) {});
  }

  void _handleEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'progress':
        final index = (event['fileIndex'] as int?) ?? 0;
        final total = (event['totalFiles'] as int?) ?? 1;
        final percent = (event['percent'] as int?) ?? 0;
        final file = (event['file'] as String?) ?? '';
        state = ConversionInProgress(
          currentIndex: index,
          totalFiles: total,
          currentFileProgress: percent / 100.0,
          currentFileName: file,
        );
      case 'done':
        state = ConversionDone(_parseResults(event['results']));
      case 'cancelled':
        state = ConversionCancelled(_parseResults(event['results']));
    }
  }

  // ── Reconnect: check if a conversion is already running ─────────────────

  Future<void> _checkRunningService() async {
    try {
      final s = await EncoderService.getState();
      if (s != null && s['running'] == true) {
        state = ConversionInProgress(
          currentIndex: (s['currentFileIndex'] as int?) ?? 0,
          totalFiles: (s['totalFiles'] as int?) ?? 1,
          currentFileProgress: ((s['currentProgress'] as num?) ?? 0.0)
              .toDouble(),
          currentFileName: (s['currentFileName'] as String?) ?? '',
        );
      }
    } catch (_) {}
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  List<ConversionResult> _parseResults(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((r) {
      final m = Map<String, dynamic>.from(r as Map);
      return ConversionResult(
        inputPath: (m['inputPath'] as String?) ?? '',
        outputPath: (m['outputPath'] as String?) ?? '',
        inputSize: (m['inputSize'] as int?) ?? 0,
        outputSize: (m['outputSize'] as int?) ?? 0,
        success: (m['success'] as bool?) ?? false,
        error: m['error'] as String?,
      );
    }).toList();
  }

  void reset() => state = const ConversionIdle();
}

final conversionStateProvider =
    NotifierProvider<ConversionStateNotifier, ConversionState>(
      ConversionStateNotifier.new,
    );
