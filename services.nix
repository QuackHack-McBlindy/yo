{ 
  self, 
  inputs,
  config,
  lib,
  pkgs,
  ...
} : let
  cfg = config.services.yo-rs;
  inherit (lib) types mkOption mkEnableOption mkIf optional optionals getExe;

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

  selectedVoice = languageToVoice.${cfg.server.language} or "en_US-amy-medium";
  yo-rs-with-models = cfg.package.override { language = cfg.server.language; model = cfg.server.whisper; };
in {

  options.services.yo-rs = {
    enable = mkEnableOption "yo-rs services (server and/or client)";

    package = mkOption {
      type = types.package;
      default = inputs.yo.packages.${pkgs.system}.yo-rs;
      defaultText = lib.literalExpression "inputs.yo.packages.${pkgs.system}.yo-rs";
      description = "The yo-rs package containing both server and client binaries.";
    };

    port = mkOption {
      type = types.port;
      default = 12345;
      description = "Listening port for yo.";
    };
    
    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Wether to open the firewall for the configured port.";
    };    

    server = {
      enable = mkEnableOption "yo-rs server (wake word detection & transcription)";

      host = mkOption {
        type = types.str;
        default = "0.0.0.0:${toString cfg.port}";
        description = "Listening address and port for the server.";
      };

      awakeSound = mkOption {
        type = types.nullOr types.path;
        default = "${yo-rs-with-models}/share/yo-rs/ding.wav";
        description = "Path to a custom WAV file played on wake detection.";
      };

      doneSound = mkOption {
        type = types.nullOr types.path;
        default = "${yo-rs-with-models}/share/yo-rs/done.wav";
        description = "Path to a custom WAV file played on successful command execution.";
      };

      failSound = mkOption {
        type = types.nullOr types.path;
        default = "${yo-rs-with-models}/share/yo-rs/fail.wav";
        description = "Path to a custom WAV file played on successful command execution.";
      };

      wakeWordPath = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to the wake‑word ONNX model.";
      };

      threshold = mkOption {
        type = types.float;
        default = 0.5;
        description = "Detection threshold (0.0–1.0).";
      };

      whisper = mkOption {
        type = types.enum [ "tiny" "base" "small" "medium" "large" ];
        default = "base";
        description = "Speech to text Whisper GGML model size.";
      };
      whisperPath = mkOption {
        type = types.path;
        default = "${yo-rs-with-models}/share/yo-rs/models/stt/ggml-" + cfg.server.whisper + ".bin";
        description = "Path to the Whisper GGML model.";
      };

      shellTranslate = mkOption {
        type = types.bool;
        default = false;
        description = "Translate the transcription to shell command and execute.";
      };

      beamSize = mkOption {
        type = types.int;
        default = 0;
        description = "Beam size for Whisper (0 = greedy).";
      };

      temperature = mkOption {
        type = types.float;
        default = 0.2;
        description = "Whisper sampling temperature.";
      };

      language = mkOption {
        type = types.enum (lib.attrNames languageToVoice);
        default = "en";
        description = "Language code (e.g., `sv` or `en`)";
      };

      threads = mkOption {
        type = types.int;
        default = 4;
        description = "Number of threads for Whisper inference.";
      };

      execCommand = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Command to execute with the transcribed text as the final argument.
          The command is run with the same environment as the server.
          Example: `"yo do"`.
        '';
      };
      
      onnxPath = mkOption {
        type = types.nullOr types.path;
        default = "${yo-rs-with-models}/share/yo-rs/models/tts/${selectedVoice}.onnx";
        description = "Path to the text-to-speech ONNX model.";
      };
      
      ttsSavePath = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Location to save the text-to-speech audio as a wav file (optional).";
      };
      
      ttsSpeed = mkOption {
        type = types.str;
        default = "1.0";
        description = "Length scale used when synthesizing text-to-speech audio. This controls the speech speed.";
      };

      debug = mkOption {
        type = types.bool;
        default = false;
        description = "Enable debug logging (prints probabilities, timings).";
      };

      logFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path to a custom log file path.
          Use absolute path.
          If `null`, default logging file path is `~/yo-rs-server.log`.
        '';
      };
      
      extraPath = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          Additional directories to prepend to the `PATH` environment variable
          of the systemd service. You can use systemd specifiers like `%h`
          (home directory) or `%u` (username).
        '';
      };

      extraArgs = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Extra arguments passed verbatim to the server binary.";
      };
    };

    client = {
      enable = mkEnableOption "yo-rs client (audio streaming & recording)";

      uri = mkOption {
        type = types.str;
        default = "127.0.0.1:12345";
        description = "Server address to connect to.";
      };

      room = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Optional room identifier sent to the server. Used for context/memory for the shell translator.
          Passed to `yo do` as `--room <value>` (only when `shellTranslate` is enabled).
        '';
      };

      awakeSound = mkOption {
        type = types.nullOr types.path;
        default = "${yo-rs-with-models}/share/yo-rs/ding.wav";
        description = "Path to a custom WAV file played on wake detection (client‑side).";
      };

      doneSound = mkOption {
        type = types.nullOr types.path;
        default = "${yo-rs-with-models}/share/yo-rs/done.wav";
        description = "Path to a custom WAV file played on successful command execution (client‑side).";
      };

      failSound = mkOption {
        type = types.nullOr types.path;
        default = "${yo-rs-with-models}/share/yo-rs/fail.wav";
        description = "Path to a custom WAV file played on successful command execution (client‑side).";
      };

      awakeCmd = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Command to execute on the client when wake word is detected.
          The command is run in a background thread; output is logged.
        '';
      };

      doneCmd = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Command to execute on the client after a successful voice command.
          The command is run in a background thread; output is logged.
        '';
      };
      
      failCmd = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Command to execute if a voice command execution has failed.
          The command is run in a background thread; output is logged.
        '';
      };

      silenceThreshold = mkOption {
        type = types.float;
        default = 0.005;
        description = "RMS threshold below which audio is considered silence.";
      };

      silenceTimeout = mkOption {
        type = types.float;
        default = 1.0;
        description = "Seconds of silence before stopping recording.";
      };

      maxDuration = mkOption {
        type = types.float;
        default = 5.0;
        description = "Maximum recording length (fallback).";
      };

      extraArgs = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Extra arguments passed verbatim to the client binary.";
      };
          
      logFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path to a custom log file path.
          Use absolute path.
          If `null`, default logging file path is `~/yo-rs-client.log`.
        '';
      };
      debug = mkOption {
        type = types.bool;
        default = false;
        description = "Print RMS values during recording.";
      };

    };
  };


  config = lib.mkMerge [
    (lib.mkIf (cfg.server.enable || cfg.client.enable) {
      networking.firewall.allowedTCPPorts =
        lib.mkIf cfg.openFirewall [ cfg.port ];


      systemd.user.services = {
        yo-rs-server = mkIf cfg.server.enable {
          description = "yo-rs wake word detection and transcription server";
          after = [ "network.target" ];
          wants = [ "network.target" ];
          wantedBy = [ "default.target" ];

          serviceConfig = {
            Restart = "always";
            RestartSec = "15s";
            Environment = let
              logLevel = if cfg.server.debug then "DEBUG" else "INFO";
              logFile = if cfg.server.logFile != null then cfg.server.logFile else "%h/yo-rs-server.log";
              defaultPathDirs = [
                "/run/wrappers/bin"
                "/run/current-system/sw/bin"
                "/usr/local/bin"
                "/usr/bin"
                "/bin"
              ];
              path = lib.concatStringsSep ":" (cfg.server.extraPath ++ defaultPathDirs);
              envVars = {
                DT_LOG_LEVEL = logLevel;
                DT_LOG_FILE = logFile;
                PATH = path;
              } // lib.optionalAttrs cfg.server.debug { DEBUG = "1"; };
            in lib.mapAttrsToList (name: value: "${name}=${value}") envVars;
          
            ExecStart = lib.escapeShellArgs (
              [ "${yo-rs-with-models}/bin/yo-rs" "--host" cfg.server.host ]
              ++ optionals (cfg.server.wakeWordPath != null)
                  [ "--wake-word" cfg.server.wakeWordPath ]
              ++ [ "--threshold" (toString cfg.server.threshold) ]
              ++ [ "--model" cfg.server.whisperPath ]
              ++ [ "--beam-size" (toString cfg.server.beamSize) ]
              ++ [ "--temperature" (toString cfg.server.temperature) ]
              ++ [ "--threads" (toString cfg.server.threads) ]
              ++ optionals (cfg.server.awakeSound != null) [ "--awake-sound" cfg.server.awakeSound ]
              ++ optionals (cfg.server.doneSound != null) [ "--done-sound" cfg.server.doneSound ]
              ++ optionals (cfg.server.language != null) [ "--language" cfg.server.language ]
              ++ optionals (cfg.server.execCommand != null) [ "--exec-command" cfg.server.execCommand ]
              ++ optionals cfg.server.shellTranslate [ "--translate-to-shell" ]
              ++ optionals (cfg.server.onnxPath != null) [ "--tts-model" cfg.server.onnxPath ]
              ++ optionals cfg.server.debug [ "--debug" ]
              ++ cfg.server.extraArgs
            );
          };
        };


        yo-rs-client = mkIf cfg.client.enable {
          description = "yo-rs client for streaming audio and recording";
          after = [ "network.target" "sound.target" ];
          wants = [ "network.target" "sound.target" ];
          wantedBy = [ "default.target" ];

          serviceConfig = {
            Restart = "always";
            RestartSec = "15s";
            Environment = let
              logLevel = if cfg.client.debug then "DEBUG" else "INFO";
              logFile = if cfg.client.logFile != null then cfg.client.logFile else "%h/yo-rs-client.log";
              defaultPathDirs = [
                "/run/wrappers/bin"
                "/run/current-system/sw/bin"
                "/usr/local/bin"
                "/usr/bin"
                "/bin"
              ];
              path = lib.concatStringsSep ":" (defaultPathDirs);
              envVars = {
                DT_LOG_LEVEL = logLevel;
                DT_LOG_FILE = logFile;
                PATH = path;              
              } // lib.optionalAttrs cfg.client.debug { DEBUG = "1"; };
            in lib.mapAttrsToList (name: value: "${name}=${value}") envVars;

            ExecStart = lib.escapeShellArgs (
              [ "${yo-rs-with-models}/bin/yo-client" "--uri" cfg.client.uri ]
              ++ optionals (cfg.client.awakeSound != null) [ "--awake-sound" cfg.client.awakeSound ]
              ++ optionals (cfg.client.doneSound != null) [ "--done-sound" cfg.client.doneSound ]
              ++ optionals (cfg.client.awakeCmd != null) [ "--awake-cmd" cfg.client.awakeCmd ]
              ++ optionals (cfg.client.doneCmd != null) [ "--done-cmd" cfg.client.doneCmd ]
              ++ [ "--silence-threshold" (toString cfg.client.silenceThreshold) ]
              ++ [ "--silence-timeout" (toString cfg.client.silenceTimeout) ]
              ++ [ "--max-duration" (toString cfg.client.maxDuration) ]
              ++ (if (cfg.client.room != null) then [ "--room" cfg.client.room ]
                  else if (cfg.server.enable && cfg.client.enable) then [ "--room" "local" ]
                  else [])
              ++ optionals cfg.client.debug [ "--debug" ]
              ++ optionals ((cfg.server.enable && cfg.client.enable)) [ "--no-bind" ]
              ++ cfg.client.extraArgs
            );
          };
        };
      };
    })
       
  ];}
