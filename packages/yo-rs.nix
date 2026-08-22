{
  self,
  lib,
  pkgs,
  rustPlatform,
  fetchFromGitHub,
  language ? "en",
  model ? "small",
  ...
} : let
  src = ./yo-rs;
  cargoToml = builtins.fromTOML (builtins.readFile (src + "/Cargo.toml"));
  name      = cargoToml.package.name;
  desc      = cargoToml.package.description;
  version   = cargoToml.package.version;
  
  whisperModel = if model == "tiny" then
      pkgs.fetchurl {
        url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin";
        sha256 = "sha256-vgfgSOHlma1GNByNKhNWRQl6U4IhZ4t6zdGxkZxuGyE=";
      }
    else if model == "base" then
      pkgs.fetchurl {
        url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin";
        sha256 = "sha256-YO1bw90U7qhWST0zQ0m0BXgt3K8AKNS130CINF+6Lv4=";
      }
    else if model == "small" then
      pkgs.fetchurl {
        url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin";
        sha256 = "sha256-G+OpsgY4Z7k35k4ux0gzZKeZF+FX+pjF2UtcH//qmHs=";
      }
    else if model == "medium" then
      pkgs.fetchurl {
        url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin";
        sha256 = "sha256-G+OpsgY4Z7k35k4ux0gzZKeZF+FX+pjF2UtcH//qmHs=";
      }
    else if model == "large" then
      pkgs.fetchurl {
        url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large.bin";
        sha256 = "sha256-G+OpsgY4Z7k35k4ux0gzZKeZF+FX+pjF2UtcH//qmHs=";
      }
    else
      pkgs.fetchurl {
        url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin";
        sha256 = "sha256-G+OpsgY4Z7k35k4ux0gzZKeZF+FX+pjF2UtcH//qmHs=";
      };
  
  voiceToPath = voiceId: let
    parts = lib.splitString "-" voiceId;
    locale = builtins.elemAt parts 0;
    speaker = builtins.elemAt parts 1;
    quality = builtins.elemAt parts 2;
    lang = builtins.head (lib.splitString "_" locale);
  in "${lang}/${locale}/${speaker}/${quality}";

  piperVoiceIds = [
    "ar_JO-kareem-medium"
    "ca_ES-upc_ona-medium"
    "cs_CZ-jirka-medium"
    "cy_GB-bu_tts-medium"
    "da_DK-talesyntese-medium"
    "de_DE-thorsten-medium"
    "el_GR-rapunzelina-low"
    "en_GB-alan-medium"
    "en_US-amy-medium"
    "es_AR-daniela-high"
    "es_ES-davefx-medium"
    "es_MX-ald-medium"
    "fa_IR-amir-medium"
    "fi_FI-harri-medium"
    "fr_FR-mls-medium"
    "hi_IN-pratham-medium"
    "hu_HU-anna-medium"
    "is_IS-bui-medium"
    "it_IT-paola-medium"
    "ka_GE-natia-medium"
    "kk_KZ-issai-high"
    "lb_LU-marylux-medium"
    "lv_LV-aivars-medium"
    "ml_IN-arjun-medium"
    "ne_NP-chitwan-medium"
    "nl_BE-nathalie-medium"
    "nl_NL-mls-medium"
    "no_NO-talesyntese-medium"
    "pl_PL-darkman-medium"
    "pt_BR-cadu-medium"
    "pt_PT-tugao-medium"
    "ro_RO-mihai-medium"
    "ru_RU-denis-medium"
    "sk_SK-lili-medium"
    "sl_SI-artur-medium"
    "sr_RS-serbski_institut-medium"
    "sv_SE-lisa-medium"
    "sw_CD-lanfrica-medium"
    "tr_TR-dfki-medium"
    "uk_UA-ukrainian_tts-medium"
    "vi_VN-vais1000-medium"
    "zh_CN-huayan-medium"
  ];

  languageToVoice = {
    "ar" = "ar_JO-kareem-medium";
    "ca" = "ca_ES-upc_ona-medium";
    "cs" = "cs_CZ-jirka-medium";
    "cy" = "cy_GB-bu_tts-medium";
    "da" = "da_DK-talesyntese-medium";
    "de" = "de_DE-thorsten-medium";
    "el" = "el_GR-rapunzelina-low";
    "en" = "en_US-amy-medium";
    "es" = "es_ES-davefx-medium";
    "fa" = "fa_IR-amir-medium";
    "fi" = "fi_FI-harri-medium";
    "fr" = "fr_FR-mls-medium";
    "hi" = "hi_IN-pratham-medium";
    "hu" = "hu_HU-anna-medium";
    "is" = "is_IS-bui-medium";
    "it" = "it_IT-paola-medium";
    "ka" = "ka_GE-natia-medium";
    "kk" = "kk_KZ-issai-high";
    "lb" = "lb_LU-marylux-medium";
    "lv" = "lv_LV-aivars-medium";
    "ml" = "ml_IN-arjun-medium";
    "ne" = "ne_NP-chitwan-medium";
    "nl" = "nl_NL-mls-medium";
    "no" = "no_NO-talesyntese-medium";
    "pl" = "pl_PL-darkman-medium";
    "pt" = "pt_PT-tugao-medium";
    "ro" = "ro_RO-mihai-medium";
    "ru" = "ru_RU-denis-medium";
    "sk" = "sk_SK-lili-medium";
    "sl" = "sl_SI-artur-medium";
    "sr" = "sr_RS-serbski_institut-medium";
    "sv" = "sv_SE-lisa-medium";
    "sw" = "sw_CD-lanfrica-medium";
    "tr" = "tr_TR-dfki-medium";
    "uk" = "uk_UA-ukrainian_tts-medium";
    "vi" = "vi_VN-vais1000-medium";
    "zh" = "zh_CN-huayan-medium";
  };

  selectedVoice = languageToVoice.${language} or "en_US-amy-medium";

  piperVoices = pkgs.fetchgit {
    url            = "https://huggingface.co/rhasspy/piper-voices";
    rev            = "375a0fe641dea077c2a47b4e9a056d6da521eed3";  # tag v1.0.0
    fetchLFS       = true;
    sparseCheckout = map voiceToPath piperVoiceIds;
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
    cp done.wav $out/share/yo-rs/done.wav
    cp fail.wav $out/share/yo-rs/fail.wav

    mkdir -p $out/share/yo-rs/models/stt
    cp ${whisperModel} $out/share/yo-rs/models/stt/ggml-${model}.bin

    mkdir -p $out/share/yo-rs/models/tts
    cp ${piperVoices}/${voiceToPath selectedVoice}/${selectedVoice}.onnx{,.json} $out/share/yo-rs/models/tts/
  '';

  meta = with lib; {
    description = desc;
    license = licenses.mit;
    maintainers = [ "QuackHack-McBlindy" ];
    mainProgram = "yo-rs";

  };}
