import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/home_screen.dart';

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const ProviderScope(child: ShrinkEmVidsApp()));
}

// Fallback for devices without Material You (Android < 12)
const _fallbackSeed = Colors.blueGrey;

class ShrinkEmVidsApp extends StatelessWidget {
  const ShrinkEmVidsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final colorScheme =
            darkDynamic ??
            ColorScheme.fromSeed(
              seedColor: _fallbackSeed,
              brightness: Brightness.dark,
            );
        return MaterialApp(
          title: 'ShrinkEmVids',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorScheme: colorScheme, useMaterial3: true),
          home: const HomeScreen(),
        );
      },
    );
  }
}
