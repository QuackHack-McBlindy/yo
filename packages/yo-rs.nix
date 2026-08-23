{
  self,
  lib,
  pkgs,
  rustPlatform,
  language ? "english",
  model ? "small",
  ...
}:
let
  src = ./yo-rs;
  cargoToml = builtins.fromTOML (builtins.readFile (src + "/Cargo.toml"));
  name = cargoToml.package.name;
  desc = cargoToml.package.description;
  version = cargoToml.package.version;

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
        sha256 = "sha256-bBTVre5fhjlAN7Tk6LWfFnO2zuEOPPCxG72+55wVYgg=";
      }
    else if model == "large" then
      pkgs.fetchurl {
        url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large.bin";
        sha256 = lib.fakeSha256;
      }
    else
      pkgs.fetchurl {
        url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin";
        sha256 = "sha256-G+OpsgY4Z7k35k4ux0gzZKeZF+FX+pjF2UtcH//qmHs=";
      };

  voiceToPath = voiceId:
    let
      parts = lib.splitString "-" voiceId;
      locale = builtins.elemAt parts 0;
      speaker = builtins.elemAt parts 1;
      quality = builtins.elemAt parts 2;
      lang = builtins.head (lib.splitString "_" locale);
    in "${lang}/${locale}/${speaker}/${quality}";

  languageToVoice = {
    "arabic" = "ar_JO-kareem-medium";
    "catalan" = "ca_ES-upc_ona-medium";
    "czech" = "cs_CZ-jirka-medium";
    "welsh" = "cy_GB-bu_tts-medium";
    "danish" = "da_DK-talesyntese-medium";
    "german" = "de_DE-thorsten-medium";
    "greek" = "el_GR-rapunzelina-low";
    "english" = "en_US-amy-medium";
    "spanish" = "es_ES-davefx-medium";
    "persian" = "fa_IR-amir-medium";
    "finnish" = "fi_FI-harri-medium";
    "french" = "fr_FR-mls-medium";
    "hindi" = "hi_IN-pratham-medium";
    "hungarian" = "hu_HU-anna-medium";
    "icelandic" = "is_IS-bui-medium";
    "italian" = "it_IT-paola-medium";
    "georgian" = "ka_GE-natia-medium";
    "kazakh" = "kk_KZ-issai-high";
    "luxembourgish" = "lb_LU-marylux-medium";
    "latvian" = "lv_LV-aivars-medium";
    "malayalam" = "ml_IN-arjun-medium";
    "nepali" = "ne_NP-chitwan-medium";
    "dutch" = "nl_NL-mls-medium";
    "norwegian" = "no_NO-talesyntese-medium";
    "polish" = "pl_PL-darkman-medium";
    "portuguese" = "pt_PT-tugao-medium";
    "romanian" = "ro_RO-mihai-medium";
    "russian" = "ru_RU-denis-medium";
    "slovak" = "sk_SK-lili-medium";
    "slovenian" = "sl_SI-artur-medium";
    "serbian" = "sr_RS-serbski_institut-medium";
    "swedish" = "sv_SE-lisa-medium";
    "swahili" = "sw_CD-lanfrica-medium";
    "turkish" = "tr_TR-dfki-medium";
    "ukrainian" = "uk_UA-ukrainian_tts-medium";
    "vietnamese" = "vi_VN-vais1000-medium";
    "chinese" = "zh_CN-huayan-medium";
  };

  selectedVoice = languageToVoice.${language} or "en_US-amy-medium";
  selectedVoicePath = voiceToPath selectedVoice;

  fileHashes = {
    "ar_JO-kareem-medium.onnx" = "sha256-npXKsHtnnaYDu6F8Tex6sxETIFcZZO6VwDeWA8CGSR4=";
    "ar_JO-kareem-medium.onnx.json" = "sha256-6m2bnZB229tr9cmMahQe8VSVnSNZcJs3hVcnlk59bE0=";
    "ca_ES-upc_ona-medium.onnx" = "sha256-/bZS24wRpEdVJzRs8yQcsGTRujk883Dz8uwJqHLRGP0=";
    "ca_ES-upc_ona-medium.onnx.json" = "sha256-f3asycBvTtqeau8pl7dXgtl4Vaq0jUtAHrlWpuZV7dw=";
    "cs_CZ-jirka-medium.onnx" = "sha256-y9XJAKysyOjL7NZDR6u43jnACp0xBL7Qb+6S5PMZ78g=";
    "cs_CZ-jirka-medium.onnx.json" = "sha256-+zixeZtzVICCJ8Bl76l7H/orDN5ZUFurtWo201r5xjc=";
    "cy_GB-bu_tts-medium.onnx" = "sha256-QRtRPNNZdbQkjLqo4+Wp2aO422t3aAuCHje3XZhL4yk=";
    "cy_GB-bu_tts-medium.onnx.json" = "sha256-wxjjuHALjrTtXesnaHKwNty2fiiCzI37LVnUpkAYsoU=";
    "da_DK-talesyntese-medium.onnx" = "sha256-uSce/SX3uElLvSjUjdZ1yMEZ2qKE8+5IgAiTX1FfEkE=";
    "da_DK-talesyntese-medium.onnx.json" = "sha256-if4TvSUUBswAiFcNED6nrDWCMhHYRm+vkTJoq4UG9Bs=";
    "de_DE-thorsten-medium.onnx" = "sha256-fmR2LY5RGLtXjy7qYgfho1qODDBZUBC2ZvmD/Ie7eBk=";
    "de_DE-thorsten-medium.onnx.json" = "sha256-l0re55BTOtsnOhrIj0kCfSobjw8s9JBZVKR5HnkmToU=";
    "el_GR-rapunzelina-low.onnx" = "sha256-7rszWUbF2Gh0P/Nfu2a28A5DG1ubLhjK9H0/YJor8uE=";
    "el_GR-rapunzelina-low.onnx.json" = "sha256-JMzDHBMG30Nk/YW1ausJq6jBhaH999sTZ6ctSv/keOQ=";
    "en_GB-alan-medium.onnx" = "sha256-CjCWaJMiBedigB8e/Cc2zUsBIDKWIq32K+CeVjOdMzA=";
    "en_GB-alan-medium.onnx.json" = "sha256-wPDRJOWJXADnwDs13MgofzGaaZijZbGC3rXI51LujB4=";
    "en_US-amy-medium.onnx" = "sha256-s6bke1e4x/vmoM4lGBYaUPWanN2KUINcAssCvdYgbBg=";
    "en_US-amy-medium.onnx.json" = "sha256-laI+tNQpCdON9zu5rH9F9Zfb/N4tG/lSb96vVGaXfXc=";
    "es_AR-daniela-high.onnx" = "sha256-fOsfwNqzSUGMW1SmOa6e5ZUhLXyepCIiDYQZFj1cyYU=";
    "es_AR-daniela-high.onnx.json" = "sha256-rtv2lkfh11TGLs+OA2bKXxavPnaOPGtTKa9utr3jhSs=";
    "es_ES-davefx-medium.onnx" = "sha256-ZliwOxpsMW7kwmWpiWq8E5M1PC2eG8p9ZsLEQuIiqRc=";
    "es_ES-davefx-medium.onnx.json" = "sha256-Dg3ah8cy9vOHcf8nSmOA2SUvMn3Kd6opY9X7357FSEI=";
    "es_MX-ald-medium.onnx" = "sha256-AZs4Ayk8k+NKIG3S5To4iSCaUU54b9cUT3twGWxXm2M=";
    "es_MX-ald-medium.onnx.json" = "sha256-76tzbmLlMh3V0GPRtG5jxZzmVUGYFjVbgdAlwajWsDw=";
    "fa_IR-amir-medium.onnx" = "sha256-+4FTgNlp6jcrCyGw3hRCH1j+SBBH4VPmloXQebbhqdE=";
    "fa_IR-amir-medium.onnx.json" = "sha256-dfkYo78PV6kXmr5yWvUp8qXHnWyJniqErsdsaF1d+5o=";
    "fi_FI-harri-medium.onnx" = "sha256-pEFn+qNMrtlA5PytE5/MNZIiZrJZO86+d3AXdMD7I4k=";
    "fi_FI-harri-medium.onnx.json" = "sha256-P5yfdvdK3x++cnnkHuoX1mEHV+Re/9aAi76mvnS4kW0=";
    "fr_FR-mls-medium.onnx" = "sha256-DtIj94RmkX8rrgXukAls5pqx/eslH1VZDQ50ItI04WI=";
    "fr_FR-mls-medium.onnx.json" = "sha256-JSsLCm5MxJSeI+zLlW+cd5mGwy+TTy9+IZHl/cLtymE=";
    "hi_IN-pratham-medium.onnx" = "sha256-FplksIcWZ/Z5NBbUs16XNXpouhrQHfhYDCgEiYnudpM=";
    "hi_IN-pratham-medium.onnx.json" = "sha256-to7dLNeVDdQ2MUATt80S6WmeWj9v5a9a+UKUz2qnuf0=";
    "hu_HU-anna-medium.onnx" = "sha256-lowMOmbLZngRJCzIhlO/+SRzlfx6BRf77vfYwIza5io=";
    "hu_HU-anna-medium.onnx.json" = "sha256-zPln2NuAGMnY/9sO3IgU/8trdSc7sNhDNzFyQPcQKDo=";
    "is_IS-bui-medium.onnx" = "sha256-OmRbLShQ5AmPAfN2XOzpMYNsA3QeAaXMUU0J0503wFw=";
    "is_IS-bui-medium.onnx.json" = "sha256-PK5yhXL7s5dxPQR/Ipkke7drYmOdnf3NZbJsV4uKukU=";
    "it_IT-paola-medium.onnx" = "sha256-b8kYtaDqYTc4KDPd36Vnv/vmpQYMAgQ8hxku5ZwEIQw=";
    "it_IT-paola-medium.onnx.json" = "sha256-rqGcCn/OKfvDWbk/EOeQKFRAHkyVri6jKK5RaxXSls8=";
    "ka_GE-natia-medium.onnx" = "sha256-BL2s8Yj6JEmYhfkQmzlf6FYaBews2Q1VRT7Fvu169GA=";
    "ka_GE-natia-medium.onnx.json" = "sha256-kGQ20PjeefzWVXZHCxDH6pN8dQ+ba22vxyonzr1KiPY=";
    "kk_KZ-issai-high.onnx" = "sha256-Te52fIk+hTXaghRH0SywMONWnhElTBQDCh2l2LIiLBY=";
    "kk_KZ-issai-high.onnx.json" = "sha256-6xRayHErh77anwJm6VuYytdqzOidRibNixQII06YQvA=";
    "lb_LU-marylux-medium.onnx" = "sha256-QUfsrN2YkylR0PlWVVVC3jWNPM/3CNSZbjBcPOKHCXo=";
    "lb_LU-marylux-medium.onnx.json" = "sha256-5cXexUM9M/9XPnb6Vn6A3PY20F3l3MgXsnOWPwcz10I=";
    "lv_LV-aivars-medium.onnx" = "sha256-nYVaR8IuK5R5W+ng656MTALOJR3IlGHe3pTeIP8IvY4=";
    "lv_LV-aivars-medium.onnx.json" = "sha256-CK4sKXvoqgTxXz+Xt//q4BRrMLC9j3uuvNxGvCwvM9w=";
    "ml_IN-arjun-medium.onnx" = "sha256-6IETBRaodDBpcqB9zyYuaQAUBDDFZYExEhdEqA7z8Rs=";
    "ml_IN-arjun-medium.onnx.json" = "sha256-KATwcJVOVlReiBAbcDMdREQCGHiZ0Kb/A+XUS+6BMkU=";
    "ne_NP-chitwan-medium.onnx" = "sha256-97prCSdoj5JxfpPKUrwG9Xg86O3HZdX4U2Ws7x1Bgiw=";
    "ne_NP-chitwan-medium.onnx.json" = "sha256-GNUjsDsgFCLRTiiSzHUKgSCNLkUVipxqfk4GpQCTDe4=";
    "nl_BE-nathalie-medium.onnx" = "sha256-Sc9IAjhh+f1C4TqGMvBo/uZ9HOJEpu448pWVr78Ka+Q=";
    "nl_BE-nathalie-medium.onnx.json" = "sha256-RwSvJzYCLpEKPzJnJIDVUw3TnaXCvMB58xX2BBZv8N4=";
    "nl_NL-mls-medium.onnx" = "sha256-iDEuD79QW4fK8jc9lME4SJLoaxvy7kgs9l3Iuhecx9M=";
    "nl_NL-mls-medium.onnx.json" = "sha256-bdshXTjxOSq5Na1FRBuCraHurgRSotaEntcepPLgqmM=";
    "no_NO-talesyntese-medium.onnx" = "sha256-t2OuvgLnLEYoxAdMS4tEjwX/5SO5db/NWOLF1TEnDBM=";
    "no_NO-talesyntese-medium.onnx.json" = "sha256-sOsEkfyL+YQ9K+rIrPh3O2z1knQxZAazb/V5rooZCdU=";
    "pl_PL-darkman-medium.onnx" = "sha256-21BUOKU2To4uAkLEMkEwqHPtZg376NlonO9Cj/sbZF8=";
    "pl_PL-darkman-medium.onnx.json" = "sha256-cPmZ8R+orRPT73eQQe6TyfOL5avbrN+tQkSXEv6RyBs=";
    "pt_BR-cadu-medium.onnx" = "sha256-dl8ICabqkDXUptDQCNv4h25ost0yApMSZy+o9AW9tTU=";
    "pt_BR-cadu-medium.onnx.json" = "sha256-X+A6o9SQGIBVSQWxIHVxPNVSWYyKNQRVoexz+LTmvhk=";
    "sl_SI-artur-medium.onnx" = "sha256-kiLtk+9CVSStS+Cwgzaa+OqNsYRVV2pgFrFUGS9O04w=";
    "sl_SI-artur-medium.onnx.json" = "sha256-dBKDQw8for5cYXF8bx/nlae59TdJGSc0DdEvkPOzzAQ=";
    "sr_RS-serbski_institut-medium.onnx" = "sha256-1wA4kM9ZbmU/ZgpP2X/Rf1fx7OttlyerrZzXbS/aDYA=";
    "sr_RS-serbski_institut-medium.onnx.json" = "sha256-Oa1lMbRqxinAvtEKqSBd0kMeLas4CLhTWAhxHbh8K8A=";
    "sv_SE-lisa-medium.onnx" = "sha256-lMrpErMdbpFA0/UWDxgVlRWIYAx6nkPVOboegaEQ0TE=";
    "sv_SE-lisa-medium.onnx.json" = "sha256-UeSLZddCeu6ejnNrNw/0/m4+ReR6VuXYgZZHtwdv+wo=";
    "sw_CD-lanfrica-medium.onnx" = "sha256-Hxle0Syl54dRFGGOXwAgevNkYC4hynjIptPXZ0+SWfo=";
    "sw_CD-lanfrica-medium.onnx.json" = "sha256-W9b2rWWaqPH4n0FOI6PfhPx1PrnAZukf6Gcp2irUwfw=";
    "tr_TR-dfki-medium.onnx" = "sha256-KERxf1JKuWXT/obmBWLLtgHT5FaDbvzCGWzDoUESqPs=";
    "tr_TR-dfki-medium.onnx.json" = "sha256-E+vXgQ8bYbUCdYPPMTGgojO26oHDjyIA68T/QcPMoDk=";
    "uk_UA-ukrainian_tts-medium.onnx" = "sha256-eSBBmsX2/YtkUFIPJLUu1aMZy1PdAY+81xyeB5y6yE8=";
    "uk_UA-ukrainian_tts-medium.onnx.json" = "sha256-TpbnKRfKm5Ttx31sz+4Dpz9FC6L8HKk8LlYrwBTlqlU=";
    "vi_VN-vais1000-medium.onnx" = "sha256-7HyJ4shfTR7cJLYSDBiq8b2mFPBrURVn65x8DeFeLas=";
    "vi_VN-vais1000-medium.onnx.json" = "sha256-+vudoTVO1Ld8Ma8ijtQftBzYJcFM/6EFRUsl5q51HuA=";
    "zh_CN-huayan-medium.onnx" = "sha256-mSmRe/jKuyb9Uo6kTTpmmcEehzF6FHZTEkIL4jC+Dz0=";
    "zh_CN-huayan-medium.onnx.json" = "sha256-1SHcRVBKjMyZ4yWCKzWUbdcBhAv7B+PbsxpAkp7WqCs=";

    # missing?
    "pt_PT-tugao-medium.onnx" = lib.fakeSha256;
    "pt_PT-tugao-medium.onnx.json" = lib.fakeSha256;
    "ro_RO-mihai-medium.onnx" = lib.fakeSha256;
    "ro_RO-mihai-medium.onnx.json" = lib.fakeSha256;
    "ru_RU-denis-medium.onnx" = lib.fakeSha256;
    "ru_RU-denis-medium.onnx.json" = lib.fakeSha256;
    "sk_SK-lili-medium.onnx" = lib.fakeSha256;
    "sk_SK-lili-medium.onnx.json" = lib.fakeSha256;
  };

  voiceOnnx = pkgs.fetchurl {
    url = "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/${selectedVoicePath}/${selectedVoice}.onnx";
    sha256 = fileHashes."${selectedVoice}.onnx";
  };

  voiceOnnxJson = pkgs.fetchurl {
    url = "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/${selectedVoicePath}/${selectedVoice}.onnx.json";
    sha256 = fileHashes."${selectedVoice}.onnx.json";
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
    cp ${voiceOnnx} $out/share/yo-rs/models/tts/${selectedVoice}.onnx
    cp ${voiceOnnxJson} $out/share/yo-rs/models/tts/${selectedVoice}.onnx.json
  '';

  meta = with lib; {
    description = desc;
    license = licenses.mit;
    maintainers = [ "QuackHack-McBlindy" ];
    mainProgram = "yo-rs";
  };
}
