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

  lisa_svSE = pkgs.fetchurl {
    url = "https://huggingface.co/rhasspy/piper-voices/resolve/main/sv/sv_SE/lisa/medium/sv_SE-lisa-medium.onnx";
    sha256 = "sha256-lMrpErMdbpFA0/UWDxgVlRWIYAx6nkPVOboegaEQ0TE=";
  };

  amy_enUS = pkgs.fetchurl {
    url = "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx";
    sha256 = "sha256-s6bke1e4x/vmoM4lGBYaUPWanN2KUINcAssCvdYgbBg=";
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
    pkgs.piper
    pkgs.ffmpeg
  ];

  env.CMAKE_POLICY_VERSION_MINIMUM = "3.5";

  postInstall = ''
    mkdir -p $out/share/yo-rs
    cp ding.wav $out/share/yo-rs/ding.wav

    mkdir -p $out/share/yo-rs/models/stt
    cp ${smallWhisper} $out/share/yo-rs/models/stt/ggml-small.bin
    
    mkdir -p $out/share/yo-rs/models/tts
    cp ${amy_enUS} $out/share/yo-rs/models/tts/en_US-amy-medium.onnx
    cp ${lisa_svSE} $out/share/yo-rs/models/tts/sv_SE-lisa-medium.onnx        
  '';

  meta = with lib; {
    description = desc;
    license = licenses.mit;
    maintainers = [ "QuackHack-McBlindy" ];
    mainProgram = "yo-rs";
    
  };}
