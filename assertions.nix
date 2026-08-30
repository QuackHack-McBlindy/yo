{ 
  config,
  lib,
  ...
} : let
  cfg = config.yo;
  scripts = cfg.scripts;
  scriptNames = lib.attrNames scripts;

  # Helper formatters
  formatConflict = alias: scrs:
    "Alias '${alias}' conflicts with script name (used by: ${lib.concatStringsSep ", " scrs})";
  formatDuplicate = alias: scrs:
    "Alias '${alias}' used by multiple scripts: ${lib.concatStringsSep ", " scrs}";

  # Scripts that violate the code/binary exclusivity rule
  failingScripts = lib.filter (script:
    ! ( (script.binary == null && (script.code != null && script.code != "")) ||
        (script.binary != null && (script.code == null || script.code == "")) )
  ) (lib.attrValues scripts);

  # Voice sentence conflicts
  # cartesian product of lists
  cartesianProductOfLists = lists:
    if lists == [] then
      [ [] ]
    else
      let
        head = builtins.head lists;
        tail = builtins.tail lists;
        tailProduct = cartesianProductOfLists tail;
      in
        lib.concatMap (x: map (y: [x] ++ y) tailProduct) head;

  # expand optional/alternative words in a sentence
  expandOptionalWords = sentence:
    let
      tokens = lib.splitString " " sentence;
      isRequiredGroup = t: lib.hasPrefix "(" t && lib.hasSuffix ")" t;
      isOptionalGroup = t: lib.hasPrefix "[" t && lib.hasSuffix "]" t;
      expandToken = token:
        if isRequiredGroup token then
          let
            clean = lib.removePrefix "(" (lib.removeSuffix ")" token);
            alternatives = lib.splitString "|" clean;
          in
            alternatives
        else if isOptionalGroup token then
          let
            clean = lib.removePrefix "[" (lib.removeSuffix "]" token);
            alternatives = lib.splitString "|" clean;
          in
            alternatives ++ [ "" ]
        else
          [ token ];
      expanded = cartesianProductOfLists (map expandToken tokens);
      trimmedVariants = map (tokenList:
        let
          raw = lib.concatStringsSep " " tokenList;
          cleaned = lib.replaceStrings ["  "] [" "] (lib.strings.trim raw);
        in cleaned
      ) expanded;
      nonEmpty = lib.filter (s: s != "") trimmedVariants;
      hasFixedText = v: builtins.match ".*[^\\{].*" v != null;
      validVariants = lib.filter hasFixedText nonEmpty;
    in
      lib.unique validVariants;

  # scripts with voice enabled
  scriptsWithVoice = lib.filterAttrs (_: script:
    script.voice != null && (script.voice.enabled or true)
  ) scripts;

  # Generate intents from voice data
  generatedIntents = lib.mapAttrs (name: script: {
    priority = script.voice.priority or 3;
    data = [{
      inherit (script.voice) sentences lists;
    }];
  }) scriptsWithVoice;

  # Collect all expanded sentences with their script origin
  allExpandedSentences = lib.flatten (lib.mapAttrsToList (scriptName: intent:
    lib.concatMap (data:
      lib.concatMap (sentence:
        map (expanded: {
          inherit scriptName;
          sentence = expanded;
          original = sentence;
          hasWildcardAtEnd = lib.hasSuffix " {search}" (lib.toLower expanded) ||
                              lib.hasSuffix " {param}" (lib.toLower expanded) ||
                              (lib.hasInfix " {" expanded && !(lib.hasInfix "} " expanded));
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

  # Check for prefix conflicts (shorter wildcard pattern is prefix of longer)  
  checkPrefixConflicts = sentences:
    let
      sortedSentences = lib.sort (a: b:
        lib.stringLength a.sentence < lib.stringLength b.sentence
      ) sentences;
      conflicts = lib.foldl' (acc: shorterItem:
        let
          shorter = shorterItem.sentence;
          shorterScript = shorterItem.scriptName;
          shorterHasWildcard = shorterItem.hasWildcardAtEnd;
        in
          acc ++ (lib.foldl' (innerAcc: longerItem:
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
    in conflicts;
  

  # Find exact duplicates
  sentencesByText = lib.groupBy (item: item.sentence) allExpandedSentences;
  exactConflicts = lib.filterAttrs (sentence: items:
    let
      uniqueScripts = lib.unique (map (item: item.scriptName) items);
    in
      lib.length uniqueScripts > 1
  ) sentencesByText;

  exactConflictList = lib.mapAttrsToList (sentence: items:
    let
      scripts = lib.unique (map (item: item.scriptName) items);
    in {
      type = "EXACT_CONFLICT";
      sentence = sentence;
      scripts = scripts;
      reason = "Exact pattern match in scripts: ${lib.concatStringsSep ", " scripts}";
    }
  ) exactConflicts;

  prefixConflicts = checkPrefixConflicts allExpandedSentences;
  allConflicts = exactConflictList ++ prefixConflicts;
  hasConflicts = allConflicts != [];

  voiceConflictAssertion = {
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

  # entity list ambiguity
  listAmbiguities = lib.flatten (lib.mapAttrsToList (scriptName: intent:
    lib.flatten (lib.mapAttrsToList (listName: listConfig:
      let
        values = listConfig.values or [];
        grouped = lib.groupBy (v: v.${"in"}) values;
        ambiguous = lib.filterAttrs (input: entries:
          lib.length (lib.unique (map (e: e.out) entries)) > 1
        ) grouped;
      in
        lib.mapAttrsToList (input: entries:
          {
            script = scriptName;
            list = listName;
            input = input;
            outputs = lib.unique (map (e: e.out) entries);
          }
        ) ambiguous
    ) (intent.lists or {}))
  ) generatedIntents);

  hasListAmbiguities = listAmbiguities != [];

  listAmbiguityAssertion = {
    assertion = !hasListAmbiguities;
    message =
      if hasListAmbiguities then
        "Entity list ambiguities detected:\n" +
        lib.concatStringsSep "\n" (map (amb:
          "  Script '${amb.script}', list '${amb.list}': input '${amb.input}' maps to multiple outputs: " +
          lib.concatStringsSep ", " amb.outputs
        ) listAmbiguities)
      else
        "No entity list ambiguities.";
  };


  # fuzzy duplicate detection
  tokenize = s:
    let
      chars = lib.stringToCharacters (lib.toLower s);
      allowed = c: (c >= "a" && c <= "z") || (c >= "0" && c <= "9") || c == " ";
      cleanedChars = lib.filter allowed chars;
      cleaned = lib.concatStrings cleanedChars;
      words = lib.splitString " " cleaned;
    in
      lib.unique (lib.filter (w: w != "") words);

  jaccardPercent = a: b:
    let
      inter = lib.length (lib.intersectLists a b);
      union = lib.length (lib.unique (a ++ b));
    in
      if union == 0 then 100 else (inter * 100) / union;

  
  fuzzyDuplicates = let
    n = builtins.length allExpandedSentences;
    indices = lib.range 0 (n - 1);
    pairs = lib.concatMap (i:
      lib.concatMap (j:
        if i < j then
          let
            itemI = builtins.elemAt allExpandedSentences i;
            itemJ = builtins.elemAt allExpandedSentences j;
            scriptI = itemI.scriptName;
            scriptJ = itemJ.scriptName;
            sentI = itemI.sentence;
            sentJ = itemJ.sentence;
            toksI = tokenize sentI;
            toksJ = tokenize sentJ;
            simPercent = jaccardPercent toksI toksJ;
          in
            if scriptI != scriptJ && simPercent > cfg.fuzzy.conflict.threshold &&
               !(sentI == sentJ) &&
               !(itemI.hasWildcardAtEnd && lib.hasPrefix (sentI + " ") sentJ) &&
               !(itemJ.hasWildcardAtEnd && lib.hasPrefix (sentJ + " ") sentI)
            then
              [{
                script1 = scriptI;
                sentence1 = sentI;
                script2 = scriptJ;
                sentence2 = sentJ;
                similarity = simPercent;
              }]
            else
              []
        else
          []
      ) indices
    ) indices;
  in pairs;


  hasfuzzyDuplicates = fuzzyDuplicates != [];

  fuzzyDuplicateAssertion = {
    assertion = !hasfuzzyDuplicates;
    message =
      if hasfuzzyDuplicates then
        "🦆 duck say ⮞ fuck ❌ Fuzzy index may contain near-duplicate sentences (token similarity > ${toString cfg.fuzzy.conflict.threshold}%):\n" +
        lib.concatStringsSep "\n" (map (conf:
          "  '${conf.sentence1}' (${conf.script1}) vs '${conf.sentence2}' (${conf.script2}) [${toString conf.similarity}%]"
        ) fuzzyDuplicates)
      else
        "No fuzzy duplicates detected.";
  };

in {

  config = {
    assertions = let
      # Errors for runAt (scheduled times)
      runAtErrors = lib.mapAttrsToList (name: script:
        if script.runAt != null then
          let
            missingParams = lib.filter (p: !p.optional && p.default == null) script.parameters;
          in
            if missingParams != [] then
              "🦆 duck say ⮞ fuck ❌ Cannot schedule '${name}' at ${lib.concatStringsSep ", " script.runAt} - missing defaults for: " +
              lib.concatMapStringsSep ", " (p: p.name) missingParams
            else null
        else null
      ) scripts;
      actualRunAtErrors = lib.filter (e: e != null) runAtErrors;

      # build alias > script names map
      aliasMap = lib.foldl' (acc: script:
        lib.foldl' (acc': alias:
          acc' // { ${alias} = (acc'.${alias} or []) ++ [script.name]; }
        ) acc script.aliases
      ) {} (lib.attrValues scripts);

      # conflicts: alias equals a script name
      scriptNameConflicts = lib.filterAttrs (alias: _: lib.elem alias scriptNames) aliasMap;

      # duplicate aliases (same alias used by multiple scripts)
      duplicateAliases = lib.filterAttrs (_: scrs: lib.length scrs > 1) aliasMap;

      # auto‑start scripts missing defaults for required parameters
      autoStartErrors = lib.mapAttrsToList (name: script:
        if script.autoStart then
          let
            missingParams = lib.filter (p: !p.optional && p.default == null) script.parameters;
          in
            if missingParams != [] then
              "🦆 duck say ⮞ fuck ❌ Cannot auto-start '${name}' - missing defaults for: " +
              lib.concatMapStringsSep ", " (p: p.name) missingParams
            else null
        else null
      ) scripts;
      actualAutoStartErrors = lib.filter (e: e != null) autoStartErrors;

      # Parameters that have a `values` list but are not of type `string`
      valueTypeErrors = lib.concatMap (script:
        lib.concatMap (param:
          if param.values != null && param.type != "string" then
            [ "🦆 duck say ⮞ fuck ❌ Parameter '${param.name}' in script '${script.name}' has 'value' defined but type is '${param.type}' (only 'string' type allowed)" ]
          else []
        ) script.parameters
      ) (lib.attrValues scripts);

    in [
      # Alias conflicts with script names
      {
        assertion = scriptNameConflicts == {};
        message = "🦆 duck say ⮞ fuck ❌ Alias/script name conflicts:\n" +
          lib.concatStringsSep "\n" (lib.mapAttrsToList formatConflict scriptNameConflicts);
      }

      # Duplicate aliases
      {
        assertion = duplicateAliases == {};
        message = "🦆 duck say ⮞ fuck ❌ Duplicate aliases:\n" +
          lib.concatStringsSep "\n" (lib.mapAttrsToList formatDuplicate duplicateAliases);
      }

      # Code/binary exclusivity (first check)
      {
        assertion = failingScripts == [];
        message = "The following scripts do not have exactly one of `code` or `binary` defined (non‑empty): " +
          lib.concatStringsSep ", " (lib.map (s: s.name) failingScripts);
      }

      # Auto‑start scripts with missing defaults
      {
        assertion = actualAutoStartErrors == [];
        message = "Auto-start errors:\n" + lib.concatStringsSep "\n" actualAutoStartErrors;
      }

      # scheduled scripts (runAt) with missing defaults
      {
        assertion = actualRunAtErrors == [];
        message = "runAt scheduling errors:\n" + lib.concatStringsSep "\n" actualRunAtErrors;
      }

      # cannot have both runEvery and runAt
      {
        assertion = lib.all (script: !(script.runEvery != null && script.runAt != null)) (lib.attrValues scripts);
        message = "🦆 duck say ⮞ fuck ❌ Script cannot have both runEvery and runAt set";
      }

      # `values` only allowed for string parameters
      {
        assertion = valueTypeErrors == [];
        message = "Value type errors:\n" + lib.concatStringsSep "\n" valueTypeErrors;
      }

      # Code/binary exclusivity
      {
        assertion = lib.all (script:
          (script.code != null && script.code != "" && script.binary == null) ||
          (script.binary != null && (script.code == null || script.code == ""))
        ) (lib.attrValues scripts);
        message = "Each script must have exactly one of `code` or `binary` defined (non‑empty).";
      }

      # Voice sentence conflict assertion (always enabled)
      voiceConflictAssertion
    ] ++ lib.optionals cfg.fuzzy.conflict.detection [
      # Fuzzy checks (opt‑in)
      listAmbiguityAssertion
      fuzzyDuplicateAssertion
    ];

  };}
