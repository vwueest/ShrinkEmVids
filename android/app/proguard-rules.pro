# Keep all ffmpeg-kit classes — native JNI_OnLoad registers methods by exact
# class/method names, so R8 must not rename or remove any of them.
-keep class com.antonkarpenko.ffmpegkit.** { *; }
-keepclassmembers class com.antonkarpenko.ffmpegkit.** { *; }
