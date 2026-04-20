# ShrinkEmVids

<p align="center">
  <img src="assets/app_icon.png" alt="ShrinkEmVids logo" width="120"/>
</p>

<p align="center">
  <img src="screenshots/1_home_empty.png" width="19%" alt="Home (empty)"/>
  &nbsp;
  <img src="screenshots/2_home_file_list.png" width="19%" alt="File list"/>
  &nbsp;
  <img src="screenshots/3_converting.png" width="19%" alt="Converting"/>
  &nbsp;
  <img src="screenshots/4_converted.png" width="19%" alt="Done"/>
</p>

Android app (Flutter) that re-encodes videos from DCIM/Camera at a lower resolution and bitrate, saving them back to your gallery to save precious storage space.

## Features

- Pick multiple videos via the native Android media picker
- Choose from preset quality profiles (480p, 720p, 1080p) with adjustable bitrate
- Background encoding — keeps going while the app is minimised, with a persistent notification and cancel/skip controls
- Progress screen shows per-file and overall progress
- Skips files whose compressed version already exists in DCIM/Camera
- Dynamic colour (Material You) theming

## Requirements

- Android 13+ (API 33)
- arm64-v8a device
- ADB / `flutter run` for local development

## Building

The project uses a Nix flake devShell that bundles Flutter, the Android SDK, and JDK 17.

```bash
# Enter the dev shell
nix develop

# Run on a connected device
flutter run

# Build release APK
flutter build apk --release

# Install
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

> **NixOS users:** `programs.nix-ld.enable = true;` is required in your system config for Gradle-downloaded binaries (aapt2, etc.) to run.

## Architecture

| Layer | Details |
|---|---|
| UI | Flutter (Riverpod state management, Material You) |
| Encoding | `ffmpeg_kit_flutter_new` (sk3llo fork, `com.antonkarpenko.ffmpegkit`) — runs inside an Android `ForegroundService` |
| Kotlin side | `ConversionForegroundService` — wake lock, progress notifications, cancel/skip |
| Flutter ↔ Kotlin | `MethodChannel` for commands, `EventChannel` for streaming progress events |
| Media access | Native `MediaStore` queries via `MethodChannel`; no file_picker dependency |

## Permissions

- `READ_MEDIA_VIDEO` (Android 13+) / `READ_EXTERNAL_STORAGE` (≤ Android 12)
- `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`
- `WAKE_LOCK`
- `POST_NOTIFICATIONS`

## Notable build notes

- **ProGuard / R8**: `proguard-rules.pro` keeps all `com.antonkarpenko.ffmpegkit.*` classes — R8 would otherwise rename them and break `JNI_OnLoad` in the native `.so` at runtime (crashes release build only).
- **Native lib packaging**: `jniLibs.useLegacyPackaging = true` forces `.so` files to be extracted on install. Without this, some ffmpeg-kit `.so` files fail to load from the compressed APK.
- **ABI filter**: only `arm64-v8a` is included, keeping the APK at ~30 MB.
