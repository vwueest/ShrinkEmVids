import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/conversion_result.dart';
import '../providers/conversion_provider.dart';
import '../providers/selected_files_provider.dart';

class DoneScreen extends ConsumerWidget {
  final List<ConversionResult> results;

  const DoneScreen({super.key, required this.results});

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final successful = results.where((r) => r.success).toList();
    final failed = results
        .where((r) => !r.success && r.error != 'Cancelled')
        .toList();
    final totalSaved = successful.fold<int>(0, (sum, r) => sum + r.savedBytes);

    return Scaffold(
      appBar: AppBar(title: const Text('Done')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 64,
              color: Colors.green,
            ),
            const SizedBox(height: 24),
            Text(
              '${successful.length} file${successful.length == 1 ? '' : 's'} converted',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Space saved: ${_formatSize(totalSaved)}',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            if (failed.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '${failed.length} failed — see details below',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: failed
                      .map(
                        (r) => ListTile(
                          title: Text(
                            r.inputPath.split('/').last,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            r.error ?? 'Unknown error',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          leading: const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ] else
              const Spacer(),
            FilledButton.icon(
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to Home'),
              onPressed: () {
                ref.read(selectedFilesProvider.notifier).clear();
                ref.read(conversionStateProvider.notifier).reset();
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
          ],
        ),
      ),
    );
  }
}
