{ 
  config,
  lib,
  ...
} : let
  cfg = config.yo;
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
        description = "A short, human-readable description of what the script does. Shown in `yo --help` and the generated command table.";
        example = "Set a timer for a specified duration.";   
      };
      category = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Category used for grouping scripts in `yo --help`.";
        example = "🛖 Home Automation";
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
        description = "Logging verbosity for this script when executed via `yo`.";
        example = "DEBUG";
      };
      helpFooter = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Additional markdown appended to the script's `--help` output. Useful for examples/notes/stats.";
        example = "Examples:\n  yo timer --minutes 5\n  yo timer --hours 1 --minutes 30";
      };
      autoStart = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to start this script automatically at boot. Requires all mandatory parameters to have defaults.";
        example = true;
      };
      runEvery = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      runAt = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf (lib.types.strMatching "[0-9]{1,2}:[0-9]{2}"));
        default = null;
        description = "Run this script at specific times daily (format: [HH:MM, ...], 24-hour)";
        apply = validateTimes;
        example = [ "07:00" "18:00" ];
      };
      code = lib.mkOption {
        type = lib.types.nullOr lib.types.lines;
        default = null;
        description = "
          Inline shell code to execute when the script is invoked. Mutually exclusive with `binary`.
          The script parameters are exposed as variables.  
        ";
        example = ''  
          echo "Hello, $name!"
        '';
      };
      binary = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to an executable binary to run instead of inline code. Mutually exclusive with `code`.";
        example = "/path/to/my-tool/or/script";
      };
      aliases = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Alternative names for invoking this script from the command line (e.g., `yo <alias>`).";
        example = [ "tim" "stopwatch" ];
      };
      voicePatterns = lib.mkOption {
        type = lib.types.int;
        internal = true;
        readOnly = true;
        description = "Number of distinct sentence patterns generated from the voice definition.";
      };
      voicePhrases = lib.mkOption {
        type = lib.types.int;
        internal = true;
        readOnly = true;
        description = "Theoretical number of unique spoken phrases that can be matched, after entity expansion.";
      };
      voiceRatio = lib.mkOption {
        type = lib.types.float;
        internal = true;
        readOnly = true;
        default = 0.0;
        description = "Ratio of `voicePhrases` to `voicePatterns`. Indicates combinatorial expansion; higher values mean more phrases per pattern.";
      };    
      parameters = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            name = lib.mkOption { 
              type = lib.types.str;
              description = "Name of the parameter as passed to the script (example, if parameter name is `seconds` it can be used in the script using `$seconds`).";
            };
            description = lib.mkOption { 
              type = lib.types.str;
              description = "Human-readable explanation of the parameter, shown in `--help`.";
            };
            default = lib.mkOption {
              type = lib.types.nullOr (lib.types.oneOf [
                lib.types.str lib.types.int lib.types.bool lib.types.path
              ]);
              default = null;
              description = "Default value if the parameter is not provided.";
            };
            optional = lib.mkOption { 
              type = lib.types.bool; 
              default = ./default != null;
              description = "Whether this parameter can be omitted. Automatically set to `true` if a default is defined.";
            };
            type = lib.mkOption {
              type = lib.types.enum ["string" "int" "path" "bool"];
              default = "string";
              description = "Data type of the parameter value. Used for validation and conversion.";
            };
            values = lib.mkOption {
              type = lib.types.nullOr (lib.types.listOf lib.types.str);
              default = null;
              description = "If set, restricts the allowed values for this parameter to the given list.";
              example = [ "on" "off" "toggle" ];
            };
          };
        });
        default = [];
        description = "List of parameters that the script accepts. Each parameter becomes a command-line option (e.g., `--name`).";
        example = [
          { name = "minutes"; type = "int"; description = "Minutes to set"; default = 5; }
          { name = "sound"; type = "path"; description = "Sound file to play"; optional = true; }
        ];
      };
      voice = lib.mkOption {
        type = lib.types.nullOr (lib.types.submodule {
          options = {
            enabled = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether voice commands are enabled for this script.";
            };
            speak = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "If true, the script’s stdout is sent to text-to-speech and played on connected clients.";
            };            
            priority = lib.mkOption {
              type = lib.types.ints.between 1 5;
              default = 3;
              description = "Match priority (1 = highest, 5 = lowest). Exact matches are always resolved first regardless of priority.";
              example = 1;
            };
            
            fuzzy = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  enable = lib.mkOption {
                    type = lib.types.bool;
                    default = cfg.fuzzy.enable;
                    description = "Enable fuzzy matching for this script. Overrides the global setting if set.";
                  };
                  threshold = lib.mkOption {
                    type = lib.types.float;
                    default = cfg.fuzzy.threshold;
                    description = "Fuzzy similarity threshold (0.0–1.0) required for a match. Lower values allow more permissive matching.";
                  };
                };
              };
              default = {};
              description = "Fuzzy matching configuration specific to this script.";
            };
            sentences = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
              description = "List of sentence patterns that this script can handle. Supports alternatives `(a|b)`, optionals `[word]`, and parameter references `{name}`.";
              example = [
                "set a timer for {minutes} minutes"
                "start a {hours} hour timer"
              ];
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
                  wildcard = lib.mkOption { 
                    type = lib.types.bool; 
                    default = false;
                    description = "If true, this list acts as a wildcard: any input is accepted and passed through unchanged.";
                  };
                  values = lib.mkOption {
                    type = lib.types.listOf (lib.types.submodule {
                      options."in" = lib.mkOption { 
                        type = lib.types.str;
                        description = "Input pattern. Can contain alternatives separated by `|`.";
                      };
                      options.out = lib.mkOption { 
                        type = lib.types.str;
                        description = "Output value assigned to the parameter when the input pattern matches.";
                      };
                    });
                    default = [];
                    description = "List of input-output mappings for entity recognition.";
                    example = [
                      { "in" = "living room|livingroom"; out = "livingroom"; }
                      { "in" = "bedroom"; out = "bedroom"; }
                    ];
                  };
                  range = lib.mkOption {
                    type = lib.types.nullOr (lib.types.submodule {
                      options = {
                        type = lib.mkOption { 
                          type = lib.types.enum ["number"];
                          default = "number";
                          description = "Type of range. Currently only `number` is supported.";
                        };
                        from = lib.mkOption { 
                          type = lib.types.number;
                          description = "Starting value of the range (inclusive).";
                        };
                        to   = lib.mkOption { 
                          type = lib.types.number;
                          description = "Ending value of the range (inclusive).";
                        };
                        multiplier = lib.mkOption { 
                          type = lib.types.number;
                          default = 1.0;
                          description = "Multiplier applied to each generated number (useful for e.g., seconds to minutes conversion).";
                        };
                      };
                    });
                    default = null;
                    description = "Define a numeric range instead of an explicit list of values.";
                    example = { from = 1; to = 60; multiplier = 1; };
                  };
                };
              });
              default = {};
              description = "Entity lists used to expand `{parameter}` placeholders in voice sentences.";
              example = {
                room.values = [
                  { "in" = "living room|livingroom"; out = "livingroom"; }
                  { "in" = "bedroom"; out = "bedroom"; }
                ];
                number.range = { from = 1; to = 10; };
              };  
            };
          };
        });
        default = null;
        description = "Voice command configuration for this script.";
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
      voicePhrases  = lib.mkDefault (countUnderstoodPhrases config);
      voiceRatio = if config.voicePatterns == 0 then 0.0
                     else (builtins.toFloat config.voicePhrases) / (builtins.toFloat config.voicePatterns);
    };
  });

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
    splitWords = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "also" ];
      description = "Words that trigger command chaining. When encountered in a sentence, the input is split and each part is executed separately.";
      example = [ "and" "also" ];
    };
    legacy = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use the legacy Bash-based shell translator instead of the Rust interpreter. The Bash version has fewer dependencies but lower performance. Not recommended if user is generating many patterns.";
    };

    fuzzy = lib.mkOption {
      type = lib.types.submodule {
        options = {
          enable = lib.mkOption { 
            type = lib.types.bool;
            default = true;
            description = "Enable fuzzy matching globally. Can be overridden per script.";
          };
          threshold = lib.mkOption {
            type = lib.types.float;
            default = 0.8;
            description = "Global fuzzy similarity threshold (0.0–1.0). Scripts may override this.";
          };
          conflict = lib.mkOption {
            type = lib.types.submodule {
              options = {
                detection = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = "Enable deep build-time sentence conflict detection for fuzzy near-duplicates. May increase build time significantly.";
                };
                threshold = lib.mkOption {
                  type = lib.types.int;
                  default = 80;
                  description = "Jaccard similarity percentage (0–100) above which two sentences are considered conflicting.";
                };
              };
            };
            default = {};
            description = "Build-time sentence conflict detection settings for fuzzy matching.";
          };
        };
      };
      default = {};
      description = "Global fuzzy matching configuration.";
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
