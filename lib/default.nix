{ 
  lib
} : with lib;
rec {
  cartesianProductOfLists = lists:
    if lists == [] then
      [ [] ]
    else
      let
        head = builtins.head lists;

        tail = builtins.tail lists;

        tailProduct = cartesianProductOfLists tail;
      in
        lib.concatMap (x:
          map (y: [x] ++ y) tailProduct
        ) head;
        
  # EXAMPLE ⮞ cartesianProductOfLists [ ["a" "b"] ["1" "2"] ["x" "y"] ]
  # BOOOOOM ⮟
  #  [ ["a" "1" "x"]
  #    ["a" "1" "y"]
  #    ["a" "2" "x"]
  #    ["a" "2" "y"]
  #    ["b" "1" "x"]
  #    ["b" "1" "y"]
  #    ["b" "2" "x"]
  #    ["b" "2" "y"] ]

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
        in
          cleaned
      ) expanded;

      nonEmpty = lib.filter (s: s != "") trimmedVariants;
      hasFixedText = v: builtins.match ".*[^\\{].*" v != null;
      validVariants = lib.filter hasFixedText nonEmpty;
    in
      lib.unique validVariants;


  expandListInputVariants = value:
    let
      tokens = lib.splitString " " value;

      isOptional = t: lib.hasPrefix "[" t && lib.hasSuffix "]" t;

      expandToken = token:
        if isOptional token then
          let
            clean = lib.removePrefix "[" (lib.removeSuffix "]" token);
            alternatives = lib.splitString "|" clean;
          in
            alternatives
        else
          [ token ];
      expanded = cartesianProductOfLists (map expandToken tokens);
      variants = map (tokenList:
        lib.replaceStrings [ "  " ] [ " " ] (lib.concatStringsSep " " tokenList)
      ) expanded;
    in lib.unique (lib.filter (s: s != "") variants);


  expandToRegex = sentence: data:
    let
      convertPattern = token:
        if lib.hasPrefix "(" token then
          let
            clean = lib.removePrefix "(" (lib.removeSuffix ")" token);
            alternatives = lib.splitString "|" clean;
            escaped = map lib.escapeRegex alternatives;
          in "(?:" + lib.concatStringsSep "|" escaped + ")"
        else if lib.hasPrefix "[" token then
          let
            clean = lib.removePrefix "[" (lib.removeSuffix "]" token);
            alternatives = lib.splitString "|" clean;
            escaped = map lib.escapeRegex alternatives;
          in "(?:" + lib.concatStringsSep "|" escaped + ")?"
        else
          lib.escapeRegex token;

      tokenize = s:
        let
          groups = builtins.match "([^{]*)(\{[^}]*\})?(.*)" s;
        in
          if groups == null then [s]
          else let
            prefix = builtins.elemAt groups 0;
            param = builtins.elemAt groups 1;
            rest = builtins.elemAt groups 2;
            tokens = if prefix != "" then [prefix] else [];
            tokensWithParam = if param != null then tokens ++ [param] else tokens;
          in tokensWithParam ++ tokenize rest;

      tokens = tokenize sentence;
      regexParts = map (token:
        if lib.hasPrefix "{" token then
          let
            param = lib.removePrefix "{" (lib.removeSuffix "}" token);
            isWildcard = data.lists.${param}.wildcard or false;
          in if isWildcard then "(.*)" else "\\b([^ ]+)\\b"
        else
          convertPattern token
      ) tokens;

      regex = "^" + lib.concatStrings regexParts + "$";
    in
      regex;


  makeEntityResolver = data: listName:
    lib.concatMapStrings (entity:
      let
        variants = expandListInputVariants entity."in";
      in
        lib.concatMapStrings (variant: ''
          "${variant}") echo "${entity.out}";;
        '') variants
    ) data.lists.${listName}.values;


  escapeMD = str: let
    replacements = [
      [ "\\" "\\\\" ]
      [ "*" "\\*" ]
      [ "`" "\\`" ]
      [ "_" "\\_" ]
      [ "[" "\\[" ]
      [ "]" "\\]" ]
    ];
  in
    lib.foldl (acc: r: lib.replaceStrings [ (builtins.elemAt r 0) ] [ (builtins.elemAt r 1) ] acc) str replacements;


  makeTimerName = scriptName: timeStr:
    let
      safeTime = replaceStrings [":"] ["-"] timeStr;
    in
      "yo-${scriptName}-at-${safeTime}";


  countGeneratedPatterns = script:
    if script.voice == null then
      0
    else
      let
        expandedSentences = lib.concatMap expandOptionalWords script.voice.sentences;
      in
        lib.length expandedSentences;


  countUnderstoodPhrases = script:
    if script.voice == null then
      0
    else
      let
        expandedSentences = lib.concatMap expandOptionalWords script.voice.sentences;

        extractParamNames = sentence:
          let
            parts = lib.splitString "{" sentence;
            paramNames = lib.concatMap (part:
              let
                paramPart = lib.splitString "}" part;
              in
                if lib.length paramPart > 1 then
                  [ (lib.elemAt paramPart 0) ]
                else
                  []
            ) (lib.tail parts);
          in
            paramNames;

        countPhrasesForSentence = sentence:
          let
            paramNames = extractParamNames sentence;
          in
            if paramNames == [] then
              1
            else
              let
                paramValueCounts = map (paramName:
                  let
                    list = script.voice.lists.${paramName} or null;
                  in
                    if list == null then 1
                    else lib.length list.values
                ) paramNames;

                totalCombinations = lib.foldl (a: b: a * b) 1 paramValueCounts;
              in
                totalCombinations;

        totalPhrases = lib.foldl (total: sentence:
          total + countPhrasesForSentence sentence
        ) 0 expandedSentences;
      in
        totalPhrases;


  countTotalGeneratedPatterns = scripts:
    lib.foldl (total: script:
      total + countGeneratedPatterns script
    ) 0 (lib.attrValues scripts);


  countTotalUnderstoodPhrases = scripts:
    lib.foldl (total: script:
      total + countUnderstoodPhrases script
    ) 0 (lib.attrValues scripts);
}
