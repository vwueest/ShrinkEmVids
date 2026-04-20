# Third-Party Licenses

## FFmpeg

This application includes pre-compiled FFmpeg shared libraries (`.so` files)
distributed via the
[ffmpeg_kit_flutter_new](https://pub.dev/packages/ffmpeg_kit_flutter_new)
package (a fork maintained by Anton Karpenko /
[`com.antonkarpenko.ffmpegkit`](https://github.com/antonkarpenko/ffmpeg-kit)).

FFmpeg is licensed under the
**GNU Lesser General Public License v2.1 or later (LGPL v2.1+)**.

- FFmpeg project: <https://ffmpeg.org>
- LGPL v2.1 full text: <https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html>
- ffmpeg-kit source (used to build the bundled `.so` files):
  <https://github.com/antonkarpenko/ffmpeg-kit>

### LGPL relinking notice

The LGPL v2.1 requires that end users be able to replace the FFmpeg shared
libraries with a version they compile themselves. This project satisfies that
requirement as follows:

- The FFmpeg code is linked **dynamically** as separate `.so` shared libraries
  (`libavcodec.so`, `libavformat.so`, `libavutil.so`, `libswscale.so`, etc.).
- The Gradle setting `jniLibs.useLegacyPackaging = true` in
  `android/app/build.gradle.kts` ensures those `.so` files are **extracted
  to disk** by the Android installer rather than being read directly from the
  compressed APK. This means they are accessible at a fixed path under
  `/data/app/<package>/lib/arm64/` and can be replaced.

**To relink with your own FFmpeg build:**

1. Clone <https://github.com/antonkarpenko/ffmpeg-kit> (or the upstream
   <https://github.com/arthenica/ffmpeg-kit>) and compile for `arm64-v8a`
   following the instructions in that repository.
2. Copy the resulting `.so` files into
   `android/app/src/main/jniLibs/arm64-v8a/`, replacing the bundled ones.
3. Rebuild the APK with `flutter build apk --release`.

---

## Other dependencies

All other runtime dependencies use **MIT**, **BSD-3-Clause**, or
**Apache 2.0** licenses, which are fully compatible with distribution
alongside this MIT-licensed application.

| Package | License |
|---|---|
| flutter_riverpod | MIT |
| permission_handler | MIT |
| path_provider | BSD-3-Clause |
| dynamic_color | Apache 2.0 |
| flutter_native_splash | MIT |
