import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/conversion_provider.dart';

class ProgressScreen extends ConsumerWidget {
  final VoidCallback onSkip;
  final VoidCallback onCancelAll;

  const ProgressScreen({
    super.key,
    required this.onSkip,
    required this.onCancelAll,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(conversionStateProvider);

    if (state is ConversionInProgress) {
      return _buildProgress(context, state);
    }

    // Shouldn't normally be visible — navigation handles done/cancelled
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
                    onPressed: onSkip,
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
                    onPressed: onCancelAll,
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

