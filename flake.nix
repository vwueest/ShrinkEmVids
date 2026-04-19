{
  description = "ShrinkEmVids – Flutter Android dev environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };

        androidSdk = (pkgs.androidenv.composeAndroidPackages {
          cmdLineToolsVersion = "13.0";
          platformToolsVersion = "35.0.1";
          buildToolsVersions = [ "28.0.3" "34.0.0" "35.0.0" ];
          platformVersions = [ "34" "35" "36" ];
          abiVersions = [ "arm64-v8a" ];
          includeNDK = true;
          ndkVersions = [ "28.2.13676358" ];
          includeEmulator = false;
          includeSystemImages = false;
          extraLicenses = [
            "android-sdk-license"
            "android-sdk-preview-license"
            "android-sdk-arm-dbt-license"
            "android-googletv-license"
            "google-gdk-license"
            "intel-android-extra-license"
            "intel-android-sysimage-license"
            "mips-android-sysimage-license"
          ];
        }).androidsdk;

      in {
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.flutter
            androidSdk
            pkgs.jdk17
            pkgs.cmake
          ];

          shellHook = ''
            # Gradle needs a writable ANDROID_HOME — symlink the Nix SDK but keep
            # the directory itself writable so Gradle can cache metadata there.
            NIX_SDK="${androidSdk}/libexec/android-sdk"
            MUTABLE_SDK="$HOME/.shrinkemvids-android-sdk"
            if [[ "$(readlink -f "$MUTABLE_SDK/platform-tools" 2>/dev/null)" != "$(readlink -f "$NIX_SDK/platform-tools")" ]]; then
              rm -rf "$MUTABLE_SDK"
              mkdir -p "$MUTABLE_SDK"
              for item in "$NIX_SDK"/*; do
                ln -sfn "$item" "$MUTABLE_SDK/$(basename "$item")"
              done
            fi

            export ANDROID_HOME="$MUTABLE_SDK"
            export ANDROID_SDK_ROOT="$MUTABLE_SDK"
            export JAVA_HOME="${pkgs.jdk17}"
            export PATH="$MUTABLE_SDK/platform-tools:$MUTABLE_SDK/cmdline-tools/13.0/bin:$PATH"

            # Write local.properties so AGP uses nixpkgs cmake directly
            # (avoids SDK manager trying to install cmake into the read-only Nix store)
            cat > "$PWD/android/local.properties" << EOF
sdk.dir=$MUTABLE_SDK
cmake.dir=${pkgs.cmake}
EOF

            echo ""
            echo "  ShrinkEmVids dev shell ready"
            echo "  Flutter:  $(flutter --version 2>/dev/null | head -1)"
            echo "  Java:     $(java -version 2>&1 | head -1)"
            echo "  ADB:      $MUTABLE_SDK/platform-tools/adb"
            echo ""
          '';
        };
      }
    );
}
