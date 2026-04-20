import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/conversion_provider.dart';
import '../services/encoder_service.dart';
import 'done_screen.dart';

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Navigate to DoneScreen / back to HomeScreen when the service finishes
    ref.listen<ConversionState>(conversionStateProvider, (_, next) {
      if (next is ConversionDone) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => DoneScreen(results: next.results)),
        );
      } else if (next is ConversionCancelled) {
        ref.read(conversionStateProvider.notifier).reset();
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    });

    final state = ref.watch(conversionStateProvider);

    if (state is ConversionConnecting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (state is ConversionInProgress) {
      return _buildProgress(context, state);
    }

    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }

  Widget _buildProgress(BuildContext context, ConversionInProgress state) {
    return Scaffold(
      appBar: AppBar(title: const Text('Converting…')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              state.currentFileName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: state.currentFileProgress),
            const SizedBox(height: 8),
            Text(
              '${(state.currentFileProgress * 100).toStringAsFixed(0)}%',
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 32),
            Text(
              'File ${state.currentIndex + 1} of ${state.totalFiles}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: state.totalFiles > 0
                  ? state.currentIndex / state.totalFiles
                  : 0,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.skip_next),
                    label: const Text('Skip File'),
                    onPressed: EncoderService.skipCurrentFile,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.stop),
                    label: const Text('Cancel All'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: EncoderService.cancelAll,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
