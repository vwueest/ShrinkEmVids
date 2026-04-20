---
name: release-workflow
description: 'Pre-commit hooks, testing, changelog, versioning and release workflow for this Flutter project. Use when: setting up or debugging pre-commit hooks, running or writing tests, bumping the version, building release APKs, tagging a release, or publishing to GitHub Releases for Obtainium.'
---

# Release Workflow — Knowledge Base

## Pre-commit Hooks

This project uses the `pre-commit` framework with hooks defined in `.pre-commit-config.yaml`.

### Hook stages

| Hook | Stage | What it does |
|---|---|---|
| `trailing-whitespace` | commit | Strips trailing spaces |
| `end-of-file-fixer` | commit | Ensures newline at EOF |
| `check-yaml` | commit | Validates YAML syntax |
| `check-json` | commit | Validates JSON syntax |
| `check-merge-conflict` | commit | Catches unresolved `<<<<<<` markers |
| `check-added-large-files` | commit | Fails if any file >500 KB is staged |
| `dart-format` | commit | Fails if any `.dart` file isn't formatted |
| `flutter-analyze` | commit | Runs `flutter analyze --no-fatal-infos` |
| `flutter-test` | push | Runs `flutter test` |

### Auto-installation

`pre-commit` is in the Nix dev shell (`pkgs.pre-commit`). The `flake.nix` `shellHook` auto-installs hooks on first `nix develop` if `.git/hooks/pre-commit` doesn't exist yet:

```bash
if [[ -d .git ]] && [[ ! -f .git/hooks/pre-commit ]]; then
  pre-commit install --install-hooks
  pre-commit install --hook-type pre-push
fi
```

### Testing hooks manually

```bash
# Run all commit-stage hooks against every file
pre-commit run --all-files

# Run a single hook
pre-commit run dart-format --all-files
pre-commit run flutter-analyze --all-files

# Run push-stage hooks (flutter test)
pre-commit run --hook-stage pre-push --all-files
```

### Re-installing hooks after flake.nix changes

```bash
nix develop --command pre-commit install --install-hooks
nix develop --command pre-commit install --hook-type pre-push
```

### Common analyzer issues and fixes

| Warning | Fix |
|---|---|
| `curly_braces_in_flow_control_structures` | Wrap `if` body in `{ }` |
| `unnecessary_import` | Remove the import (e.g. `dart:typed_data` masked by `flutter/services.dart`) |
| `unnecessary_dev_dependency` | Remove the duplicate from `dev_dependencies` in `pubspec.yaml` |

Always run `flutter analyze --no-fatal-infos` (not plain `flutter analyze`) in hooks and CI — plain analyze treats infos as errors and fails on benign style notes.

---

## Testing

All tests are pure-Dart unit tests — no device or emulator needed.

```bash
# Run all tests
nix develop --command flutter test

# Scope to a directory
nix develop --command flutter test test/models/
nix develop --command flutter test test/providers/

# Filter by name
nix develop --command flutter test --name "isEligible"
nix develop --command flutter test --name "buildFfmpegArgs"

# Coverage report
nix develop --command flutter test --coverage
genhtml coverage/lcov.info -o coverage/html && xdg-open coverage/html/index.html
```

### Test coverage map

| Source file | Test file |
|---|---|
| `lib/models/video_file.dart` | `test/models/video_file_test.dart` |
| `lib/models/encoding_preset.dart` | `test/models/encoding_preset_test.dart` |
| `lib/providers/selected_files_provider.dart` | `test/providers/selected_files_provider_test.dart` |
| `lib/providers/selected_preset_provider.dart` | `test/providers/selected_preset_provider_test.dart` |

The Kotlin/Android layer and FFmpeg invocations are not unit-tested (would need instrumentation tests). Keep the Dart layer thin and testable.

---

## Versioning

Version lives in one place: `pubspec.yaml`.

```yaml
version: 0.3.0+3
#        ^^^^^  ^
#        semver build number (versionCode in Android)
```

**Rules:**
- Increment `versionCode` (`+N`) on every release — Android uses this to validate upgrades
- Use semver for the name:
  - Patch (`0.3.x`) — bug fixes only
  - Minor (`0.x.0`) — new user-visible features
  - Major (`x.0.0`) — breaking change or significant rewrite
- The version in `pubspec.yaml` is injected automatically into the APK by the Flutter Gradle plugin via `flutter.versionCode` / `flutter.versionName` — no need to touch `build.gradle.kts`

### History

