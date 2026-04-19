import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SelectionMode { filePicker, dateRange }

final selectionModeProvider = StateProvider<SelectionMode>((ref) => SelectionMode.filePicker);

final dateFromProvider = StateProvider<DateTime?>((ref) => null);
final dateToProvider = StateProvider<DateTime?>((ref) => null);
final dateRangeScanningProvider = StateProvider<bool>((ref) => false);
