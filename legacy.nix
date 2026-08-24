{ 
  lib,
  pkgs,
  matcherDir,
  matcherSourceScript,
  ...
} : let 
  commonHelpers = ''
    elapsed_since_start() {
      local now=$(date +%s.%N)
      local elapsed=$(echo "$now - $start" | bc)
      printf "%.3f" "$elapsed"
    }

    BOLD="\033[1m"
    BLINK="\033[5m"
    YELLOW="\033[33m"
    BLUE="\033[34m"
    GREEN="\033[0;32m"
    ALERT='\033[1;5;31m'
    RED='\033[1;31m'
    NC='\033[0m'
    RESET='\033[0m'
    GRAY="\033[38;5;244m"

    DSAY="\033[3m\033[38;2;0;150;150m"   
    bold() {
      echo -e "\033[1m$1\033[0m"
    }  
    # 🦆 says ⮞ duckTrace logging
    declare -A DT_LEVEL_MAP=( [DEBUG]=0 [INFO]=1 [WARNING]=2 [ERROR]=3 [CRITICAL]=4 )

    if [[ -n "$DT_LOG_LEVEL" && ! "$DT_LOG_LEVEL" =~ ^[0-9]+$ ]]; then
      export DT_LOG_LEVEL_NUM="''${DT_LEVEL_MAP[''${DT_LOG_LEVEL^^}]:-1}"
    else
      : ''${DT_LOG_LEVEL_NUM:=1}
    fi

    declare -A DT_LEVEL_MAP=( [DEBUG]=0 [INFO]=1 [WARNING]=2 [ERROR]=3 [CRITICAL]=4 )
    _dt_log() {
      local level="$1"
      local symbol="$2"
      local color="$3"
      local message="$4"
      local blink="$5"
      local timestamp
      timestamp=$(date +"%H:%M:%S")
      local blink_code=""
      [[ "$blink" == "true" ]] && blink_code="$BLINK"
      local level_num="''${DT_LEVEL_MAP[$level]:-0}"
      (( level_num < DT_LOG_LEVEL_NUM )) && return      
      local max_size=1048576 # 1MB     

      if [[ -f "$log_path" && $(stat -c%s "$log_path") -gt $max_size ]]; then mv "$log_path" "$log_path.old"; fi

      local output="''${color}''${BOLD}''${blink_code}[🦆📜] [''${timestamp}] ''${symbol}''${level}''${symbol} ⮞ ''${message}''${RESET}"
      echo -e "$output" 
      if [[ "$level" == "error" ]]; then
        echo -e "\e[3m\e[38;2;0;150;150m🦆 duck say \e[1m\e[38;2;255;255;0m⮞\e[0m\e[3m\e[38;2;0;150;150m fuck ❌ ''${message}\e[0m}"
      fi
      echo "[''${timestamp}] ''${level} - ''${message}" >> "''${DT_LOG_PATH%/}/''${DT_LOG_FILE}"
    }

    dt_debug() {
      local elapsed_time=$(elapsed_since_start)
      local elapsed_text=""
      if (( $(echo "$elapsed_time < 10000" | bc -l) )); then
        elapsed_text="+$elapsed_time s "
      fi
      _dt_log "DEBUG" "⁉️" "$BLUE" "''${elapsed_text}$1" >&2
    }
    dt_info() {
      _dt_log "INFO" "✅" "$GREEN" "$1" >&2
    }
    dt_warning() {
      _dt_log "WARNING" "⚠️" "$YELLOW" "$1" >&2
    }
    dt_error() {
      _dt_log "ERROR" "❌" "$RED" "$1" true >&2
    }
    dt_critical() {
      _dt_log "CRITICAL" "🚨" "$RED" "$1" true >&2
    }
    dt_success() {
      _dt_log "SUCCESS" "✅" "$GREEN" "$1" >&2
    }  
    say_duck() {
      echo -e "\e[3m\e[38;2;0;150;150m🦆 duck say \e[1m\e[38;2;255;255;0m⮞\e[0m\e[3m\e[38;2;0;150;150m $1\e[0m"
    }
    say_no_match() {
      yo say "I didn't understand that"
    }
  '';
