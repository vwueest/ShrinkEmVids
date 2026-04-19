enum ResolutionOption { p720, p1080, original }

extension ResolutionOptionX on ResolutionOption {
  String get label {
    switch (this) {
      case ResolutionOption.p720:
        return '720p';
      case ResolutionOption.p1080:
        return '1080p';
      case ResolutionOption.original:
        return '4K';
    }
  }

  /// Suggested bitrate for this resolution (kbps). The user can override.
  int get defaultBitrateKbps {
    switch (this) {
      case ResolutionOption.p720:
        return 1600;
      case ResolutionOption.p1080:
        return 3200;
      case ResolutionOption.original:
        return 6400;
    }
  }

  int get minBitrateKbps {
    switch (this) {
      case ResolutionOption.p720:
        return 500;
      case ResolutionOption.p1080:
        return 1000;
      case ResolutionOption.original:
        return 3000;
    }
  }

  int get maxBitrateKbps {
    switch (this) {
      case ResolutionOption.p720:
        return 3500;
      case ResolutionOption.p1080:
        return 7000;
      case ResolutionOption.original:
        return 12000;
    }
  }

  /// Step size in kbps.
  int get stepBitrateKbps {
    switch (this) {
      case ResolutionOption.p720:
        return 100;
      case ResolutionOption.p1080:
        return 200;
      case ResolutionOption.original:
        return 300;
    }
  }

  /// null means keep the source resolution.
  int? get maxHeight {
    switch (this) {
      case ResolutionOption.p720:
        return 720;
      case ResolutionOption.p1080:
        return 1080;
      case ResolutionOption.original:
        return null;
    }
  }

  /// Builds the ffmpeg argument list for this resolution and bitrate.
  List<String> buildFfmpegArgs(int bitrateKbps) {
    final args = <String>[];
    if (maxHeight != null) {
      final h = maxHeight!;
      args.addAll([
        '-vf',
        "scale='if(gte(iw,ih),-2,$h)':'if(gte(ih,iw),-2,$h)'",
      ]);
    }
    // Maxrate ~13% above target; bufsize = 2× target bitrate
    final maxrate = (bitrateKbps * 1.13).round();
    final bufsize = bitrateKbps * 2;
    // Scale audio bitrate with overall quality
    final audioBitrate = bitrateKbps >= 4000 ? 192 : bitrateKbps >= 2000 ? 128 : 96;
    args.addAll([
      '-c:v', 'hevc_mediacodec',
      '-pix_fmt', 'yuv420p',
      '-profile:v', 'main',
      '-level', '4.0',
      '-b:v', '${bitrateKbps}k',
      '-maxrate', '${maxrate}k',
      '-bufsize', '${bufsize}k',
      '-g', '30',
      '-force_key_frames', 'expr:gte(t,n_forced*2)',
      '-movflags', '+faststart',
      '-c:a', 'aac',
      '-b:a', '${audioBitrate}k',
    ]);
    return args;
  }
}

