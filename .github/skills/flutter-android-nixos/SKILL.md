---
name: flutter-android-nixos
description: 'Flutter Android development on NixOS with nix develop. Use when: setting up the dev shell, fixing NixOS Android SDK errors (licenses not accepted, SDK not writable, aapt2 ELF errors, cmake install failures), building a release APK, fixing native .so load failures, fixing R8/ProGuard minification crashes, fixing Gradle wrapper network errors, or migrating away from file_picker.'
---

# Flutter Android Dev on NixOS — Knowledge Base

## When This Applies

- Setting up Flutter + Android SDK in a `nix develop` shell
- Fixing errors on NixOS:
  - `Some Android licenses not accepted`
  - `The SDK directory is not writable`
  - `aapt2 ... NixOS cannot run dynamically linked executables`
  - `Failed to install SDK components: cmake`
  - `Failed to read or create install properties file`
  - Gradle wrapper `UnknownHostException: services.gradle.org` (no network at build time)

---

## This Project's `flake.nix` Pattern

Key decisions already implemented in this repo:

- **`pkgs.cmake`** instead of `cmakeVersions` in `composeAndroidPackages` — the SDK cmake install always fails on NixOS (store is read-only)
- **Mutable SDK symlink** at `~/.shrinkemvids-android-sdk` — lets Gradle cache metadata while the Nix store stays read-only
- **`gradleZip = pkgs.fetchurl { … }`** — pins `gradle-8.14-all.zip` into the Nix store; `shellHook` pre-populates `~/.gradle/wrapper/dists/` so `flutter build` never needs network access
- **`pkgs.unzip`** in packages — needed by the shellHook extraction step
- **`android/local.properties`** written by `shellHook` with `sdk.dir` and `cmake.dir` pointing to the mutable SDK and nixpkgs cmake

### Required NixOS System Config

```nix
# Needed for Gradle-downloaded binaries (aapt2, etc.) — generic ELF executables
programs.nix-ld.enable = true;

# Needed for flakes
nix.settings.experimental-features = [ "nix-command" "flakes" ];
```

Apply with `sudo nixos-rebuild switch`.

> Without `nix-ld`, AAPT2 (downloaded by Gradle from Maven) fails with:
> `NixOS cannot run dynamically linked executables intended for generic linux environments`

---

## Android Release Build Gotchas (Flutter + ffmpeg-kit)

### 1. Native `.so` fails to load from compressed APK (`UnsatisfiedLinkError: Bad JNI version … 0`)

**Symptom:** App crashes on launch in release build only; logcat shows
`UnsatisfiedLinkError: Bad JNI version returned from JNI_OnLoad in "base.apk!/lib/arm64-v8a/libffmpegkit_abidetect.so": 0`

**Cause:** AGP defaults to `extractNativeLibs=false` in release — `.so` files are mmap'd directly from the compressed APK. ffmpeg-kit `.so` files are not built for page-aligned APK storage.

**Fix** (already applied in this project's `android/app/build.gradle.kts`):
```kotlin
packaging {
    jniLibs {
        useLegacyPackaging = true   // extract .so to disk on install
    }
}
```

This also compresses `.so` files inside the APK, significantly reducing download size.

---

### 2. R8 renames ffmpeg-kit classes → `JNI_OnLoad` returns 0 (release only)

**Symptom:** Same `Bad JNI version … 0` crash even after `useLegacyPackaging`.

**Cause:** R8 minification renames Java classes that `JNI_OnLoad` registers via `RegisterNatives`. The fork used here (`com.antonkarpenko.ffmpegkit`) doesn't ship ProGuard rules for its package name.

**Fix** (already applied in this project's `android/app/proguard-rules.pro`):
```proguard
-keep class com.antonkarpenko.ffmpegkit.** { *; }
-keepclassmembers class com.antonkarpenko.ffmpegkit.** { *; }
```

Referenced in `build.gradle.kts`:
```kotlin
buildTypes {
    release {
        proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
    }
}
```

---

### 3. `file_picker` broken in release APK

`file_picker` 8.1.x → `MissingPluginException` in release. 8.3.x → opens file browser instead of media picker on Android 13+.

**Fix** (already applied in this project): Native `MethodChannel` picker using `MediaStore.ACTION_PICK_IMAGES` (Android 13+) or `Intent.ACTION_GET_CONTENT` (older). See `android/app/src/main/kotlin/…/MainActivity.kt`.

---

### 4. Gradle wrapper needs network (`UnknownHostException: services.gradle.org`)

**Cause:** Gradle wrapper downloads itself on first run, but `flutter build` runs without network.

**Fix** (already applied): `gradleZip = pkgs.fetchurl { … }` in `flake.nix` fetches the zip into the Nix store during `nix develop`, which does have network access. The `shellHook` extracts it into `~/.gradle/wrapper/dists/` if not already present.

When changing the Gradle version in `android/gradle/wrapper/gradle-wrapper.properties`, update `flake.nix`:
1. Run `nix-prefetch-url --type sha256 <distribution-url>` to get the hash
2. Convert with `nix hash convert --hash-algo sha256 --to sri <hash>`
3. Update `gradleZip.url`, `gradleZip.hash`, and the `GRADLE_DIST_DIR` path in `shellHook`

---

## MediaStore & Metadata

### Compressed video sorted at "now" instead of next to original in Google Photos

**Cause:** Two issues:
1. FFmpeg drops container metadata without `-map_metadata 0` — output MP4 has no `creation_time` tag
2. MediaStore insert without `DATE_TAKEN` → Android stamps it with insertion time

**Fix** (already applied):
- Add `-map_metadata`, `"0"` to FFmpeg args in `ConversionForegroundService.kt`
- Before `copyToMovies` insert, query source file's `DATE_TAKEN` from MediaStore and set it on the new `ContentValues`