in {

  environment.etc = {
    "yo/matchers" = { source = matcherDir; };
    "yo/matcher-loader.sh".source = matcherSourceScript;
  };


  yo.scripts = {
    do = {
      description = "yo do - legacy version in Bash";
      category = "🗣️ Voice";
      logLevel = "INFO";
      parameters = [
        { name = "input"; description = "Text to parse into a yo command"; optional = false; }
        { name = "fuzzy"; type = "int"; description = "Minimum procentage for considering fuzzy matching sucessful. (1-100)"; default = 15; }
      ]; 
      code = ''
        ${commonHelpers}
        set +u  
        start_time=$(${pkgs.coreutils}/bin/date +%s%3N)

        FUZZY_THRESHOLD=$fuzzyThreshold
        intent_data_file="/etc/yo/intent-data.json"
        YO_FUZZY_INDEX="/etc/yo/fuzzy-index.json"
        text="$input"
        match_result_flag=$(mktemp)
        trap 'rm -f "$match_result_flag"' EXIT
        echo "waiting" > "$match_result_flag"
        debug_attempted_matches=()
        substitution_applied=false   
        declare -A script_substitutions_data
        declare -A script_has_lists  
        intent_data_json=$(<"$intent_data_file")
        while IFS=$'\t' read -r script pattern value; do
            if [[ -n "$script" ]]; then
                script_has_lists["$script"]=1
                key="''${script}:''${pattern}"
                script_substitutions_data["$key"]="$value"
            fi
        done < <(
            jq -r 'to_entries[] | .key as $script | .value.substitutions[]? | 
                    [$script, .pattern, .value] | @tsv' \
            <<<"$intent_data_json"
        )
        # Levenshtein distance
        levenshtein() {
          local a="$1" b="$1"
          local -i len_a=''${#a} len_b=''${#b}
          local -a d; local -i i j cost    
          for ((i=0; i<=len_a; i++)); do d[i]=$i; done
          for ((j=1; j<=len_b; j++)); do
            prev=$j
            for ((i=1; i<=len_a; i++)); do
              [[ "''${a:i-1:1}" == "''${b:j-1:1}" ]] && cost=0 || cost=1
              act=$(( d[i-1] + cost ))
              d[i]=$(( (d[i]+1) < (prev+1) ? 
                       ((d[i]+1) < act ? d[i]+1 : act) : 
                       ((prev+1) < act ? prev+1 : act) ))
              prev=$((d[i]))
            done
            d[0]=$j
          done
          echo ''${d[len_a]}
        }
        
        # Substitution / Entity list handler
        resolve_entities() {
          local script="$1"      
          local text="$2"
          local replacements
          local pattern out
          declare -A substitutions
          has_lists=$(jq -e '."'"$script"'"?.substitutions | length > 0' "$intent_data_file" 2>/dev/null || echo false)
          if [[ "$has_lists" != "true" ]]; then
            echo -n "$text"
            echo "|declare -A substitutions=()"
            return
          fi                    

          replacements=$(jq -r '.["'"$script"'"].substitutions[] | "\(.pattern)|\(.value)"' "$intent_data_file")
          while IFS="|" read -r pattern out; do
            if [[ -n "$pattern" && "$text" =~ $pattern ]]; then
              original="''${BASH_REMATCH[0]}"
              [[ -z "''$original" ]] && continue
              substitutions["''$original"]="$out"
              substitution_applied=true
              text=$(echo "$text" | sed -E "s/\\b$pattern\\b/$out/g")
            fi
          done <<< "$replacements"      
          echo -n "$text"
          echo "|$(declare -p substitutions)"
        }
        
        trigram_similarity() {
          local str1="$1"
          local str2="$2"
          declare -a tri1 tri2 # generate trigrams
          for ((i=0; i<''${#str1}-2; i++)); do
            tri1+=( "''${str1:i:3}" )
          done
          for ((i=0; i<''${#str2}-2; i++)); do
            tri2+=( "''${str2:i:3}" )
          done
          local matches=0
          for t in "''${tri1[@]}"; do
            [[ " ''${tri2[*]} " == *" $t "* ]] && ((matches++))
          done
          local total=$(( ''${#tri1[@]} + ''${#tri2[@]} ))
          (( total == 0 )) && echo 0 && return
          echo $(( 100 * 2 * matches / total ))  # 0-100 scale
        }       
        levenshtein_similarity() {
          local a="$1" b="$2"
          local len_a=''${#a} len_b=''${#b}
          local max_len=$(( len_a > len_b ? len_a : len_b ))   
          (( max_len == 0 )) && echo 100 && return     
          local dist=$(levenshtein "$a" "$b")
          local score=$(( 100 - (dist * 100 / max_len) ))         

          [[ "''${a:0:1}" == "''${b:0:1}" ]] && score=$(( score + 10 ))
          echo $(( score > 100 ? 100 : score ))
        }
        
        for f in "$MATCHER_DIR"/*.sh; do [[ -f "$f" ]] && source "$f"; done
        scripts_ordered_by_priority=()
          for f in "$MATCHER_DIR"/*.sh; do
          script=$(basename "$f" .sh)
          scripts_ordered_by_priority+=("$script")
        done
        dt_info "Scripts: ''${scripts_ordered_by_priority[*]}"
        find_best_fuzzy_match() {
          local input="$1"
          local best_score=0
          local best_match=""
          local normalized=$(echo "$input" | tr '[:upper:]' '[:lower:]' | tr -d '[:punct:]')
          local candidates
          mapfile -t candidates < <(jq -r '.[] | .[] | "\(.script):\(.sentence)"' "$YO_FUZZY_INDEX")
          dt_debug "Found ''${#candidates[@]} candidates for fuzzy matching"
          for candidate in "''${candidates[@]}"; do
            IFS=':' read -r script sentence <<< "$candidate"
            local norm_sentence=$(echo "$sentence" | tr '[:upper:]' '[:lower:]' | tr -d '[:punct:]')
            local tri_score=$(trigram_similarity "$normalized" "$norm_sentence")
            (( tri_score < 30 )) && continue
            local score=$(levenshtein_similarity "$normalized" "$norm_sentence")  
            if (( score > best_score )); then
              best_score=$score
              best_match="$script:$sentence"
              dt_info "New best match: $best_match ($score%)"
            fi
          done
          if [[ -n "$best_match" ]]; then
            echo "$best_match|$best_score"
          else
            echo ""
          fi
        }
           
        # Exact matching
        exact_match_handler() {        
          for script in "''${scripts_ordered_by_priority[@]}"; do
            resolved_output=$(resolve_entities "$script" "$text")
            resolved_text=$(echo "$resolved_output" | cut -d'|' -f1)
            dt_debug "Tried: match_''${script} '$resolved_text'"

            subs_decl=$(echo "$resolved_output" | cut -d'|' -f2-)
            declare -gA substitutions || true
            eval "$subs_decl" >/dev/null 2>&1 || true

            if match_$script "$resolved_text"; then      
              if [[ "$(declare -p substitutions 2>/dev/null)" =~ "declare -A" ]]; then
                for original in "''${!substitutions[@]}"; do
                  dt_debug "Substitution: $original >''${substitutions[$original]}";
                  [[ -n "$original" ]] && dt_info "$original > ''${substitutions[$original]}"
                done
              fi
              args=()
              for arg in "''${cmd_args[@]}"; do
                dt_debug "ADDING PARAMETER: $arg"
                args+=("$arg")
              done
         
              # Final product
              paramz="''${args[@]}" && echo
              echo "exact" > "$match_result_flag" # Tell fuzzy handler we're done

              # Display              
              echo "   ┌─(yo-$script)"
              echo "   │🦆"
              if [ ''${#args[@]} -eq 0 ]; then
                echo "   └─🦆 says ⮞ no parameters yo"
              else
                for ((i=0; i<''${#args[@]}; i+=2)); do
                  if [ $i -eq 0 ]; then
                    echo -n "   └─⮞ "
                  else
                    echo -n "   └─⮞ "
                  fi
                  echo -n "''${args[$i]}"
                  if [ $((i+1)) -lt ''${#args[@]} ]; then
                    echo " ''${args[$((i+1))]}"
                  else
                    echo
                  fi
                done
              fi
              dt_debug "Executing: yo $script $paramz" 
              
              # Execute!
              exec "yo-$script" "''${args[@]}"   
              return 0
            fi         
          done

          dt_info "Exact: No exact match found"
          echo "exact_finished" > "$match_result_flag"
        }        

        # No matching script
        no_match() {
          local end_time=$(date +%s%3N)
          local elapsed_ms=$((end_time - start_time))
          local elapsed_sec=$((elapsed_ms / 1000))
          local elapsed_ms_remainder=$((elapsed_ms % 1000))
          if (( elapsed_sec > 0 )); then
            echo "   ┌─(yo-do)"
            echo "   │🦆 qwack?! $text"
            echo "   │🦆 says ⮞ fuck ❌ no match!"
            echo "   └─⏰ do took ''${elapsed_sec}.''${elapsed_ms_remainder} s"
          else
            echo "   ┌─(yo-do)"
            echo "   │🦆 qwack!? $text" 
            echo "   │🦆 says ⮞ fuck ❌ no match!"
            echo "   └─⏰ do took ''${elapsed_ms}ms"
          fi
        }


        # Fuzzy handler                
        fuzzy_match_handler() {
          resolved_output=$(resolve_entities "dummy" "$text")
          resolved_text=$(echo "$resolved_output" | cut -d'|' -f1)
          fuzzy_result=$(find_best_fuzzy_match "$resolved_text")
          [[ -z "$fuzzy_result" ]] && return 1

          IFS='|' read -r combined match_score <<< "$fuzzy_result"
          IFS=':' read -r matched_script matched_sentence <<< "$combined"
          if (( match_score < FUZZY_THRESHOLD )); then
            dt_debug "Fuzzy match score $match_score below threshold $FUZZY_THRESHOLD, skipping."
            return 1
          fi
          dt_debug "Best fuzzy script: $matched_script (score: $match_score%)"

          # Resolve entities agein - this time for matched script
          resolved_output=$(resolve_entities "$matched_script" "$text")
          resolved_text=$(echo "$resolved_output" | cut -d'|' -f1)
          subs_decl=$(echo "$resolved_output" | cut -d'|' -f2-)
          declare -gA substitutions || true
          eval "$subs_decl" >/dev/null 2>&1 || true


          if match_fuzzy_$matched_script "$resolved_text" "$matched_sentence"; then
            if [[ "$(declare -p substitutions 2>/dev/null)" =~ "declare -A" ]]; then
              for original in "''${!substitutions[@]}"; do
                dt_debug "Substitution: $original >''${substitutions[$original]}";
                [[ -n "$original" ]] && dt_info "$original > ''${substitutions[$original]}"
              done
            fi
            args=()
            for arg in "''${cmd_args[@]}"; do
              dt_debug "ADDING PARAMETER: $arg"
              args+=("$arg")
            done

            dt_debug "Fuzzy handler: Waiting for exact match to finish..."
            while [[ $(cat "$match_result_flag") == "waiting" ]]; do
              dt_debug "Fuzzy: Still waiting for exact match flag... (loop)"
              sleep 0.05
            done
            dt_debug "Fuzzy: Exact match flag found"

            if [[ $(cat "$match_result_flag") == "exact" ]]; then 
              dt_debug "Exact match already handled execution. Fuzzy exiting."             
              exit 0
            fi    
            dt_debug "Fuzzy: Proceeding with fuzzy execution..."

            paramz="''${args[@]}" && echo
            echo "   ┌─(yo-$matched_script)"
            echo "   │🦆 Fuzzy"
            if [ ''${#args[@]} -eq 0 ]; then
              echo "   └─🦆 says ⮞ no parameters yo"
            else
              for ((i=0; i<''${#args[@]}; i+=2)); do
                if [ $i -eq 0 ]; then
                  echo -n "   └─⮞ "
                else
                  echo -n "   └─⮞ "
                fi
                echo -n "''${args[$i]}"
                if [ $((i+1)) -lt ''${#args[@]} ]; then
                  echo " ''${args[$((i+1))]}"
                else
                  echo
                fi
              done
            fi
            dt_info "Executing: yo $matched_script $paramz" 
            
            # Execution 
            exec "yo-$matched_script" "''${args[@]}"
            return 0
          fi
        }        

        # if exact match wins, no need for fuzz matching
        exact_match_handler &
        pid1=$!
        fuzzy_match_handler

        no_match
        say_no_match
        	if [[ $(cat "$match_result_flag") == "exact_finished" ]]; then
          no_match
          say_no_match
        fi
        exit
      '';
    };
    
    
   
    tests = {
      description = "Test user defined sentences using Bash"; 
      category = "🗣️ Voice";
      logLevel = "INFO";
      parameters = [
        { name = "input"; description = "Text to test as a single  sentence test"; optional = true; }
        { name = "stats"; type = "bool"; description = "Flag to display voice commands information like generated regex patterns, generated phrases and ratio"; optional = true; }    
      ];
      code = ''    
        ${commonHelpers}
        set +u
        
        intent_data_file="/etc/yo/intent-data.json"
        scripts=()
        for f in "$MATCHER_DIR"/*.sh; do
          script=$(basename "$f" .sh)
          scripts+=("$script")
        done
        passed_positive=0
        total_positive=0
        passed_negative=0
        total_negative=0
        passed_boundary=0
        failures=()     
        
        resolve_entities() {
          local script="$1"
          local text="$2"
          local replacements
          local pattern out
          declare -A substitutions

          has_lists=$(jq -e '."'"$script"'"?.substitutions | length > 0' "$intent_data_file" 2>/dev/null || echo false)
          if [[ "$has_lists" != "true" ]]; then
            echo -n "$text"
            echo "|declare -A substitutions=()"
            return
          fi                    

          replacements=$(jq -r '.["'"$script"'"].substitutions[] | "\(.pattern)|\(.value)"' "$intent_data_file")
          while IFS="|" read -r pattern out; do
            if [[ -n "$pattern" && "$text" =~ $pattern ]]; then
              original="''${BASH_REMATCH[0]}"
              [[ -z "''$original" ]] && continue
              substitutions["''$original"]="$out"
              substitution_applied=true
              text=$(echo "$text" | sed -E "s/\\b$pattern\\b/$out/g")
            fi
          done <<< "$replacements"      
          echo -n "$text"
          echo "|$(declare -p substitutions)"
        }
        
        resolve_sentence() {
          local script="$1" sentence="$2"
          local lists_json
          lists_json=$(jq -c ".\"$script\".lists // {}" "$intent_data_file" 2>/dev/null || echo "{}")
          local parameters=($(grep -oP '{\K[^}]+' <<< "$sentence"))
          for param in "''${parameters[@]}"; do
            local is_wildcard=$(jq -r --arg p "$param" '.[$p].wildcard // false' <<< "$lists_json")
            local replacement
            if [[ "$is_wildcard" == "true" ]]; then
              if [[ "$param" =~ hour|minute|second ]]; then
                replacement="1"
              elif [[ "$param" =~ room|device ]]; then
                replacement="livingroom"
              else
                replacement="test"
              fi
            else
              replacement=$(jq -r --arg p "$param" '.[$p].values[0].out // ""' <<< "$lists_json")
              [[ -z "$replacement" ]] && replacement="unknown"
            fi
            sentence="''${sentence//\{$param\}/$replacement}"
          done
          sentence=$(echo "$sentence" | sed -E 's/\([^)]+\)/test/g; s/\[[^]]+\]//g; s/[|]//g; s/  +/ /g; s/^ //; s/ $//')
          echo "$sentence"
        }
        
        if [[ -n "$input" ]]; then
            echo "[🦆📜] Testing single input: '$input'"
            FUZZY_THRESHOLD=15
            YO_FUZZY_INDEX="/etc/yo/fuzzy-index.json"
            scripts_ordered_by_priority=()
            for f in "$MATCHER_DIR"/*.sh; do
              script=$(basename "$f" .sh)
              scripts_ordered_by_priority+=("$script")
            done

            for f in "$MATCHER_DIR"/*.sh; do [[ -f "$f" ]] && source "$f"; done
            find_best_fuzzy_match() {
              local input="$1"
              local best_score=0
              local best_match=""
              local normalized=$(echo "$input" | tr '[:upper:]' '[:lower:]' | tr -d '[:punct:]')
              local candidates
              mapfile -t candidates < <(jq -r '.[] | .[] | "\(.script):\(.sentence)"' "$YO_FUZZY_INDEX")
              dt_debug "Found ''${#candidates[@]} candidates for fuzzy matching"
              for candidate in "''${candidates[@]}"; do
                IFS=':' read -r script sentence <<< "$candidate"
                local norm_sentence=$(echo "$sentence" | tr '[:upper:]' '[:lower:]' | tr -d '[:punct:]')
                local tri_score=$(trigram_similarity "$normalized" "$norm_sentence")
                (( tri_score < 30 )) && continue
                local score=$(levenshtein_similarity "$normalized" "$norm_sentence")  
                if (( score > best_score )); then
                  best_score=$score
                  best_match="$script:$sentence"
                  dt_info "New best match: $best_match ($score%)"
                fi
              done
              if [[ -n "$best_match" ]]; then
                echo "$best_match|$best_score"
              else
                echo ""
              fi
            }
            test_single_input() {
                local input="$1"
                dt_info "Testing input: '$input'"
                for script in "''${scripts_ordered_by_priority[@]}"; do
                    resolved_output=$(resolve_entities "$script" "$input")
                    resolved_text=$(echo "$resolved_output" | cut -d'|' -f1)
                    dt_debug "Trying exact match: $script '$resolved_text'" 
                    if match_$script "$resolved_text"; then
                        dt_info "✅ EXACT MATCH: $script"
                        dt_info "Parameters:"
                        for arg in "''${cmd_args[@]}"; do
                            dt_info "  - $arg"
                        done
                        return 0
                    fi
                done
                dt_info "No exact match found. Attempting fuzzy match..."
                fuzzy_result=$(find_best_fuzzy_match "$input")
                if [[ -z "$fuzzy_result" ]]; then
                    dt_info "❌ No fuzzy candidates found"
                    return 1
                fi  
                IFS='|' read -r combined match_score <<< "$fuzzy_result"
                IFS=':' read -r matched_script matched_sentence <<< "$combined"
                dt_info "Best fuzzy candidate: $matched_script (score: $match_score%)"
                dt_info "Matched sentence: '$matched_sentence'"
                resolved_output=$(resolve_entities "$matched_script" "$input")
                resolved_text=$(echo "$resolved_output" | cut -d'|' -f1)
                if match_fuzzy_$matched_script "$resolved_text" "$matched_sentence"; then
                    dt_info "✅ FUZZY MATCH ACCEPTED: $matched_script"
                    dt_info "Parameters:"
                    for arg in "''${cmd_args[@]}"; do
                        dt_info "  - $arg"
                    done
                    return 0
                else
                    dt_info "❌ Fuzzy match rejected (parameter resolution failed)"
                    return 1
                fi
            }
            test_single_input "$input"
            exit $?
        fi
    

        test_positive_cases() {
          for script in "''${scripts[@]}"; do
            echo "[🦆📜] Testing script: $script"

    
            mapfile -t raw_sentences < <(jq -r ".\"$script\".sentences[]?" "$intent_data_file" 2>/dev/null)

            dt_debug "found ''${#raw_sentences[@]} sentences for $script"
            for template in "''${raw_sentences[@]}"; do
              test_sentence=$(resolve_sentence "$script" "$template")
              echo " Testing: $test_sentence"
              resolved_output=$(resolve_entities "$script" "$test_sentence")
              resolved_text=$(echo "$resolved_output" | cut -d'|' -f1)
              subs_decl=$(echo "$resolved_output" | cut -d'|' -f2-)
              declare -gA substitutions || true
              eval "$subs_decl" >/dev/null 2>&1 || true
              if match_$script "$resolved_text"; then
                say_duck "yay ✅ PASS: $resolved_text"
                ((passed_positive++))
              else
                say_duck "fuck ❌ FAIL: $resolved_text"
                failures+=("POSITIVE: $script | $resolved_text")
              fi
              ((total_positive++))
            done
          done
        }
        test_negative_cases() {
          echo "[🦆🚫] Testing Negative Cases"
          negative_cases=(
            "make me a sandwich"
            "launch the nuclear torpedos!"
            "gör mig en macka"
            "avfyra kärnvapnen!"
            "ducks sure are the best dont you agree"
          )        
          for neg_case in "''${negative_cases[@]}"; do
            echo " Testing: $neg_case"
            matched=false
            for script in "''${scripts[@]}"; do
              resolved_output=$(resolve_entities "$script" "$neg_case")
              resolved_neg=$(echo "$resolved_output" | cut -d'|' -f1)     
              if match_$script "$resolved_neg"; then
                say_duck "fuck ❌ FALSE POSITIVE: $resolved_neg (matched by $script)"
                failures+=("NEGATIVE: $script | $resolved_neg")
                matched=true
                break
              fi
            done       
            if ! $matched; then
              say_duck "yay ✅ [NEG] PASS: $resolved_neg"
              ((passed_negative++))
            fi
            ((total_negative++))
          done
        }
        test_boundary_cases() {
          echo "[🦆🔲] Testing Boundary Cases"
          boundary_cases=("" "   " "." "!@#$%^&*()")  
          for bcase in "''${boundary_cases[@]}"; do
            printf " Testing: '%s'\n" "$bcase"
            matched=false   
            for script in "''${scripts[@]}"; do
              if match_$script "$bcase"; then
                say_duck "fuck ❌ BOUNDARY FAIL: '$bcase' (matched by $script)"
                failures+=("BOUNDARY: $script | '$bcase'")
                matched=true
                break
              fi
            done       
            if ! $matched; then
              say_duck "yay ✅ [BND] PASS: '$bcase'"
              ((passed_boundary++))
            fi
          done
          total_boundary=''${#boundary_cases[@]}
        }  
        test_positive_cases
        test_negative_cases
        test_boundary_cases
        
        total_tests=$((total_positive + total_negative + total_boundary))
        passed_tests=$((passed_positive + passed_negative + passed_boundary))
        percent=$(( 100 * passed_tests / total_tests ))
        

        if [ "$percent" -ge 80 ]; then 
            color="$GREEN" && duck_report="⭐"
        elif [ "$percent" -ge 60 ]; then 
            color="$YELLOW" && duck_report="🟢"
        else 
            color="$RED" && duck_report="😭"
        fi
        
        # Display report
        if [ "$passed_tests" -ne "$total_tests" ]; then 
            if [ ''${#failures[@]} -gt 0 ]; then
                echo "" && echo -e "''${RED}## ────── FAILURES ──────##''${RESET}"
                for failure in "''${failures[@]}"; do
                    echo -e "''${RED}## ❌ $failure"
                done
                echo -e "''${RED}## ────── FAILURES ──────##''${RESET}"
            fi
        fi
        
        
        echo "" && echo -e "''${color}"## ──────⋆⋅☆⋅⋆────── ##''${RESET}"
        bold "Testing completed!" 
        say_duck "Positive: $passed_positive/$total_positive"
        say_duck "Negative: $passed_negative/$total_negative"
        say_duck "Boundary: $passed_boundary/$total_boundary"
        say_duck "TOTAL: $passed_tests/$total_tests (''${color}''${percent}%''${GRAY})"
        echo "''${RESET}" && echo -e "''${color}## ──────⋆⋅☆⋅⋆────── ##''${RESET}"
        say_duck "$duck_report"
        dt_info "Test completed with results: $passed_tests/$total_tests ''${percent}%"
        exit 1
      '';
    };
 
  };}
