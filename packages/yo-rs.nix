{
  self,
  lib,
  pkgs,
  rustPlatform,
  fetchFromGitHub,
  ...
} : let
  src = ./yo-rs;
  cargoToml = builtins.fromTOML (builtins.readFile (src + "/Cargo.toml"));
  version = cargoToml.package.version;
  desc = cargoToml.package.description;

  tinyWhisper = pkgs.fetchurl {
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin";
    sha256 = "sha256-vgfgSOHlma1GNByNKhNWRQl6U4IhZ4t6zdGxkZxuGyE=";
  };

  smallWhisper = pkgs.fetchurl {
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin";
    sha256 = "sha256-G+OpsgY4Z7k35k4ux0gzZKeZF+FX+pjF2UtcH//qmHs=";
  };

  piperVoices = pkgs.fetchgit {
    url            = "https://huggingface.co/rhasspy/piper-voices";
    rev            = "375a0fe641dea077c2a47b4e9a056d6da521eed3";  # tag v1.0.0
    fetchLFS       = true;
    sparseCheckout = [ "en/en_US/amy/medium" "sv/sv_SE/lisa/medium" ];
    sha256         = "0f5myl87yj2l31xg9s6cav94v7imai20qhc2qhshj40ibd1wbar2";
  };

in
rustPlatform.buildRustPackage {
  pname = "yo-rs";
  inherit version;
  src = src;
  cargoLock = { lockFile = src + "/Cargo.lock"; };

  nativeBuildInputs = [
    pkgs.pkg-config
    pkgs.cmake
    pkgs.libclang
    rustPlatform.bindgenHook
  ];

  buildInputs = [
    pkgs.openssl.dev
    pkgs.alsa-lib-with-plugins
    pkgs.piper-tts
    pkgs.ffmpeg
  ];

  env.CMAKE_POLICY_VERSION_MINIMUM = "3.5";

  postInstall = ''
    mkdir -p $out/share/yo-rs
    cp ding.wav $out/share/yo-rs/ding.wav

    mkdir -p $out/share/yo-rs/models/stt
    cp ${smallWhisper} $out/share/yo-rs/models/stt/ggml-small.bin

    mkdir -p $out/share/yo-rs/models/tts
    cp ${piperVoices}/en/en_US/amy/medium/en_US-amy-medium.onnx{,.json} $out/share/yo-rs/models/tts/
    cp ${piperVoices}/sv/sv_SE/lisa/medium/sv_SE-lisa-medium.onnx{,.json} $out/share/yo-rs/models/tts/
  '';

  meta = with lib; {
    description = desc;
    license = licenses.mit;
    maintainers = [ "QuackHack-McBlindy" ];
    mainProgram = "yo-rs";

  };}
