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
  scripts = cfg.scripts; 
  scriptNames = builtins.attrNames scripts;
  scriptNamesWithIntents = builtins.filter (scriptName:
    let
      intent = generatedIntents.${scriptName};
      hasSentences = builtins.any (data: data ? sentences && data.sentences != []) intent.data;
    in
      builtins.hasAttr scriptName generatedIntents && hasSentences
  ) (builtins.attrNames scriptsWithVoice);


  scriptsWithVoice = lib.filterAttrs (_: script: 
    script.voice != null && (script.voice.enabled or true)
  ) config.yo.scripts;
  
  generatedIntents = lib.mapAttrs (name: script: {
    priority = script.voice.priority or 3;
    data = [{
      inherit (script.voice) sentences lists;
    }];
  }) scriptsWithVoice;

  fuzzyFlatIndex = lib.flatten (lib.mapAttrsToList (scriptName: intent:
    lib.concatMap (data:
      lib.concatMap (sentence:
        map (expanded: {
          script = scriptName;
          sentence = expanded;
          signature = let
            words = lib.splitString " " (lib.toLower expanded);
            sorted = lib.sort (a: b: a < b) words;
          in builtins.concatStringsSep "|" sorted;
        }) (expandOptionalWords sentence)
      ) data.sentences
    ) intent.data
  ) (lib.mapAttrs (name: script: {
    priority = script.voice.priority or 3;
    data = [{
      inherit (script.voice) sentences lists;
    }];
  }) scriptsWithFuzzy));

 
  # 🦆 says ⮞ where da magic dynamic regex iz at 
  makePatternMatcher = scriptName: let
    dataList = generatedIntents.${scriptName}.data;    
  in '' # 🦆 says ⮞ diz iz how i pick da script u want 
    match_${scriptName}() { # 🦆 says ⮞ shushin' da caps – lowercase life 4 cleaner dyn regex zen ✨
      local input="$(echo "$1" | tr '[:upper:]' '[:lower:]')" 
      # 🦆 says ⮞ always show input in debug mode
      # 🦆 says ⮞ watch the fancy stuff live in action  
      dt_debug "Trying to match for script: ${scriptName}" >&2
      dt_debug "Input: $input" >&2
      # 🦆 says ⮞ duck presentin' - da madnezz 
      ${lib.concatMapStrings (data:
        lib.concatMapStrings (sentence:
          lib.concatMapStrings (sentenceText: let
            # 🦆 says ⮞ now sentenceText is one of the expanded variants!
            parts = lib.splitString "{" sentenceText; # 🦆 says ⮞ diggin' out da goodies from curly nests! Gimme dem {param} nuggets! 
            firstPart = lib.escapeRegex (lib.elemAt parts 0); # 🦆 says ⮞ gotta escape them weird chars 
            restParts = lib.drop 1 parts;  # 🦆 says ⮞ now we in the variable zone quack?  
            # 🦆 says ⮞ process each part to build regex and params
            regexParts = lib.imap (i: part:
              let
                split = lib.splitString "}" part; # 🦆 says ⮞ yeah yeah curly close that syntax shell
                param = lib.elemAt split 0; # 🦆 says ⮞ name of the param in da curly – ex: {user}
                after = lib.concatStrings (lib.tail split); # 🦆 says ⮞ anything after the param in this chunk
                # 🦆 says ⮞ Wildcard mode! anything goes - duck catches ALL the worms! (.*)
                isWildcard = data.lists.${param}.wildcard or false;
                regexGroup = if isWildcard then "(.*)" else "\\b([^ ]+)\\b"; # 82%
                # regexGroup = if isWildcard then "(.*)" else "([^ ]+)";
                # 🦆 says ⮞ ^ da regex that gon match actual input text
              in {
                regex = regexGroup + lib.escapeRegex after;
                param = param;
              }
            ) restParts;

            fullRegex = let
              clean = lib.strings.trim (firstPart + lib.concatStrings (map (v: v.regex) regexParts));
            in "^${clean}$"; # 🦆 says ⮞ mash all regex bits 2gether
            paramList = map (v: v.param) regexParts; # 🦆 says ⮞ the squad of parameters 
          in ''
            local regex='^${fullRegex}$'
            dt_debug "REGEX: $regex"
            if [[ "$input" =~ $regex ]]; then  # 🦆 says ⮞ DANG DANG – regex match engaged 
              ${lib.concatImapStrings (i: paramName: ''
                # 🦆 says ⮞ extract match group #i+1 – param value, come here plz 
                param_value="''${BASH_REMATCH[${toString (i+1)}]}"
                # 🦆 says ⮞ if param got synonym, apply the duckfilter 
                if [[ -n "''${param_value:-}" && -v substitutions["$param_value"] ]]; then
                  subbed="''${substitutions["$param_value"]}"
                  if [[ -n "$subbed" ]]; then
                    param_value="$subbed"
                  fi
                fi           
                ${lib.optionalString (
                  data.lists ? ${paramName} && !(data.lists.${paramName}.wildcard or false)
                ) ''
                  # 🦆 says ⮞ apply substitutions before case matchin'
                  if [[ -v substitutions["$param_value"] ]]; then
                    param_value="''${substitutions["$param_value"]}"
                  fi
                  case "$param_value" in
                    ${makeEntityResolver data paramName}
                    *) ;;
                  esac
                ''} # 🦆 says ⮞ declare global param – duck want it everywhere! (for bash access)
                declare -g "_param_${paramName}"="$param_value"            
                declare -A params=()
                params["${paramName}"]="$param_value"
                matched_params+=("$paramName")
              '') paramList} # 🦆 says ⮞ set dat param as a GLOBAL VAR yo! every duck gotta know 
              # 🦆 says ⮞ build cmd args: --param valu
              cmd_args=()
              ${lib.concatImapStrings (i: paramName: ''
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
  ''; # 🦆 says ⮞ dat was fun! let'z do it again some time

  # 🦆 says ⮞ quack and scan, match bagan
  makeFuzzyPatternMatcher = scriptName: let
    dataList = generatedIntents.${scriptName}.data;
  in '' # 🦆 says ⮞ fuzz in code, waddle mode
    match_fuzzy_${scriptName}() {
      local input="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
      local matched_sentence="$2"
      # 🦆 says ⮞ skip regex! dat shit iz crazy - use aligned wordz yo
      declare -A params=()
      local input_words=($input)
      local sentence_words=($matched_sentence)     
      # 🦆 says ⮞ extract params by aligning words cool huh
      for i in ''${!sentence_words[@]}; do
        local word="''${sentence_words[$i]}"
        if [[ "$word" == \{*\} ]]; then
          local param_name="''${word:1:-1}"
          params["$param_name"]="''${input_words[$i]}"
        fi
      done
      # 🦆 says ⮞ apply subs to params yo
      for param in "''${!params[@]}"; do
        local value="''${params[$param]}"
        if [[ -v substitutions["$value"] ]]; then
          params["$param"]="''${substitutions["$value"]}"
        fi
      done
      # 🦆 says ⮞ build da paramz
      cmd_args=()
      for param in "''${!params[@]}"; do
        cmd_args+=(--"$param" "''${params[$param]}")
      done
      return 0
    }
  '';
  
  # 🦆 says ⮞ matcher to json yao
  matchers = lib.mapAttrsToList (scriptName: data:
    let
      matcherCode = makePatternMatcher scriptName;
    in {
      name = scriptName;
      value = pkgs.writeText "${scriptName}-matcher" matcherCode;
    }
  ) generatedIntents;

  # 🦆 says ⮞ one shell script dat sourcez dem allz
  matcherSourceScript = pkgs.writeText "matcher-loader.sh" (
    lib.concatMapStringsSep "\n" (m: "source ${m.value}") matchers
  );

  # 🦆 says ⮞ oh duck... dis is where speed goes steroids yo iz diz cachin'?
  intentDataFile = pkgs.writeText "intent-entity-map4.json"
    (builtins.toJSON (
      lib.mapAttrs (_scriptName: intentList:
        let
          allData = lib.flatten (map (d: d.lists or {}) intentList.data);
          # 🦆 says ⮞ collect all sentences for diz intent
          sentences = lib.concatMap (d: d.sentences or []) intentList.data;      
          # 🦆 says ⮞ expand all sentence variants
          expandedSentences = lib.unique (lib.concatMap expandOptionalWords sentences);
          # 🦆 says ⮞ "in" > "out" for dem' subz 
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
          # 🦆 says ⮞ CRITICAL: Include the lists data for wildcard detection
          lists = lib.foldl (acc: d: acc // (d.lists or {})) {} intentList.data;
        in {
          inherit substitutions;
          sentences = expandedSentences;
          inherit lists;
        }
      ) generatedIntents
    ));

  # 🦆 says ⮞ fuzzy entity dictionary: script -> param -> list of (rawInput, canonicalOut)
  fuzzyEntityDictFile = pkgs.writeText "fuzzy-entity-dict.json"
    (builtins.toJSON (
      lib.mapAttrs (scriptName: intent:
        let
          # 🦆 collect all lists for this script
          lists = lib.foldl (acc: d: acc // (d.lists or {})) {} intent.data;
        in
          lib.mapAttrs (paramName: listData:
            # 🦆 expand every "in" field, collecting all raw tokens
            lib.unique (
              lib.concatMap (item:
                let
                  rawIn = item."in";
                  # 🦆 remove optional brackets for expansion
                  cleaned = lib.removePrefix "[" (lib.removeSuffix "]" rawIn);
                  # 🦆 split by "|" to get alternatives
                  alternatives = lib.splitString "|" cleaned;
                in
                  map (token: {
                    input = token;
                    output = item.out;
                  }) alternatives
              ) listData.values
            )
          ) lists
      ) generatedIntents
    ));

  # 🦆 says ⮞ quack! now we preslicin' dem sentences wit their fuzzynutty signatures for bitchin' fast fuzz-lookup!
  fuzzyIndex = lib.mapAttrsToList (scriptName: intent:
    lib.concatMap (data: # 🦆 says ⮞ dive into each intent entryz like itz bread crumbs
      lib.concatMap (sentence: # 🦆 says ⮞ grab all dem raw sentence templates
        map (expanded: { # 🦆 says ⮞ ayy, time to expand theze feathers
          script = scriptName; # 🦆 says ⮞ label diz bird wit itz intent script yo
          sentence = expanded; # 🦆 says ⮞ this da expanded sentence duck gon' match against
          # 🦆 says ⮞ precompute signature for FAAASTEERRr matching - quicky quacky snappy matchin' yo! 
          signature = let
            words = lib.splitString " " (lib.toLower expanded); # 🦆 says ⮞ lowercase & split likez stale rye
            #sorted = lib.sort (a: b: lib.hasPrefix a b) words; # 🦆 says ⮞ duck sort dem quackz alphabetically-ish quack quack
            sorted = lib.sort (a: b: a < b) words;
          in builtins.concatStringsSep "|" sorted;  # 🦆 says ⮞ make a fuzzy-flyin’ signature string, pipe separated - yo' know it 
        }) (expandOptionalWords sentence) # 🦆 says ⮞ diz iz where optional wordz becomez reality
      ) data.sentences # 🦆 says ⮞ waddlin' through all yo' sentencez
    ) intent.data # 🦆 says ⮞ scoopin' from every intentz
  ) generatedIntents; # 🦆 says ⮞ diz da sacred duck scripture — all yo' intents livez here boom  

  # 🦆 says ⮞ fuzzy index only for allowed yo scriptz dat allow dem fuzzy matchin' yo
  scriptsWithFuzzy = lib.filterAttrs (_: script: 
    script.voice != null && 
    (script.voice.enabled or true) &&
    (script.voice.fuzzy.enable or true)  # 🦆 Must explicitly allow fuzzy
  ) config.yo.scripts;

  splitWordsFile = pkgs.writeText "split-words.json" (builtins.toJSON config.yo.SplitWords);
  sorryPhrasesFile = pkgs.writeText "sorry-phrases.json" (builtins.toJSON config.yo.sorryPhrases);
  fuzzyIndexFile = pkgs.writeText "fuzzy-index.json" (builtins.toJSON fuzzyIndex);
  fuzzyIndexFlatFile = pkgs.writeText "fuzzy-rust-index.json" (builtins.toJSON fuzzyFlatIndex);  
  matcherDir = pkgs.linkFarm "yo-matchers" (
    map (m: { name = "${m.name}.sh"; path = m.value; }) matchers
  ); 

  # 🦆 duck say ⮞ turn hyphens into underscores so bash is happy
  sanitizeVarName = name: builtins.replaceStrings ["-"] ["_"] name;

  # 🦆 says ⮞ priority system 4 runtime optimization
  scriptRecordsWithIntents = 
    let # 🦆 says ⮞ calculate priority
      calculatePriority = scriptName:
        generatedIntents.${scriptName}.priority or 3; # Default medium

      # 🦆 says ⮞ create script records metadata
      makeRecord = scriptName: rec {
        name = scriptName;
        priority = calculatePriority scriptName;
        hasComplexPatterns = 
          let 
            intent = generatedIntents.${scriptName};
            patterns = lib.concatMap (d: d.sentences) intent.data;
          in builtins.any (p: lib.hasInfix "{" p || lib.hasInfix "[" p) patterns;
      };    
    in lib.sort (a: b:
        # 🦆 says ⮞ primary sort: lower number = higher priority
        a.priority < b.priority 
        # 🦆 says ⮞ secondary sort: simple patterns before complex ones
        || (a.priority == b.priority && !a.hasComplexPatterns && b.hasComplexPatterns)
        # 🦆 says ⮞ third sort: alphabetical for determinism
        || (a.priority == b.priority && a.hasComplexPatterns == b.hasComplexPatterns && a.name < b.name)
      ) (map makeRecord scriptNamesWithIntents);
  # 🦆 says ⮞ generate optimized processing order
  processingOrder = map (r: r.name) scriptRecordsWithIntents;

  failingScripts = lib.filter (script:
    ! ( (script.binary == null && (script.code != null && script.code != "")) ||
        (script.binary != null && (script.code == null || script.code == "")) )
  ) (lib.attrValues cfg.scripts); 
 
  # 🦆 says ⮞ conflict detection - no bad voice intentz quack!  
  assertionCheckForConflictingSentences = let
    # 🦆 says ⮞ collect all expanded sentences with their script originz
    allExpandedSentences = lib.flatten (lib.mapAttrsToList (scriptName: intent:
      lib.concatMap (data:
        lib.concatMap (sentence:
          map (expanded: {
            inherit scriptName;
            sentence = expanded;
            original = sentence;
            # 🦆 says ⮞ extract parameter positionz & count da fixed words
            hasWildcardAtEnd = lib.hasSuffix " {search}" (lib.toLower expanded) || 
                              lib.hasSuffix " {param}" (lib.toLower expanded) ||
                              (lib.hasInfix " {" expanded && 
                               !(lib.hasInfix "} " expanded)); # 🦆 says ⮞ wildcard at end if no } followed by space
            fixedWordCount = let
              words = lib.splitString " " expanded;
              nonParamWords = lib.filter (word: 
                !(lib.hasPrefix "{" word) && !(lib.hasSuffix "}" word)
              ) words;
            in lib.length nonParamWords;
          }) (expandOptionalWords sentence)
        ) data.sentences
      ) intent.data
    ) generatedIntents);
    # 🦆 says ⮞ check for prefix conflictz
    checkPrefixConflicts = sentences:
      let
        sortedSentences = lib.sort (a: b: 
          lib.stringLength a.sentence < lib.stringLength b.sentence
        ) sentences;
        conflicts = lib.foldl (acc: shorterItem:
          let
            shorter = shorterItem.sentence;
            shorterScript = shorterItem.scriptName;
            shorterHasWildcard = shorterItem.hasWildcardAtEnd;
          in
            acc ++ (lib.foldl (innerAcc: longerItem:
              let
                longer = longerItem.sentence;
                longerScript = longerItem.scriptName;
              in
                if shorterScript != longerScript then
                  if lib.hasPrefix (shorter + " ") longer && shorterHasWildcard then
                    innerAcc ++ [{
                      type = "PREFIX_CONFLICT";
                      shorter = shorter;
                      longer = longer;
                      scripts = [shorterScript longerScript];
                      reason = "Shorter pattern '${shorter}' (ends with wildcard) is a prefix of '${longer}'";
                    }]
                  else
                    innerAcc
                else
                  innerAcc
            ) [] sortedSentences)
        ) [] sortedSentences;
      in
        conflicts;
    # 🦆 says ⮞ find prefix conflictz!
    sentencesByText = lib.groupBy (item: item.sentence) allExpandedSentences;
    exactConflicts = lib.filterAttrs (sentence: items:
      let 
        uniqueScripts = lib.unique (map (item: item.scriptName) items);
      in 
        lib.length uniqueScripts > 1
    ) sentencesByText; 
    # 🦆 says ⮞ find duplicatez!
    exactConflictList = lib.mapAttrsToList (sentence: items:
      let
        scripts = lib.unique (map (item: item.scriptName) items);
      in { # 🦆  says ⮞ format exact conflictz dawg
        type = "EXACT_CONFLICT";
        sentence = sentence;
        scripts = scripts;
        reason = "Exact pattern match in scripts: ${lib.concatStringsSep ", " scripts}";
      }
    ) exactConflicts;   
    # 🦆  says ⮞ find prefix conflictz
    prefixConflicts = checkPrefixConflicts allExpandedSentences;    
    # 🦆  says ⮞ letz put dem conflictz together okay?
    allConflicts = exactConflictList ++ prefixConflicts;
    hasConflicts = allConflicts != [];    
    # 🦆  says ⮞ find da prefix conflictz  
  in {
    assertion = !hasConflicts;
    message = 
      if hasConflicts then
        let
          conflictMsgs = map (conflict:
            if conflict.type == "EXACT_CONFLICT" then
              ''
              🦆 says ⮞ CONFLICT! 
                Pattern "${conflict.sentence}"
                In scripts: ${lib.concatStringsSep ", " conflict.scripts}
              ''
            else if conflict.type == "PREFIX_CONFLICT" then
              ''
              🦆 says ⮞ CONFLICT!
                Shorter: "${conflict.shorter}" (ends with wildcard)
                Longer:  "${conflict.longer}"
                Scripts: ${lib.concatStringsSep ", " conflict.scripts}
                Reason:  ${conflict.reason}
              ''
            else
              ""
          ) allConflicts;
        in
          "Sentence conflicts detected in voice definition:\n\n" +
          lib.concatStringsSep "\n" conflictMsgs +
          "\n\n🦆 says ⮞ fix da conflicts before rebuildin' yo!"
      else
        "No sentence conflicts found.";
  };

  # 🦆 says ⮞ category based helper with actual names instead of {param}
  voiceSentencesHelpFile = pkgs.writeText "voice-sentences-help.md" (
    let
      scriptsWithVoice = lib.filterAttrs (_: script: 
        script.voice != null && script.voice.sentences != [] && (script.voice.enabled or true)
      ) config.yo.scripts;
      
      # 🦆 says ⮞ replace {param} with actual values from voice lists
      replaceParamsWithValues = sentence: voiceData:
        let
          # 🦆 says ⮞ find all {param} placeholders in the sentence
          paramMatches = builtins.match ".*(\\{([^}]+)\\}).*" sentence;
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
                      # 🦆 says ⮞ get all possible input values
                      values = map (v: v."in") listData.values;
                      # 🦆 says ⮞ expand any optional patterns like [foo|bar]
                      expandedValues = lib.concatMap expandListInputVariants values;
                      # 🦆 says ⮞ take first few examples for display
                      examples = lib.take 3 (lib.unique expandedValues);
                    in
                      if examples == [] then "ANYTHING"
                      else "(" + lib.concatStringsSep "|" examples + 
                           (if lib.length examples < lib.length expandedValues then "|...)" else ")")
                else
                  "ANYTHING" # 🦆 says ⮞ fallback if param not found
            else
              token;
          
          # 🦆 says ⮞ split sentence and process each token
          tokens = lib.splitString " " sentence;
          processedTokens = map processToken tokens;
        in
          lib.concatStringsSep " " processedTokens;
      
      # 🦆 says ⮞ group by category
      groupedScripts = lib.groupBy (script: script.category or "🧩 Miscellaneous") 
        (lib.attrValues scriptsWithVoice);
      
      # 🦆 says ⮞ generate category sections with param replacement
      categorySections = lib.mapAttrsToList (category: scripts:
        let
          scriptLines = map (script:
            let
              # 🦆 says ⮞ replace params in each sentence
              sentenceLines = lib.concatMapStrings (sentence: 
                let processedSentence = replaceParamsWithValues sentence script.voice;
                in "    - \"${escapeMD processedSentence}\"\n"
              ) script.voice.sentences;
            in
              "  **${escapeMD script.name}**:\n${sentenceLines}"
          ) (lib.sort (a: b: a.name < b.name) scripts);
        in
          "# ${category}\n\n${lib.concatStringsSep "\n" scriptLines}"
      ) groupedScripts;
      
      # 🦆 says ⮞ statistics
      totalScripts = lib.length (lib.attrNames config.yo.scripts);
      voiceScripts = lib.length (lib.attrNames scriptsWithVoice);
      totalPatterns = config.yo.generatedPatterns;
      totalPhrases = config.yo.understandsPhrases;    
      stats = ''  
  # ----────----──⋆⋅☆☆☆⋅⋆─────----─ #
  # Total:  
  - **Scripts with voice enabled**: ${toString voiceScripts} / ${toString totalScripts}
  - **Generated patterns**: ${toString totalPatterns}
  - **Understandable phrases**: ${toString totalPhrases}
      '';
    in
      "# 🦆 Voice Commands\nÅ\n\n${lib.concatStringsSep "\n\n" categorySections}\n\n${stats}"
  );


  # 🦆 says ⮞ for README version badge yo
  nixosVersion = let
    raw = builtins.readFile /etc/os-release;
    versionMatch = builtins.match ".*VERSION_ID=([0-9\\.]+).*" raw;
  in builtins.replaceStrings [ "." ] [ "%2E" ] (builtins.elemAt versionMatch 0);

  sysHosts = builtins.attrNames self.nixosConfigurations;
  vmHosts = builtins.filter (host:
    self.nixosConfigurations.${host}.self.config.system.build ? vm
  ) sysHosts;  
  # 🦆 duck say ⮞ comma sep list of your hosts
  sysHostsComma = builtins.concatStringsSep "," sysHosts;

  # 🦆 duck say ⮞ validate time format - HH:MM (24h)
  isValidTime = timeStr:
    let
      matches = builtins.match "([0-9]{1,2}):([0-9]{2})" timeStr;
    in
      if matches != null then
        let
          hourStr = builtins.elemAt matches 0;
          minuteStr = builtins.elemAt matches 1;
          # 🦆 duck say ⮞ remove leading zeros for JSON parsin'
          cleanNumber = str:
            if builtins.substring 0 1 str == "0" && builtins.stringLength str > 1
            then builtins.substring 1 (builtins.stringLength str) str
            else str;
          hour = builtins.fromJSON (cleanNumber hourStr);
          minute = builtins.fromJSON (cleanNumber minuteStr);
        in
          hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59
      else false;
  
  # 🦆 duck say ⮞ validate list of timez
  validateTimes = times:
    if times == null then null
    else
      let
        invalidTimes = lib.filter (time: !isValidTime time) times;
      in
        if invalidTimes != [] then
          throw "🦆 duck say ⮞ fuck ❌ Invalid time format in runAt: ${lib.concatStringsSep ", " invalidTimes}. Use HH:MM (24-hour format)"
        else times;

  # 🦆 duck say ⮞ expoort param into shell script
  yoEnvGenVar = script: let
    withDefaults = builtins.filter (p: p.default != null) script.parameters;
    exports = map (p: 
      let # 🦆 duck say ⮞ convert dem Nix types 2 shell strings
        defaultValue = 
          if p.type == "string" then lib.escapeShellArg (toString p.default)
          else if p.type == "int" then toString p.default
          else if p.type == "bool" then (if p.default then "true" else "false")
          else if p.type == "path" then lib.escapeShellArg (toString p.default)
          else lib.escapeShellArg (toString p.default);
      in
        "export ${sanitizeVarName p.name}=${defaultValue}"
    ) withDefaults;
  in lib.concatStringsSep "\n" exports;

  # 🦆 duck say ⮞ build scripts for da --help command
  terminalScriptsTableFile = pkgs.writeText "yo-helptext.md" terminalScriptsTable;
  # 🦆 duck say ⮞ markdown help text
  terminalScriptsTable = let # 🦆 duck say ⮞ categorize scripts
    groupedScripts = lib.groupBy (script: script.category) (lib.attrValues cfg.scripts);
    # 🦆 duck say ⮞ sort da scriptz by category
    visibleScripts2 = lib.filterAttrs (_: script: script.visibleInReadme) cfg.scripts;
    groupedScripts2 = lib.groupBy (script: script.category) (lib.attrValues visibleScripts2);
    sortedCategories2 = lib.sort (a: b: 
      # 🦆 duck say ⮞ system management goes first yo
      if a == "🖥️ System Management" then true
      else if b == "🖥️ System Management" then false
      else a < b # 🦆 duck say ⮞ after dat everything else quack quack
    ) (lib.attrNames groupedScripts2);
  
    # 🦆 duck say ⮞ create table rows with category separatorz 
    rows = lib.concatMap (category:
      let  # 🦆 duck say ⮞ sort from A to Ö  
        scripts = lib.sort (a: b: a.name < b.name) groupedScripts.${category};
      in
        [ # 🦆 duck say ⮞ add **BOLD** header table row for category
          "| **${escapeMD category}** | | |"
        ] 
        ++ # 🦆 duck say ⮞ each yo script goes into a table row
        (map (script:
          let # 🦆 duck say ⮞ format list of aliases
            aliasList = if script.aliases != [] then
              concatStringsSep ", " (map escapeMD script.aliases)
            else "";
            # 🦆 duck say ⮞ generate CLI parameter hints, with [] for optional/defaulted
            paramHint = concatStringsSep " " (map (param:
              if param.optional || param.default != null
              then "[--${param.name}]"
              else "--${param.name}"
            ) script.parameters);
            # 🦆 duck say ⮞ render yo script syntax with param
            syntax = "\\`yo ${escapeMD script.name} ${paramHint}\\`";
          in # 🦆 duck say ⮞ write full md table row - command | aliases | description
            "| ${syntax} | ${aliasList} | ${escapeMD script.description} |"
        ) scripts)
    ) sortedCategories2;
  in concatStringsSep "\n" rows;
 
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
        YO_FUZZY_ENTITY_DICT = fuzzyEntityDictFile;
        "YO_FUZZY_INDEX" = fuzzyIndexFlatFile;
        MATCHER_DIR = matcherDir;
        MATCHER_SOURCE = matcherSourceScript;
      };

      # Generate configuration files in /etc/yo  
      environment.etc = {
        "yo/split-words.json".source = splitWordsFile;
        "yo/sorry-phrases.json".source = sorryPhrasesFile;
        "yo/intent-data.json".source = intentDataFile;
        "yo/fuzzy-index.json".source = fuzzyIndexFlatFile;
        "yo/fuzzy-entity-dict.json".source = fuzzyEntityDictFile;
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
            timerConfig = let
              runEveryStr = script.runEvery;
              isMinute = builtins.match "^[0-9]+$" runEveryStr != null
                         && lib.toInt (lib.head (builtins.match "0*([0-9]+)" runEveryStr)) <= 59;
              onCalendar = if isMinute
                           then "*-*-* *:${runEveryStr}:00"
                           else "*-*-* *:0/${runEveryStr}";
            in {
              OnCalendar = onCalendar;
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
        binary = "${config.services.yo-rs.package}/bin/yo-do";
        category = "🗣️ Voice";
        logLevel = "INFO";
        parameters = [
          { name = "input"; description = "Text to translate"; optional = true; } 
          { name = "fuzzy"; type = "int"; description = "Minimum procentage for considering fuzzy matching sucessful. (1-100)"; default = 25; }
          { name = "room"; type = "string"; description = "Optional client area (used for context)"; optional = true; }
        ];
      };
  
      yo.scripts.tests = {
        description = "Extensive automated sentence testing for the yo do"; 
        binary = "${config.services.yo-rs.package}/bin/yo-tests";      
        category = "🗣️ Voice";
        parameters = [
          { name = "input"; description = "Text to test as a single  sentence test"; optional = true; }
          { name = "stats"; type = "bool"; description = "Flag to display voice commands information like generated regex patterns, generated phrases and ratio"; optional = true; }    
          { name = "fuzzy"; type = "int"; description = "Minimum procentage for considering fuzzy matching sucessful. (1-100)"; default = 30; }
        ];
      };  
  
  
      yo.scripts.say = {
        description = "Text to speech with built in language detection and automatic model downloading";
        binary = "${config.services.yo-rs.package}/bin/yo-say";
        category = "🗣️ Voice";
        logLevel = "WARNING";
        parameters = [
          { name = "text"; description = "Input text that should be spoken"; optional = false; }      
          { name = "model"; description = "File name of the model"; default = config.services.yo-rs.server.textToSpeechModelPath; }
          { name = "blocking"; type = "bool"; description = "Wait for TTS playback to finish"; default = false; }
          { name = "path"; description = "Specify a file path where wav will be saved to disk"; optional = true; }
          { name = "length-scale"; description = "Speech speed"; default = "1.3"; optional = true; }                    
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
