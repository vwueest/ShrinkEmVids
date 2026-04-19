import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/conversion_result.dart';
import '../models/encoding_preset.dart';
import '../models/video_file.dart';
import '../providers/conversion_provider.dart';
import '../providers/selected_files_provider.dart';
import '../providers/selected_preset_provider.dart';
import '../providers/selection_mode_provider.dart';
import '../services/date_range_scanner.dart';
import '../services/encoder_service.dart';
import '../services/media_scanner_service.dart';
import '../services/thumbnail_service.dart';
import 'progress_screen.dart';
import 'done_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  // ── File picker mode ──────────────────────────────────────────────────────

  Future<void> _pickFiles(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
    );
    if (result == null) return;
    // On Android 12+ the photo picker caches files as "<mediaId>.mp4" and
    // reports that as f.name — resolve the real DISPLAY_NAME from MediaStore.
    Future<String> resolveDisplayName(String pickerName) async {
      final stem = pickerName.endsWith('.mp4')
          ? pickerName.substring(0, pickerName.length - 4)
          : pickerName;
      if (RegExp(r'^\d+$').hasMatch(stem)) {
        final real = await MediaScannerService.resolveDisplayName(stem);
        if (real != null) return real;
      }
      return pickerName;
    }

    var files = <VideoFile>[];
    for (final f in result.files.where((f) => f.path != null)) {
      final displayName = await resolveDisplayName(f.name);
      files.add(buildVideoFile(f.path!, displayName: displayName));
    }
    // Check which outputs already exist in DCIM/Camera
    final existing = await MediaScannerService.getExistingOutputNames();
    files = files.map((f) {
      if (existing.contains(f.outputFileName)) {
        return f.copyWith(outputExists: true, selected: false);
      }
      return f;
    }).toList();
    ref.read(selectedFilesProvider.notifier).addFiles(files);
    _loadMetadata(ref, files);
  }

  // ── Date range mode ───────────────────────────────────────────────────────

  Future<void> _scanDateRange(BuildContext context, WidgetRef ref) async {
    final from = ref.read(dateFromProvider);
    final to = ref.read(dateToProvider);
    if (from == null || to == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both dates first')),
      );
      return;
    }
    final status = await Permission.videos.request();
    if (!status.isGranted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video permission required to scan DCIM/Camera')),
        );
      }
      return;
    }
    ref.read(dateRangeScanningProvider.notifier).state = true;
    try {
      final files = await DateRangeScanner.scan(from, to);
      ref.read(selectedFilesProvider.notifier).replaceAll(files);
      _loadMetadata(ref, files);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: $e')),
        );
      }
    } finally {
      ref.read(dateRangeScanningProvider.notifier).state = false;
    }
  }

  // ── Metadata loading ──────────────────────────────────────────────────────

  void _loadMetadata(WidgetRef ref, List<VideoFile> files) {
    for (final file in files) {
      _loadFileMetadata(ref, file);
    }
  }

  Future<void> _loadFileMetadata(WidgetRef ref, VideoFile file) async {
    // Thumbnail
    final thumbnail = await ThumbnailService.getThumbnail(file.path);
    if (thumbnail != null) {
      ref.read(selectedFilesProvider.notifier).updateMetadata(file.path, thumbnail: thumbnail);
    }
    // Duration + resolution
    try {
      final session = await FFprobeKit.getMediaInformation(file.path);
      final info = session.getMediaInformation();
      int? durationMs;
      String? resolution;
      final dur = info?.getDuration();
      if (dur != null) {
        final secs = double.tryParse(dur);
        if (secs != null) durationMs = (secs * 1000).toInt();
      }
      final streams = info?.getStreams();
      if (streams != null) {
        for (final s in streams) {
          final w = s.getWidth();
          final h = s.getHeight();
          if (w != null && h != null && w > 0) {
            resolution = '${w}x$h';
            break;
          }
        }
      }
      if (durationMs != null || resolution != null) {
        ref.read(selectedFilesProvider.notifier).updateMetadata(
          file.path,
          durationMs: durationMs,
          resolution: resolution,
        );
      }
    } catch (_) {}
  }

  // ── Conversion ────────────────────────────────────────────────────────────

  Future<void> _startConversion(BuildContext context, WidgetRef ref) async {
    final files = ref.read(selectedFilesProvider);
    final resolution = ref.read(resolutionProvider);
    final bitrateKbps = ref.read(bitrateKbpsProvider);
    final toConvert = files.where((f) => f.selected && f.isEligible).toList();
    if (toConvert.isEmpty) return;

    final notifier = ref.read(conversionStateProvider.notifier);
    final encoder = EncoderService();
    encoder.reset();

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProgressScreen(
        onSkip: () => encoder.skipCurrentFile(),
        onCancelAll: () => encoder.cancelAll(),
      ),
    ));

    final results = <ConversionResult>[];
    for (int i = 0; i < toConvert.length; i++) {
      if (encoder.isCancelAllRequested) break;
      final file = toConvert[i];
      notifier.setProgress(i, toConvert.length, 0.0, file.displayName);

      final result = await encoder.encode(
        file,
        resolution,
        bitrateKbps,
        onProgress: (p) => notifier.setProgress(i, toConvert.length, p, file.displayName),
      );
      results.add(result);

      if (result.success) {
        await MediaScannerService.scan(result.outputPath);
      }
    }

    if (encoder.isCancelAllRequested) {
      notifier.setCancelled(results);
    } else {
      notifier.setDone(results);
    }

    if (context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => DoneScreen(results: results)),
      );
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return 'Tap to select';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(selectionModeProvider);
    final files = ref.watch(selectedFilesProvider);
    final eligible = files.where((f) => f.selected && f.isEligible).toList();
    final totalSize = eligible.fold<int>(0, (sum, f) => sum + f.sizeBytes);

    return Scaffold(
      appBar: AppBar(title: const Text('ShrinkEmVids')),
      body: Column(
        children: [
          _buildModeToggle(ref, mode),
          Expanded(
            child: mode == SelectionMode.filePicker
                ? _buildFilePickerBody(context, ref, files)
                : _buildDateRangeBody(context, ref, files),
          ),
          _buildBottomBar(context, ref, eligible, totalSize),
        ],
      ),
    );
  }

  Widget _buildModeToggle(WidgetRef ref, SelectionMode mode) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SegmentedButton<SelectionMode>(
        segments: const [
          ButtonSegment(
            value: SelectionMode.filePicker,
            label: Text('Pick Files'),
            icon: Icon(Icons.folder_open),
          ),
          ButtonSegment(
            value: SelectionMode.dateRange,
            label: Text('By Date'),
            icon: Icon(Icons.date_range),
          ),
        ],
        selected: {mode},
        onSelectionChanged: (val) =>
            ref.read(selectionModeProvider.notifier).state = val.first,
      ),
    );
  }

  // ── File picker body ──────────────────────────────────────────────────────

  Widget _buildFilePickerBody(BuildContext context, WidgetRef ref, List<VideoFile> files) {
    if (files.isEmpty) {
      return Center(
        child: ElevatedButton.icon(
          icon: const Icon(Icons.folder_open),
          label: const Text('Pick Video Files'),
          onPressed: () => _pickFiles(context, ref),
        ),
      );
    }
    return Column(
      children: [
        Expanded(child: _buildFileList(context, ref, files)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add More'),
                onPressed: () => _pickFiles(context, ref),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.clear_all),
                label: const Text('Clear'),
                onPressed: () => ref.read(selectedFilesProvider.notifier).clear(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Date range body ───────────────────────────────────────────────────────

  Widget _buildDateRangeBody(BuildContext context, WidgetRef ref, List<VideoFile> files) {
    final from = ref.watch(dateFromProvider);
    final to = ref.watch(dateToProvider);
    final isScanning = ref.watch(dateRangeScanningProvider);

    return Column(
      children: [
        _buildDateRow(context, ref, 'From', from,
            (d) => ref.read(dateFromProvider.notifier).state = d),
        _buildDateRow(context, ref, 'To', to,
            (d) => ref.read(dateToProvider.notifier).state = d),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: isScanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.search),
              label: Text(isScanning ? 'Scanning…' : 'Scan DCIM/Camera'),
              onPressed: isScanning ? null : () => _scanDateRange(context, ref),
            ),
          ),
        ),
        if (files.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  '${files.length} video${files.length == 1 ? '' : 's'} found',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => ref.read(selectedFilesProvider.notifier).selectAllEligible(),
                  child: const Text('Select All New'),
                ),
                TextButton(
                  onPressed: () => ref.read(selectedFilesProvider.notifier).deselectAll(),
                  child: const Text('Deselect All'),
                ),
              ],
            ),
          ),
          Expanded(child: _buildFileList(context, ref, files)),
        ] else
          const Expanded(child: SizedBox()),
      ],
    );
  }

  Widget _buildDateRow(
    BuildContext context,
    WidgetRef ref,
    String label,
    DateTime? date,
    void Function(DateTime) onPicked,
  ) {
    return ListTile(
      leading: SizedBox(width: 40, child: Text(label)),
      title: Text(
        _fmtDate(date),
        style: date == null
            ? TextStyle(color: Theme.of(context).disabledColor)
            : null,
      ),
      trailing: const Icon(Icons.calendar_today, size: 18),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (picked != null) onPicked(picked);
      },
    );
  }

  // ── Shared file list ──────────────────────────────────────────────────────

  Widget _buildFileList(BuildContext context, WidgetRef ref, List<VideoFile> files) {
    return ListView.builder(
      itemCount: files.length,
      itemBuilder: (ctx, i) {
        final file = files[i];
        return _FileTile(
          file: file,
          onToggle: file.isEligible
              ? () => ref.read(selectedFilesProvider.notifier).toggleSelection(i)
              : null,
        );
      },
    );
  }

  // ── Bottom bar ────────────────────────────────────────────────────────────

  Widget _buildBottomBar(
    BuildContext context,
    WidgetRef ref,
    List<VideoFile> eligible,
    int totalSize,
  ) {
    final resolution = ref.watch(resolutionProvider);
    final bitrateKbps = ref.watch(bitrateKbpsProvider);
    final mbps = bitrateKbps / 1000.0;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<ResolutionOption>(
              segments: ResolutionOption.values.map((r) {
                return ButtonSegment<ResolutionOption>(
                  value: r,
                  label: Text(r.label),
                );
              }).toList(),
              selected: {resolution},
              onSelectionChanged: (val) {
                final r = val.first;
                ref.read(resolutionProvider.notifier).state = r;
                ref.read(bitrateKbpsProvider.notifier).state = r.defaultBitrateKbps;
              },
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    '${(resolution.minBitrateKbps / 1000.0).toStringAsFixed(1)} Mbps',
                    style: const TextStyle(fontSize: 11),
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: bitrateKbps.toDouble().clamp(
                        resolution.minBitrateKbps.toDouble(),
                        resolution.maxBitrateKbps.toDouble()),
                    min: resolution.minBitrateKbps.toDouble(),
                    max: resolution.maxBitrateKbps.toDouble(),
                    divisions: ((resolution.maxBitrateKbps - resolution.minBitrateKbps) ~/
                            resolution.stepBitrateKbps)
                        .clamp(1, 200),
                    label: '${mbps.toStringAsFixed(1)} Mbps',
                    onChanged: (val) =>
                        ref.read(bitrateKbpsProvider.notifier).state = val.round(),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    '${(resolution.maxBitrateKbps / 1000.0).toStringAsFixed(0)} Mbps',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (eligible.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${eligible.length} file${eligible.length == 1 ? '' : 's'} · ${_formatSize(totalSize)} · ${mbps.toStringAsFixed(1)} Mbps',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Convert Selected'),
              onPressed: eligible.isEmpty ? null : () => _startConversion(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}

// ── File tile ─────────────────────────────────────────────────────────────────

class _FileTile extends StatelessWidget {
  final VideoFile file;
  final VoidCallback? onToggle;

  const _FileTile({required this.file, this.onToggle});

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    final isBlocked = !file.isEligible;
    final blockedReason = file.alreadyCompressed
        ? 'Already compressed'
        : file.outputExists
            ? 'Output already exists'
            : null;

    final meta = <String>[_formatSize(file.sizeBytes)];
    if (file.formattedDuration.isNotEmpty) meta.add(file.formattedDuration);
    if (file.resolution != null) meta.add(file.resolution!);

    return InkWell(
      onTap: isBlocked ? null : onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Checkbox(
              value: file.selected && file.isEligible,
              onChanged: isBlocked ? null : (_) => onToggle?.call(),
              tristate: false,
            ),
            const SizedBox(width: 8),
            _buildThumbnail(file.thumbnail),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: isBlocked ? Theme.of(context).disabledColor : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    blockedReason ?? meta.join(' · '),
                    style: TextStyle(
                      fontSize: 12,
                      color: blockedReason != null ? Colors.orange : Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(Uint8List? thumbnail) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 72,
        height: 48,
        child: thumbnail != null
            ? Image.memory(thumbnail, fit: BoxFit.cover)
            : ColoredBox(
                color: Colors.grey.shade800,
                child: const Center(
                  child: Icon(Icons.videocam, size: 24, color: Colors.white38),
                ),
              ),
      ),
    );
  }
}

