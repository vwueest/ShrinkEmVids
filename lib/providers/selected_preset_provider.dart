import 'package:flutter_riverpod/legacy.dart';
import '../models/encoding_preset.dart';

final resolutionProvider =
    StateProvider<ResolutionOption>((ref) => ResolutionOption.p1080);

final bitrateKbpsProvider =
    StateProvider<int>((ref) => ResolutionOption.p1080.defaultBitrateKbps);
