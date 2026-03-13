{ 
  self,
  config,
  lib,
  pkgs,
  ...
} : with lib;
let

  utils = import ./lib { inherit lib; };
  inherit (utils)
    cartesianProductOfLists
    expandOptionalWords
    expandListInputVariants
    expandToRegex
    makeEntityResolver
    escapeMD
    makeTimerName
    countGeneratedPatterns
    countUnderstoodPhrases
    countTotalGeneratedPatterns
    countTotalUnderstoodPhrases
    ;

  cfg = config.yo;

  # Data preparation
  scriptsWithVoice = filterAttrs (_: script:
    script.voice != null && (script.voice.enabled or true)
  ) cfg.scripts;

  generatedIntents = mapAttrs (name: script: {
    priority = script.voice.priority or 3;
    data = [{
      inherit (script.voice) sentences lists;
    }];
  }) scriptsWithVoice;

  scriptsWithFuzzy = filterAttrs (_: script:
    script.voice != null &&
    (script.voice.enabled or true) &&
    (script.voice.fuzzy.enable or true)
  ) cfg.scripts;

  fuzzyFlatIndex = flatten (mapAttrsToList (scriptName: intent:
    concatMap (data:
      concatMap (sentence:
        map (expanded: {
          script = scriptName;
          sentence = expanded;
          signature = let
            words = splitString " " (toLower expanded);
            sorted = sort (a: b: a < b) words;
          in concatStringsSep "|" sorted;
        }) (expandOptionalWords sentence)
      ) data.sentences
    ) intent.data
  ) (mapAttrs (name: script: {
    priority = script.voice.priority or 3;
    data = [{
      inherit (script.voice) sentences lists;
    }];
  }) scriptsWithFuzzy));

  # files to be written to store
  splitWordsFile = pkgs.writeText "split-words.json" (builtins.toJSON cfg.SplitWords);
  sorryPhrasesFile = pkgs.writeText "sorry-phrases.json" (builtins.toJSON cfg.sorryPhrases);

  intentDataFile =
    if cfg.legacy then
      # Bash version:
      pkgs.writeText "intent-entity-map.json"
        (builtins.toJSON (
          lib.mapAttrs (_scriptName: intentList:
            let
              allData = lib.flatten (map (d: d.lists or {}) intentList.data);
              sentences = lib.concatMap (d: d.sentences or []) intentList.data;      
              expandedSentences = lib.unique (lib.concatMap expandOptionalWords sentences);
              substitutions = lib.flatten (map (lists:
                lib.flatten (lib.mapAttrsToList (_listName: listData:
                  if listData ? values then
                    lib.flatten (map (item:
                      let
                        rawIn = item."in";
                        value = item.out;
                        cleaned = lib.removePrefix "[" (lib.removeSuffix "]" rawIn);
                        variants = lib.splitString "|" cleaned;     
                    in map (v: let     
                      cleanV = lib.replaceStrings ["  "] [" "] (lib.strings.trim v);
                    in {   
                      pattern = if builtins.match ".* .*" cleanV != null
                                then cleanV
                                else "(${cleanV})";
                      value = value;
                    }) variants
                  ) listData.values)
                else []
              ) lists)
            ) allData);
          in {
            inherit substitutions;
            sentences = expandedSentences;
          }
        ) generatedIntents
      ))    
    else
      # Rust version:
      pkgs.writeText "intent-entity-map.json"        
        (builtins.toJSON (
          mapAttrs (_scriptName: intentList:
            let
              allData = flatten (map (d: d.lists or {}) intentList.data);
              sentences = concatMap (d: d.sentences or []) intentList.data;
              expandedSentences = unique (concatMap expandOptionalWords sentences);
              substitutions = flatten (map (lists:
                flatten (mapAttrsToList (_listName: listData:
                  if listData ? values then
                    flatten (map (item:
                      let
                        rawIn = item."in";
                        value = item.out;
                        cleaned = removePrefix "[" (removeSuffix "]" rawIn);
                        variants = splitString "|" cleaned;
                      in map (v: let
                        cleanV = replaceStrings ["  "] [" "] (strings.trim v);
                      in {
                        pattern = if builtins.match ".* .*" cleanV != null
                                  then cleanV
                                  else "(${cleanV})";
                        inherit value;
                      }) variants
                    ) listData.values)
                  else []
                ) lists)
              ) allData);
              lists = foldl (acc: d: acc // (d.lists or {})) {} intentList.data;
            in {
              inherit substitutions sentences lists;
            }
          ) generatedIntents
        ));

  fuzzyIndex = mapAttrsToList (scriptName: intent:
    concatMap (data:
      concatMap (sentence:
        map (expanded: {
          script = scriptName;
          sentence = expanded;
          signature = let
            words = splitString " " (toLower expanded);
            sorted = sort (a: b: hasPrefix a b) words;
          in concatStringsSep "|" sorted;
        }) (expandOptionalWords sentence)
      ) data.sentences
    ) intent.data
  ) generatedIntents;

  fuzzyIndexFile = pkgs.writeText "fuzzy-index.json" (builtins.toJSON fuzzyIndex);
  fuzzyIndexFlatFile = pkgs.writeText "fuzzy-rust-index.json" (builtins.toJSON fuzzyFlatIndex);

  # Pattern matcher generators
  makePatternMatcher = scriptName: let
    dataList = generatedIntents.${scriptName}.data;
  in ''
    match_${scriptName}() {
      local input="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
      dt_debug "Trying to match for script: ${scriptName}" >&2
      dt_debug "Input: $input" >&2
      ${concatMapStrings (data:
        concatMapStrings (sentence:
          concatMapStrings (sentenceText: let
            parts = splitString "{" sentenceText;
            firstPart = escapeRegex (elemAt parts 0);
            restParts = drop 1 parts;
            regexParts = imap (i: part:
              let
                split = splitString "}" part;
                param = elemAt split 0;
                after = concatStrings (tail split);
                isWildcard = data.lists.${param}.wildcard or false;
                regexGroup = if isWildcard then "(.*)" else "\\b([^ ]+)\\b";
              in {
                regex = regexGroup + escapeRegex after;
                param = param;
              }
            ) restParts;
            fullRegex = "^${strings.trim (firstPart + concatStrings (map (v: v.regex) regexParts))}$";
            paramList = map (v: v.param) regexParts;
          in ''
            local regex='${fullRegex}'
            dt_debug "REGEX: $regex"
            if [[ "$input" =~ $regex ]]; then
              ${concatImapStrings (i: paramName: ''
                param_value="''${BASH_REMATCH[${toString (i+1)}]}"
                if [[ -n "''${param_value:-}" && -v substitutions["$param_value"] ]]; then
                  subbed="''${substitutions["$param_value"]}"
                  if [[ -n "$subbed" ]]; then
                    param_value="$subbed"
                  fi
                fi
                ${optionalString (
                  data.lists ? ${paramName} && !(data.lists.${paramName}.wildcard or false)
                ) ''
                  if [[ -v substitutions["$param_value"] ]]; then
                    param_value="''${substitutions["$param_value"]}"
                  fi
                  case "$param_value" in
                    ${makeEntityResolver data paramName}
                    *) ;;
                  esac
                ''}
                declare -g "_param_${paramName}"="$param_value"
                declare -A params=()
                params["${paramName}"]="$param_value"
                matched_params+=("$paramName")
              '') paramList}
              cmd_args=()
              ${concatImapStrings (i: paramName: ''
                value="''${BASH_REMATCH[${toString i}]}"
                cmd_args+=(--${paramName} "$value")
              '') paramList}
              dt_debug "REMATCH 1: ''${BASH_REMATCH[1]}"
              dt_debug "REMATCH 2: ''${BASH_REMATCH[2]}"
              dt_debug "REMATCH 3: ''${BASH_REMATCH[3]}"
              dt_debug "MATCHED SCRIPT: ${scriptName}"
              dt_debug "ARGS: ''${cmd_args[@]}"
              return 0
            fi
          '') (expandOptionalWords sentence)
        ) data.sentences
      ) dataList}
      return 1
    }
  '';

  makeFuzzyPatternMatcher = scriptName: let
    dataList = generatedIntents.${scriptName}.data;
  in ''
    match_fuzzy_${scriptName}() {
      local input="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
      local matched_sentence="$2"
      declare -A params=()
      local input_words=($input)
      local sentence_words=($matched_sentence)
      for i in ''${!sentence_words[@]}; do
        local word="''${sentence_words[$i]}"
        if [[ "$word" == \{*\} ]]; then
          local param_name="''${word:1:-1}"
          params["$param_name"]="''${input_words[$i]}"
        fi
      done
      for param in "''${!params[@]}"; do
        local value="''${params[$param]}"
        if [[ -v substitutions["$value"] ]]; then
          params["$param"]="''${substitutions["$value"]}"
        fi
      done
      cmd_args=()
      for param in "''${!params[@]}"; do
        cmd_args+=(--"$param" "''${params[$param]}")
      done
      return 0
    }
  '';

  matchers = mapAttrsToList (scriptName: data:
    let
      matcherCode = makePatternMatcher scriptName;
    in {
      name = scriptName;
      value = pkgs.writeText "${scriptName}-matcher" matcherCode;
    }
  ) generatedIntents;

  matcherSourceScript = pkgs.writeText "matcher-loader.sh" (
    concatMapStringsSep "\n" (m: "source ${m.value}") matchers
  );

  matcherDir = pkgs.linkFarm "yo-matchers" (
    map (m: { name = "${m.name}.sh"; path = m.value; }) matchers
  );

  # Help file with voice sentences 
  voiceSentencesHelpFile = pkgs.writeText "voice-sentences-help.md" (
    let
      scriptsWithVoice2 = filterAttrs (_: script:
        script.voice != null && script.voice.sentences != [] && (script.voice.enabled or true)
      ) cfg.scripts;

      replaceParamsWithValues = sentence: voiceData:
        let
          processToken = token:
            if hasPrefix "{" token && hasSuffix "}" token then
              let
                paramName = removePrefix "{" (removeSuffix "}" token);
                listData = voiceData.lists.${paramName} or null;
              in
                if listData != null then
                  if listData.wildcard or false then
                    "ANYTHING"
                  else
                    let
                      values = map (v: v."in") listData.values;
                      expandedValues = concatMap expandListInputVariants values;
                      examples = take 3 (unique expandedValues);
                    in
                      if examples == [] then "ANYTHING"
                      else "(" + concatStringsSep "|" examples +
                           (if length examples < length expandedValues then "|...)" else ")")
                else
                  "ANYTHING"
            else
              token;
          tokens = splitString " " sentence;
          processedTokens = map processToken tokens;
        in concatStringsSep " " processedTokens;

      groupedScripts = groupBy (script: script.category or "🧩 Miscellaneous")
        (attrValues scriptsWithVoice2);

      categorySections = mapAttrsToList (category: scripts:
        let
          scriptLines = map (script:
            let
              sentenceLines = concatMapStrings (sentence:
                let processedSentence = replaceParamsWithValues sentence script.voice;
                in "    - \"${escapeMD processedSentence}\"\n"
              ) script.voice.sentences;
            in
              "  **${escapeMD script.name}**:\n${sentenceLines}"
          ) (sort (a: b: a.name < b.name) scripts);
        in
          "# ${category}\n\n${concatStringsSep "\n" scriptLines}"
      ) groupedScripts;

      totalScripts = length (attrNames cfg.scripts);
      voiceScripts = length (attrNames scriptsWithVoice2);
      totalPatterns = cfg.generatedPatterns;
      totalPhrases = cfg.understandsPhrases;

      stats = ''
  # ----────----──⋆⋅☆☆☆⋅⋆─────----─ #
  # Total:
  - **Scripts with voice enabled**: ${toString voiceScripts} / ${toString totalScripts}
  - **Generated patterns**: ${toString totalPatterns}
  - **Understandable phrases**: ${toString totalPhrases}
      '';
    in
      "# 🦆 Voice Commands\n\n${concatStringsSep "\n\n" categorySections}\n\n${stats}"
  );

  # Help table for yo --help
  terminalScriptsTable = let
    groupedScripts = groupBy (script: script.category) (attrValues cfg.scripts);
    visibleScripts = filterAttrs (_: script: script.visibleInReadme) cfg.scripts;
    groupedVisible = groupBy (script: script.category) (attrValues visibleScripts);
    sortedCategories = sort (a: b:
      if a == "🖥️ System Management" then true
      else if b == "🖥️ System Management" then false
      else a < b
    ) (attrNames groupedVisible);

    rows = concatMap (category:
      let
        scripts = sort (a: b: a.name < b.name) groupedVisible.${category};
      in
        [ "| **${escapeMD category}** | | |" ] ++
        map (script:
          let
            aliasList = if script.aliases != [] then
              concatStringsSep ", " (map escapeMD script.aliases)
            else "";
            paramHint = concatStringsSep " " (map (param:
              if param.optional || param.default != null
              then "[--${param.name}]"
              else "--${param.name}"
            ) script.parameters);
            syntax = "\\`yo ${escapeMD script.name} ${paramHint}\\`";
          in
            "| ${syntax} | ${aliasList} | ${escapeMD script.description} |"
        ) scripts
    ) sortedCategories;
  in concatStringsSep "\n" rows;

  # helper for script generation
  sanitizeVarName = name: replaceStrings ["-"] ["_"] name;

  yoEnvGenVar = script: let
    withDefaults = filter (p: p.default != null) script.parameters;
    exports = map (p:
      let
        defaultValue =
          if p.type == "string" then escapeShellArg (toString p.default)
          else if p.type == "int" then toString p.default
          else if p.type == "bool" then (if p.default then "true" else "false")
          else if p.type == "path" then escapeShellArg (toString p.default)
          else escapeShellArg (toString p.default);
      in
        "export ${sanitizeVarName p.name}=${defaultValue}"
    ) withDefaults;
  in concatStringsSep "\n" exports;

  sysHosts = attrNames self.nixosConfigurations;
  sysHostsComma = concatStringsSep "," sysHosts;


  # The yo package
  yoScriptsPackage = pkgs.symlinkJoin {
    name = "yo-scripts";
    paths = mapAttrsToList (name: script:
      let
        voiceSentencesHelp = if script.voice != null && script.voice.sentences != [] then
          let
            patterns = countGeneratedPatterns script;
            phrases = countUnderstoodPhrases script;

            replaceParamsWithValues = sentence: voiceData:
              let
                processToken = token:
                  if lib.hasPrefix "{" token && lib.hasSuffix "}" token then
                    let
                      paramName = lib.removePrefix "{" (lib.removeSuffix "}" token);
                      listData = voiceData.lists.${paramName} or null;
                    in
                      if listData != null then
                        if listData.wildcard or false then
                          "ANYTHING"
                        else
                          let
                            values = map (v: v."in") listData.values;

                            expandedValues = lib.concatMap expandListInputVariants values;

                            examples = lib.take 3 (lib.unique expandedValues);
                          in
                            if examples == [] then "ANYTHING"
                            else "(" + lib.concatStringsSep "|" examples + 
                                 (if lib.length examples < lib.length expandedValues then "|...)" else ")")
                      else
                        "ANYTHING"
                  else
                    token;
                
                tokens = lib.splitString " " sentence;
                processedTokens = map processToken tokens;
              in
                lib.concatStringsSep " " processedTokens;
            
            processedSentences = map (sentence: 
              replaceParamsWithValues sentence script.voice
            ) script.voice.sentences;
            
            sentencesMarkdown = lib.concatMapStrings (sentence: 
              "- \"${escapeMD sentence}\"\n"
            ) processedSentences;
          in
            "## Voice Commands\n\nPatterns: ${toString patterns}  \nPhrases: ${toString phrases}  \n\n${sentencesMarkdown}"
        else "";
       
        param_usage = lib.concatMapStringsSep " " (param:
          if param.optional
          then "[--${param.name}]"
          else "--${param.name}"
        ) (lib.filter (p: !builtins.elem p.name ["!" "?"]) script.parameters);
        
        # Where the magic happens (construction + validation) 
        scriptContent = ''
          #!${pkgs.runtimeShell}
#          set -euo pipefail
          set -o noglob
          ${yoEnvGenVar script} # Enviorment injection
          export LC_NUMERIC=C
          start=$(date +%s.%N)
#          trap 'end=$(date +%s.%N); elapsed=$(echo "$end - $start" | bc); printf "[🦆⏱] Total time: %.3f seconds\n" "$elapsed"' EXIT

          export DT_LOG_PATH="$HOME/.config/duckTrace/"
          mkdir -p "$DT_LOG_PATH"   
          export DT_LOG_FILE="${name}.log"
          touch "$DT_LOG_PATH/$DT_LOG_FILE"
          export DT_LOG_LEVEL="${script.logLevel}"
          DT_MONITOR_HOSTS="${sysHostsComma}";
          DT_MONITOR_PORT="9999";
      
          # PHASE 1: preprocess special flags
          VERBOSE=0
          DRY_RUN=false
          FILTERED_ARGS=()
          
          # Loop through arguments
          while [[ $# -gt 0 ]]; do
            case "$1" in
              \?) ((VERBOSE++)); shift ;;
              '!') DRY_RUN=true; shift ;;
              *) FILTERED_ARGS+=("$1"); shift ;;
            esac
          done  
          VERBOSE=$VERBOSE
          export VERBOSE DRY_RUN
          
          # reset arguments without special flags
          set -- "''${FILTERED_ARGS[@]}"

          # PHASE 2: regular parameter parsing
          declare -A PARAMS=()
          POSITIONAL=()
          VERBOSE=$VERBOSE
          DRY_RUN=$DRY_RUN
          # if ? flag used - sets scripts logLevel to DEBUG
          if [ "$VERBOSE" -ge 1 ]; then
            DT_LOG_LEVEL="DEBUG"
          fi
          
          # Parse parameters
          while [[ $# -gt 0 ]]; do
            case "$1" in
              --help|-h)
                width=$(tput cols 2>/dev/null || echo 100)
                help_footer=$(${script.helpFooter}) # Generate help footer

                usage_suffix=""
                if [[ -n "${toString (script.parameters != [])}" ]]; then
                  usage_suffix=" [OPTIONS]"
                fi
                
                cat <<EOF | ${pkgs.glow}/bin/glow --width "$width" - # Render as markdown 
# 🚀🦆 yo ${escapeMD script.name}
${script.description}
**Usage:** \`yo ${escapeMD script.name}''${usage_suffix}\`
${lib.optionalString (script.parameters != []) ''
## Parameters
${lib.concatStringsSep "\n\n" (map (param: ''
**\`--${param.name}\`**  
${param.description}  
${lib.optionalString param.optional "*(optional)*"} ${lib.optionalString (param.default != null) (let
  defaultText = 
    if param.type == "bool" then 
      (if param.default then "true" else "false")
    else 
      (toString param.default);
in "*(default: ${defaultText})*")}
${lib.optionalString (param.values != null && param.type == "string") 
  "*(allowed: ${lib.concatStringsSep ", " param.values})*"}
'') script.parameters)}
''}
${voiceSentencesHelp}

$help_footer
EOF
                exit 0
                ;;
              --*) # Parse named parameters (--param)
                param_name=''${1##--}
                # Check param existence
                if [[ " ${concatMapStringsSep " " (p: 
                      if p.type == "bool" then p.name else ""
                    ) script.parameters} " =~ " $param_name " ]]; then
                  
                  # Boolean flag - presence means true, but also allow explicit true/false
                  if [[ $# -gt 1 && ( "$2" == "true" || "$2" == "false" ) ]]; then
                    PARAMS["$param_name"]="$2"
                    shift 2
                  else
                    PARAMS["$param_name"]="true"
                    shift 1
                  fi
                else
                  # regular param expects value
                  if [[ " ${concatMapStringsSep " " (p: p.name) script.parameters} " =~ " $param_name " ]]; then
                    PARAMS["$param_name"]="$2"
                    shift 2
                  else
                    echo -e "\033[1;31m 🦆 duck say ⮞ fuck ❌ $1\033[0m Unknown parameter: $1"
                    exit 1
                  fi
                fi
                ;;
              *) # Assume positional argument
                POSITIONAL+=("$1")
                shift
                ;;
            esac
          done

            # PHASE 3: assign parameters
            ${concatStringsSep "\n" (lib.imap0 (idx: param: ''
              if (( ${toString idx} < ''${#POSITIONAL[@]} )); then
                ${sanitizeVarName param.name}="''${POSITIONAL[${toString idx}]}"
              fi
            '') script.parameters)}
            
          # Assign named parameters
          ${concatStringsSep "\n" (map (param: ''
            if [[ -n "''${PARAMS[${param.name}]:-}" ]]; then
              ${sanitizeVarName param.name}="''${PARAMS[${param.name}]}"
            fi
          '') script.parameters)}

          # Count number of parameters
          ${optionalString (script.parameters != []) ''
            if [ ''${#POSITIONAL[@]} -gt ${toString (length script.parameters)} ]; then
              echo -e "\033[1;31m 🦆 duck say ⮞ fuck ❌ Too many arguments (max ${toString (length script.parameters)})\033[0m" >&2
              exit 1
            fi
          ''}

          # Parameter type validation
          ${concatStringsSep "\n" (map (param: 
            optionalString (param.type != "string") ''
              if [ -n "''${${sanitizeVarName param.name}:-}" ]; then
                case "${param.type}" in
                  int)
                    if ! [[ "''${${sanitizeVarName param.name}}" =~ ^[0-9]+$ ]]; then
                      echo -e "\033[1;31m 🦆 duck say ⮞ fuck ❌ ${name} --${param.name} must be integer\033[0m" >&2
                      exit 1
                    fi
                    ;;
                  path)
                    if ! [ -e "''${${sanitizeVarName param.name}}" ]; then
                      echo -e "\033[1;31m 🦆 duck say ⮞ fuck ❌ ${name} Path not found: ''${${sanitizeVarName param.name}}\033[0m" >&2
                      exit 1
                    fi
                    ;;
                  bool)
                    if ! [[ "''${${sanitizeVarName param.name}}" =~ ^(true|false)$ ]]; then
                      echo -e "\033[1;31m 🦆 duck say ⮞ fuck ❌ ${name} Parameter ${param.name} must be true or false\033[0m" >&2
                      exit 1
                    fi
                    ;;
                esac
              fi
            ''
          ) script.parameters)}


          # Values validation - explicit allowed list
          ${concatStringsSep "\n" (map (param: 
            optionalString (param.values != null && param.type == "string") ''
              if [ -n "''${${sanitizeVarName param.name}:-}" ]; then
                allowed_values=(${lib.concatMapStringsSep " " (v: "'${lib.escapeShellArg v}'") param.values})
                value_found=false
                for allowed in "''${allowed_values[@]}"; do
                  if [[ "''${${sanitizeVarName param.name}}" == "$allowed" ]]; then
                    value_found=true
                    break
                  fi
                done
                if [[ "$value_found" == "false" ]]; then
                  echo -e "\033[1;31m 🦆 duck say ⮞ fuck ❌ ${name} --${param.name} must be one of: ${lib.concatStringsSep ", " param.values}\033[0m" >&2
                  exit 1
                fi
              fi
            ''
          ) script.parameters)}


          # Boolean defaults - false if not provided
          ${concatStringsSep "\n" (map (param: 
            optionalString (param.type == "bool" && param.default != null) ''
              if [[ -z "''${${sanitizeVarName param.name}:-}" ]]; then
                ${param.name}=${if param.default then "true" else "false"}
              fi
            '') script.parameters)}


          ${concatStringsSep "\n" (map (param: 
            optionalString (param.default != null) ''
              if [[ -z "''${${sanitizeVarName param.name}:-}" ]]; then
                ${sanitizeVarName param.name}=${
                  if param.type == "string" then 
                    "'${lib.escapeShellArg (toString param.default)}'" 
                  else if param.type == "int" then
                    "${toString param.default}"
                  else if param.type == "bool" then
                    (if param.default then "true" else "false")
                  else if param.type == "path" then
                    "'${lib.escapeShellArg (toString param.default)}'"
                  else
                    "'${lib.escapeShellArg (toString param.default)}'"
                }
              fi
            '') script.parameters)}
            
          # Check required parameters - if missing - error out 
          ${concatStringsSep "\n" (map (param: ''
            ${optionalString (!param.optional && param.default == null) ''
              if [[ -z "''${${sanitizeVarName param.name}:-}" ]]; then
                echo -e "\033[1;31m 🦆 duck say ⮞ fuck ❌ ${name} Missing required parameter: ${param.name}\033[0m" >&2
                exit 1
              fi
            ''}
          '') script.parameters)}


          # Execution

          # Binary with args 
          ${if script.binary != null then ''
            args=()
            ${concatStringsSep "\n" (map (param: ''
              if [[ -n "''${${sanitizeVarName param.name}:-}" ]]; then
                args+=(--${param.name} "''${${sanitizeVarName param.name}}")
              fi
            '') script.parameters)}
            ${lib.escapeShellArg script.binary} "''${args[@]}"
          '' else '' # Else exec code 
            ${script.code}
          ''}          
        '';
        # Generate entrypoint
        mainScript = pkgs.writeShellScriptBin "yo-${script.name}" scriptContent;
      in  
        pkgs.runCommand "yo-script-${script.name}" {} ''
          mkdir -p $out/bin
          ln -s ${mainScript}/bin/yo-${script.name} $out/bin/yo-${script.name} 
          ${concatMapStrings (alias: ''
            ln -s ${mainScript}/bin/yo-${script.name} $out/bin/yo-${alias}
          '') script.aliases}
        ''
    ) cfg.scripts;
  };


in {
  imports = [
    ./options.nix
    ./assertions.nix
    ./services.nix
  ];

  config = mkMerge [
    {  
      yo.pkgs = yoScriptsPackage;
  
      # Global counters
      yo.generatedPatterns = countTotalGeneratedPatterns cfg.scripts;
      yo.understandsPhrases = countTotalUnderstoodPhrases cfg.scripts;
  
  
      # Environment variables pointing to generated files
      environment.variables = {
        YO_SPLIT_WORDS = splitWordsFile;
        YO_SORRY_PHRASES = sorryPhrasesFile;
        YO_INTENT_DATA = intentDataFile;
        "ỲO_FUZZY_INDEX" = fuzzyIndexFile;
        MATCHER_DIR = matcherDir;
        MATCHER_SOURCE = matcherSourceScript;
      };

      # Generate configuration files in /etc/yo  
      environment.etc = {
        "yo/split-words.json".source = splitWordsFile;
        "yo/sorry-phrases.json".source = sorryPhrasesFile;
        "yo/intent-data.json".source = intentDataFile;
        "yo/fuzzy-index.json".source = fuzzyIndexFile;
        "yo/matchers" = { source = matcherDir; };
        "yo/matcher-loader.sh".source = matcherSourceScript;
      };
  
      environment.systemPackages = [
        config.yo.pkgs
        pkgs.glow
        (pkgs.writeShellScriptBin "yo" ''
          #!${pkgs.runtimeShell}
          set -o noglob
          script_dir="${yoScriptsPackage}/bin"
          show_help() {
            width=130
            cat <<EOF | ${pkgs.glow}/bin/glow --width $width -
          ### ──────⋆⋅☆☆☆⋅⋆────── ##
          **Usage:** \`yo <command> [arguments]\`
          ### ──────⋆⋅☆☆☆⋅⋆────── ##
          ### 🦆✨ Available Commands
          Parameters inside brackets are [optional]
          | Command Syntax               | Aliases    | Description |
          |------------------------------|------------|-------------|
          ${terminalScriptsTable}
          ### ──────⋆⋅☆☆☆⋅⋆────── ##
          ### 🦆❓ Detailed Help
          For specific command help: \`yo <command> --help\`
          \`yo do --help\` will list all defined voice intents.
          EOF
            exit 0
          }
          if [[ $# -eq 0 ]]; then
            show_help
            exit 1
          fi
          case "$1" in
            -h|--help) show_help; exit 0 ;;
            *) command="$1"; shift ;;
          esac
          script_path="$script_dir/yo-$command"
          if [[ -x "$script_path" ]]; then
            exec "$script_path" "$@"
          else
            echo -e "\033[1;31m 🦆 duck say ⮞ fuck ❌ $1\033[0m Error: Unknown command '$command'" >&2
            show_help
            exit 1
          fi
        '')
        yoScriptsPackage
      ];
  
      # systemd services and timers
      systemd.user.services = mkMerge [
        (mapAttrs' (name: script:
          nameValuePair "yo-${name}" (mkIf script.autoStart {
            enable = true;
            wantedBy = ["multi-user.target"];
            after = ["sound.target" "network.target" "pulseaudio.socket" "sops-nix.service"];
            serviceConfig = {
              Environment = "PATH=${
                concatStringsSep ":" [
                  "/run/wrappers/bin"
                  "/run/current-system/sw/bin"
                  "/usr/local/bin"
                  "/usr/bin"
                  "/bin"
                ]
              }";
              ExecStart = let
                args = concatMapStringsSep " " (param:
                  "--${param.name} ${escapeShellArg param.default}"
                ) (filter (p: p.default != null) script.parameters);
              in "${yoScriptsPackage}/bin/yo-${name} ${args}";
              RestartSec = 45;
              Restart = "on-failure";
            };
          })
        ) cfg.scripts)
  
        (mapAttrs' (name: script:
          nameValuePair "yo-${name}-periodic" (mkIf (script.runEvery != null) {
            enable = true;
            description = "Periodic execution of yo.${name}";
            serviceConfig = {
              Type = "oneshot";
              Environment = "PATH=${
                concatStringsSep ":" [
                  "/run/wrappers/bin"
                  "/run/current-system/sw/bin"
                  "/usr/local/bin"
                  "/usr/bin"
                  "/bin"
                ]
              }";
              ExecStart = let
                args = concatMapStringsSep " " (param:
                  "--${param.name} ${escapeShellArg param.default}"
                ) (filter (p: p.default != null) script.parameters);
              in "${yoScriptsPackage}/bin/yo-${name} ${args}";
            };
          })
        ) cfg.scripts)
  
        (mapAttrs' (name: script:
          nameValuePair "yo-${name}-scheduled" (mkIf (script.runAt != null) {
            enable = true;
            description = let
              timesFormatted = if script.runAt != null then
                concatStringsSep ", " script.runAt
              else "";
              baseDesc = if script.description != "" then
                "${script.description} (scheduled at ${timesFormatted})"
              else
                "Scheduled execution of yo.${name} at ${timesFormatted}";
            in baseDesc;
            serviceConfig = {
              Type = "oneshot";
              Environment = "PATH=${
                concatStringsSep ":" [
                  "/run/wrappers/bin"
                  "/run/current-system/sw/bin"
                  "/usr/local/bin"
                  "/usr/bin"
                  "/bin"
                ]
              }";
              ExecStart = let
                args = concatMapStringsSep " " (param:
                  "--${param.name} ${escapeShellArg param.default}"
                ) (filter (p: p.default != null) script.parameters);
              in "${yoScriptsPackage}/bin/yo-${name} ${args}";
            };
          })
        ) cfg.scripts)
      ];
  
      systemd.user.timers = mkMerge [
        (mapAttrs' (name: script:
          nameValuePair "yo-${name}-periodic" (mkIf (script.runEvery != null) {
            enable = true;
            wantedBy = ["timers.target"];
            timerConfig = {
              OnCalendar = "*-*-* *:0/${script.runEvery}";
              Unit = "yo-${name}-periodic.service";
              Persistent = true;
            };
          })
        ) cfg.scripts)
  
        (foldl' recursiveUpdate {} (mapAttrsToList (name: script:
          if script.runAt != null then
            listToAttrs (map (timeStr:
              nameValuePair (makeTimerName name timeStr) {
                enable = true;
                wantedBy = ["timers.target"];
                timerConfig = {
                  OnCalendar = "*-*-* ${timeStr}:00";
                  Unit = "yo-${name}-scheduled.service";
                  Persistent = true;
                };
              }
            ) script.runAt)
          else {}
        ) cfg.scripts))
      ];
    }
    
      
    (mkIf (!cfg.legacy) {      
      yo.scripts.do = {
        description = "do is a Natural Language to Shell script translator that generates dynamic regex patterns at build time for defined yo.script sentences. It runs exact and fuzzy pattern matching at runtime with automatic parameter resolution and seamless shell script execution";
        binary = "/run/current-system/sw/bin/yo-do";
        category = "🗣️ Voice";
        logLevel = "INFO";
        parameters = [
          { name = "input"; description = "Text to translate"; optional = true; } 
          { name = "fuzzy"; type = "int"; description = "Minimum procentage for considering fuzzy matching sucessful. (1-100)"; default = 60; }
          { name = "room"; type = "string"; description = "Optional client area (used for context)"; optional = true; }
        ];
      };
  
      yo.scripts.tests = {
        description = "Extensive automated sentence testing for the yo do"; 
        binary = "/run/current-system/sw/bin/yo-tests";      
        category = "🗣️ Voice";
        parameters = [
          { name = "input"; description = "Text to test as a single  sentence test"; optional = true; }
          { name = "stats"; type = "bool"; description = "Flag to display voice commands information like generated regex patterns, generated phrases and ratio"; optional = true; }    
          { name = "fuzzy"; type = "int"; description = "Minimum procentage for considering fuzzy matching sucessful. (1-100)"; default = 30; }
        ];
      };  
  
  
      yo.scripts.say = {
        description = "Text to speech with built in language detection and automatic model downloading";
        binary = "/run/current-system/sw/bin/yo-say";
        category = "🗣️ Voice";
        logLevel = "WARNING";
        parameters = [
          { name = "text"; description = "Input text that should be spoken"; optional = false; }      
          { name = "model"; description = "File name of the model"; default = config.services.yo-rs.server.textToSpeechModelPath; }
          { name = "blocking"; type = "bool"; description = "Wait for TTS playback to finish"; default = false; }
          { name = "path"; description = "Specify a file path where wav will be saved to disk"; optional = true; }
        ];      
      };
    })
    
    (mkIf cfg.legacy (import ./legacy.nix {
      inherit config lib pkgs;
      inherit generatedIntents scriptsWithVoice fuzzyFlatIndex
              splitWordsFile sorryPhrasesFile intentDataFile
              fuzzyIndexFile matcherDir matcherSourceScript
              yoScriptsPackage;
    }))    
  

  ];}
