{ 
  config,
  lib,
  ...
} : let

  utils = import ./lib { inherit lib; };
  inherit (utils) countGeneratedPatterns countUnderstoodPhrases;

  # yo.scripts submodule
  scriptType = lib.types.submodule ({ name, config, ... }: {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        internal = true;
        readOnly = true;
        default = name;
        description = "Script name derived from attribute key";
      };
      description = lib.mkOption {
        type = lib.types.str;
        default = "";
      };
      category = lib.mkOption {
        type = lib.types.str;
        default = "";
      };
      filePath = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
      };
      visibleInReadme = lib.mkOption {
        type = lib.types.bool;
        default = config.category != "";
        defaultText = "category != \"\"";
      };
      logLevel = lib.mkOption {
        type = lib.types.enum ["DEBUG" "INFO" "WARNING" "ERROR" "CRITICAL"];
        default = "INFO";
      };
      helpFooter = lib.mkOption {
        type = lib.types.lines;
        default = "";
      };
      autoStart = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      runEvery = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      runAt = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf (lib.types.strMatching "[0-9]{1,2}:[0-9]{2}"));
        default = null;
        description = "Run this script at specific times daily (format: [HH:MM, ...], 24-hour)";
        apply = validateTimes;   # you'll need to define validateTimes here or import it
      };
      code = lib.mkOption {
        type = lib.types.nullOr lib.types.lines;
        default = null;
      };
      binary = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
      };
      aliases = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
      };
      voicePatterns = lib.mkOption {
        type = lib.types.int;
        internal = true;
        readOnly = true;
      };
      voicePhrases = lib.mkOption {
        type = lib.types.int;
        internal = true;
        readOnly = true;
      };
      parameters = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            name = lib.mkOption { type = lib.types.str; };
            description = lib.mkOption { type = lib.types.str; };
            default = lib.mkOption {
              type = lib.types.nullOr (lib.types.oneOf [
                lib.types.str lib.types.int lib.types.bool lib.types.path
              ]);
              default = null;
            };
            optional = lib.mkOption { 
              type = lib.types.bool; 
              default = ./default != null;
              description = "Whether this parameter can be omitted";
            };
            type = lib.mkOption {
              type = lib.types.enum ["string" "int" "path" "bool"];
              default = "string";
            };
            values = lib.mkOption {
              type = lib.types.nullOr (lib.types.listOf lib.types.str);
              default = null;
            };
          };
        });
        default = [];
      };
      voice = lib.mkOption {
        type = lib.types.nullOr (lib.types.submodule {
          options = {
            enabled = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
            priority = lib.mkOption {
              type = lib.types.ints.between 1 5;
              default = 3;
            };
            fuzzy = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  enable = lib.mkOption { type = lib.types.bool; default = true; };
                  threshold = lib.mkOption { type = lib.types.float; default = 0.8; };
                };
              };
              default = {};
            };
            sentences = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
            };
            requires_context = lib.mkOption {
              type = lib.types.attrsOf (lib.types.nullOr (lib.types.oneOf [ lib.types.str (lib.types.listOf lib.types.str) ]));
              default = {};
            };
            excludes_context = lib.mkOption {
              type = lib.types.attrsOf (lib.types.nullOr (lib.types.oneOf [ lib.types.str (lib.types.listOf lib.types.str) ]));
              default = {};
            };
            lists = lib.mkOption {
              type = lib.types.attrsOf (lib.types.submodule {
                options = {
                  wildcard = lib.mkOption { type = lib.types.bool; default = false; };
                  values = lib.mkOption {
                    type = lib.types.listOf (lib.types.submodule {
                      options."in" = lib.mkOption { type = lib.types.str; };
                      options.out = lib.mkOption { type = lib.types.str; };
                    });
                    default = [];
                  };
                  range = lib.mkOption {
                    type = lib.types.nullOr (lib.types.submodule {
                      options = {
                        type = lib.mkOption { type = lib.types.enum ["number"]; default = "number"; };
                        from = lib.mkOption { type = lib.types.number; };
                        to   = lib.mkOption { type = lib.types.number; };
                        multiplier = lib.mkOption { type = lib.types.number; default = 1.0; };
                      };
                    });
                    default = null;
                  };
                };
              });
              default = {};
            };
          };
        });
        default = null;
      };
      voiceReady = lib.mkOption {
        type = lib.types.bool;
        internal = true;
        readOnly = true;
      };
    };

    config = {
      filePath = lib.mkDefault "${(categoryDirMap.${config.category} or "bin/misc")}/${name}.nix";
      voiceReady = lib.mkDefault (
        config.voice != null &&
        config.voice.sentences != [] &&
        config.voice.sentences != null
      );
      voicePatterns = lib.mkDefault (countGeneratedPatterns config);
      voicePhrases = lib.mkDefault (countUnderstoodPhrases config);
    };
  });

  # Helper for category → directory mapping
  categoryDirMap = {
    "🎧 Media Management" = "bin/media";
    "🗣️ Voice" = "bin/voice";
    "🛖 Home Automation" = "bin/home";
    "🧹 Maintenance" = "bin/maintenance";
    "🧩 Miscellaneous" = "bin/misc";
    "🌐 Networking" = "bin/network";
    "🌍 Localization" = "bin/misc";
    "⚡ Productivity" = "bin/productivity";
    "🖥️ System Management" = "bin/system";
    "📁 File Operations" = "bin/files";
    "🔐 Security & Encryption" = "bin/security";
  };

  # Time validation
  isValidTime = timeStr:
    let
      matches = builtins.match "([0-9]{1,2}):([0-9]{2})" timeStr;
    in
      if matches != null then
        let
          hourStr = builtins.elemAt matches 0;
          minuteStr = builtins.elemAt matches 1;
          cleanNumber = str:
            if builtins.substring 0 1 str == "0" && builtins.stringLength str > 1
            then builtins.substring 1 (builtins.stringLength str) str
            else str;
          hour = builtins.fromJSON (cleanNumber hourStr);
          minute = builtins.fromJSON (cleanNumber minuteStr);
        in
          hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59
      else false;

  validateTimes = times:
    if times == null then null
    else
      let
        invalidTimes = lib.filter (time: !isValidTime time) times;
      in
        if invalidTimes != [] then
          throw "🦆 duck say ⮞ fuck ❌ Invalid time format in runAt: ${lib.concatStringsSep ", " invalidTimes}. Use HH:MM (24-hour format)"
        else times;

in {
  options.yo = {  
    pkgs = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = "The final yo scripts package";
    };
    sorryPhrases = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "Buddy, you are speaking Japanese, I dont understand anything."
        "I'm sorry, I did not understand that"
        "Sorry, can you repeat that"
        "I did not quite catch that"
        "Excuse me?!"
      ];
      description = "List of phrases for TTS when no match is found";
    };
    SplitWords = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "also" ];
      description = "Words used for command chaining, i.e. multiple executions";
    };
    language = lib.mkOption {
      type = lib.types.string;
      default = "english";
      description = "Voice commands language for example scripts.";
    };   
    legacy = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use the legacy version of the shell translator in Bash instead of Rust";
    };
    scripts = lib.mkOption {
      type = lib.types.attrsOf scriptType;
      default = {};
      description = "Attribute set of scripts to be made available";
    };
    generatedPatterns = lib.mkOption {
      type = lib.types.int;
      readOnly = true;
      description = "Number of regex patterns generated at build time";
    };
    understandsPhrases = lib.mkOption {
      type = lib.types.int;
      readOnly = true;
      description = "Theoretical number of unique spoken phrases the system can understand";
    };
    
  };}