| Tag | Version | Notes |
|---|---|---|
| v0.1 | 0.1.0+1 | Initial release |
| v0.2 | 0.2.0+2 | Share target, background encoding |
| v0.3 | 0.3.0+3 | MIT license, release signing, pre-commit, multi-ABI APKs |

---

## Building Release APKs

```bash
# Always use --split-per-abi — produces one APK per ABI
nix develop --command flutter build apk --release --split-per-abi
```

Output files:
```
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk   # ~30 MB  — distribute this
build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk # ~50 MB  — optional, older phones
build/app/outputs/flutter-apk/app-x86_64-release.apk      # ~32 MB  — emulators only, skip
```

**Do NOT use `--target-platform android-arm64`** — that flag only filters Flutter's own `.so`, not the AAR native libs (ffmpeg-kit). Use `--split-per-abi` instead.

**Do NOT add `ndk { abiFilters += "arm64-v8a" }` in Gradle** — it conflicts with Flutter's `--split-per-abi` splits with error: `Conflicting configuration: 'arm64-v8a' in ndk abiFilters cannot be present when splits abi filters are set`.

### Signing

Release APKs are signed with a keystore whose credentials are in `android/key.properties` (gitignored). Format:

```properties
storeFile=../keystore.jks
storePassword=your_store_password
keyAlias=shrinkemvids
keyPassword=your_key_password
```

`build.gradle.kts` loads this file at build time. If `key.properties` is absent it falls back to the debug keystore (fine for local dev, not for distribution).

To create a new keystore:
```bash
nix develop --command keytool -genkey -v \
  -keystore android/keystore.jks \
  -alias shrinkemvids \
  -keyalg RSA -keysize 2048 -validity 10000
```

**Back up `android/keystore.jks` and the passwords.** Losing the keystore means existing installs can never receive an update — users must uninstall and reinstall.

---

## Release Checklist

Before tagging a release:

1. **Run tests**: `nix develop --command flutter test` — all must pass
2. **Run analyze**: `nix develop --command flutter analyze --no-fatal-infos` — 0 issues
3. **Bump version** in `pubspec.yaml` (semver + build number)
4. **Rebuild APKs**: `nix develop --command flutter build apk --release --split-per-abi`
5. **Commit**: `git add … && git commit -m "release X.Y.Z: …"` (pre-commit hooks run automatically)
6. **Tag**: `git tag -a vX.Y -m "vX.Y.Z — summary"`
7. **Push commit + tag**: `git push && git push --tags`
8. **Create GitHub Release** (see below)

---

## Publishing a GitHub Release from the CLI

Use the `gh` CLI (available in the Nix dev shell via `~/.nix-profile`).

```bash
gh release create vX.Y \
  build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
  build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk \
  --title "vX.Y.Z" \
  --notes "## What's new

- Feature / fix description

## Install

- **\`app-arm64-v8a-release.apk\`** — all phones made after 2017
- **\`app-armeabi-v7a-release.apk\`** — older 32-bit phones

**Obtainium**: set APK filter to \`arm64-v8a\`."
```

The tag must already exist on the remote (`git push --tags`) before running this.

To verify `gh` is authenticated: `gh auth status`

---

## Updating the GitHub Repo's About Section

```bash
gh repo edit \
  --description "Your description here" \
  --add-topic flutter \
  --add-topic android \
  --add-topic ffmpeg \
  --add-topic video-compression \
  --add-topic kotlin
```

Current description: "Android app that shrinks camera videos using FFmpeg and hardware HEVC encoding (MediaCodec)"

---

## GitHub Releases & Obtainium

- Upload both APKs to a GitHub Release attached to the annotated tag
- Obtainium config: point at the GitHub repo, set APK filter regex `arm64-v8a` so it picks the right file automatically
- The armeabi-v7a APK is optional — include it if you want to support phones older than ~2017

---

## Licensing Notes

- **Source code**: MIT — see `LICENSE`
- **Bundled FFmpeg** (via `ffmpeg_kit_flutter_new`): LGPL v2.1+ — see `THIRD_PARTY_LICENSES.md`
- LGPL relinking requirement is satisfied by `jniLibs.useLegacyPackaging = true` in `build.gradle.kts`, which extracts `.so` files to disk at install time, making them replaceable
- Do **not** remove `useLegacyPackaging = true` — it is required both for LGPL compliance and to prevent `UnsatisfiedLinkError` on some devices (ffmpeg-kit `.so` files are not page-aligned for compressed-APK mmap)
