
[![Sponsors](https://img.shields.io/github/sponsors/QuackHack-McBlindy?logo=githubsponsors&label=Sponsor&style=flat&labelColor=ff1493&logoColor=fff&color=rgba(234,74,170,0.5) "")](https://github.com/sponsors/QuackHack-McBlindy) [![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-Sponsor?style=flat&logo=buymeacoffee&logoColor=fff&labelColor=ff1493&color=ff1493)](https://buymeacoffee.com/quackhackmcblindy)

# **It's Nix & deterministic, `yo`!**

`yo` is:
- **Nix: compile-time command-language compiler & verifier**  
- **Rust: deterministic run-time interpreter, matcher & dispatcher**  
- **Lightweight: Legacy CLI requires only `pkgs.bash` + `pkgs.jq` & `pkgs.coreutils`!**   

``` 
🦆🏠  HOME via 🐍 via 🦀 v1.98.0 took 1m31s 
03:36:35 ❯ yo do "seetlt ao tiimezrr fobor twoz hourazs ninre minuotes twentyonz<e secondips"
   ┌─(yo-timer-en)
   │🦆 qwack!? seetlt ao tiimezrr fobor twoz hourazs ninre minuotes twentyonz<e secondips
   └─⮞ --hours 2
   └─⮞ --minutes 9
   └─⮞ --seconds 21
   └─⏰ do took 52.417625ms
{
  "status": "ok",
  "timer_id": 1
}
```

<br>

**Nix Build Time**  
▶ declarative command definitions  
▶ grammar expansion  
▶ parameter/entity expansion  
▶ pattern & phrase generation  
▶ command index generation  
▶ conflict detection  
▶ test generation  
▶ compile-time verification  


>  **Rust Run Time**  
>  At runtime, `yo do` normalizes the input and concurrently evaluates exact and fuzzy matches against the pre-compiled command index.  
>  Exact matching always takes precedence; the fuzzy matcher waits for the exact result before it is allowed to dispatch a command.  
>  Once a match is selected, parameters are extracted and the corresponding `yo` script is dispatched with those arguments.  


`yo` is a **full-stack voice assistant** that's:  
- **Very Fast** - Pre-compiled indexes, priority-ordered exact matching, parallel fuzzy evaluation & Rust performance.  
- **Simple** - Everything neatly packaged and runs on a single port.  
- **Safe** - Rule based, user defines the rules. Strong validation included.     
- **Configurable** - Optimize fuzzy threshold per script.   
- **Offline** - No internet required after setup.  
- **Ready** - Voice commands are exact/fuzzy tested for conflicts before service starts.  
- **Deployable** - 100% reproducible using the NixOS flake.  


<br>

`yo` is **NOT**:    
- **❌ An LLM with shell access!**  

<br>

  
## **1. Installation**

<details><summary><strong>
❄️ Using flakes
</strong></summary>

 

#### **Add yo as an input in your flake**

```nix
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    yo.url = "github:quackhack-mcblindy/yo";
  };
```


#### **Import the yo module into your configuration**  
  

```nix
  imports = [ yo.nixosModules.yo ];
```

> **Note:** the module also requires `self` and `inputs` as module arguments. Pass them to your `nixosSystem` via `specialArgs`:

```nix
  nixosSystem {
    specialArgs = { inherit self inputs; };
    ...
  }
```

<br>


#### **Enable the service**  


Example of a minimal server + client service configuration (view `2. Usage` for a full configuration).  

```nix
  services.yo-rs = {  
    server = {
      enable         = true;
      language       = "swedish"; # "english" by default
      whisper        = "base";
      shellTranslate = true;  
    };  
    client.enable = true;
  };
```

<br>


#### **Rebuild your system**  

```nix
$ sudo nixos-rebuild switch --flake /path/to/flake ...
```

**Done!**  
  
Now you can speak your wake word *(default: `"yo bitch"`)*  
& ask what time it is.  
*or if you prefer CLI:*  

```bash
❄️ DOTFILES  on  main [$!+]  
✦ 07:17:33 ❯ yo do "what time is it"
   ┌─(yo-time)
   │🦆 qwack!? what time is it 
   └─🦆 says ⮞ no parameters yo
   └─⏰ do took 183.835µs
07:17
```

Approx: `~0.184 ms`  

*But if you don't like Rust, or have a basic setup you can use Bash (Which only depends on `pkgs.jq` and `pkgs.coreutils`) instead by setting:*  

```nix
yo.legacy = true;
```


</details>


<br>


**`yo` uses ONNX Runtime for text-to-speech inference and wake-word detection.**  
**GGML-based bin models from the Whisper family is used for speech-to-text.**  

> **Note:** models are automatically fetched by Nix. Just remember to set a language in the server configuration.  


<br>


## **2. Usage**

<details><summary><strong>
Service configuration
</strong></summary>

Full usage example:  

```nix
  services.yo-rs = {
    port = 12345;
    openFirewall = true;
  
    server = {
      enable         = true;
      shellTranslate = true;     # true = executes yo scripts
      language       = "swedish";     # controls the transcription language + TTS model (default = `"english"`)
      whisper        = "medium"; # (tiny, base, small, medium, large) 
      threshold      = 0.8;      # wake word detection trigger threshold
      beamSize       = 0;        # 0 = greedy (often faster)
      temperature    = 0.2;      # can reduce hallucinations
      threads        = 4;        # CPU threads, increase for speed
      ttsSpeed       = 1.3;      # text-to-speech length-scale
      
      # additional optional settings:
      # host                  = "0.0.0.0:12345";
      # wakeWordPath          = "/path/to/custom/model.onnx";
      # awakeSound            = "/path/to/custom/awake.wav";
      # doneSound             = "/path/to/custom/done.wav";
      # failSound             = "/path/to/custom/fail.wav";
      # debug                 = true;
      # logFile               = "/path/to/custom/log/path/yo-rs-server.log";
    };
    
    # Microphone client (streams audio - RMS based VAD)
    client = {
      enable           = true;            # enables microphone streaming to server
      uri              = "192.168.1.111"; # server ip (leave unchanged when server & client on same host) 
      room             = "livingroom";
      silenceThreshold = 0.03;
      silenceTimeout   = 1.5;
      maxDuration      = 5.0; # max recording in seconds before sending
      
      # awakeSound         = "/path/to/custom/awake.wav";
      # doneSound          = "/path/to/custom/done.wav";
      # failSound          = "/path/to/custom/fail.wav";
      # awakeCmd           = "notify-send 'Wake word detected'";
      # doneCmd            = "mpg123 /path/to/success.mp3";
      # failCmd            = "mpg123 /path/to/success.mp3";      
      # debug              = true;
      # logFile            = "/path/to/custom/log/path/yo-rs-client.log";
    };
  };    
```

<br>

</details>


<details><summary><strong>
Yo configuration
</strong></summary>

Most of the options are baked into the service or scripts, but there are a couple of options:   

```nix
  yo = {
    fuzzy = {
      enable = false;        # disable fuzzy globally
      threshold = 0.9;       # global runtime threshold
      conflict = {
        detection = false;   # detect near-duplicate sentences at build-time
        threshold = 80;      # build-time Jaccard percentage (0–100)
      };
    };  
    legacy = false;          # set to true to run using Bash
    splitWords = [ "also" ]; # used for chaining commands
    sorryPhrases = [         # TTS when failing
      "Buddy, you are speaking Japanese, I dont understand anything."
      "I'm sorry, I did not understand that"
      "Sorry, can you repeat that"
      "I did not quite catch that"
      "Excuse me?!"
    ];
  };
```

<br>

</details>

<details><summary><strong>
Script configuration
</strong></summary>


You can see real yo.scripts in the [./examples](https://github.com/QuackHack-McBlindy/yo/tree/main/examples) directory.  

```nix
yo.scripts.timer = {
  description = "What this script does";
  category = "Home Automation";       # used for grouping in `yo --help`
  aliases = [ "tim" ];                     # alternative CLI names
  autoStart = false;                      # start at boot? (requires defaults for required parameters)
  runEvery = "55";                       # run periodically (systemd timer)
  runAt = [ "08:00" "20:00" ];            # run at specific times daily
  logLevel = "INFO";                      # DEBUG, INFO, WARNING, ERROR, CRITICAL
  helpFooter = "Additional help text";
  parameters = [  
    { name = "minutes"; type = "int"; description = "Minutes to set the timer on"; default = 0;  }     
    { name = "seconds"; type = "int"; description = "Seconds to set the timer on"; default = 0; }     
    { name = "hours"; type = "int"; description = "Hours to set the timer on"; default = 0; }
    { name = "list"; type = "bool"; description = "Lists active timers"; default = false;  }
    { name = "sound"; type = "path"; description = "Soundfile to be played on finished timer"; default = "/path/to/finished.wav"; }
  ];
  code = ''
      SOUNDFILE="$sound"
      HOURS="$hours"
      MINUTES="$minutes"
      SECONDS="$seconds"

      LOGFILE_DIR="/tmp/yo-timers"
      mkdir -p "$LOGFILE_DIR"

      if [ "$list" = "true" ]; then
        timers=()
        counter=1

        if ls "$LOGFILE_DIR"/*.pid >/dev/null 2>&1; then
          for pidfile in "$LOGFILE_DIR"/*.pid; do
            pid=$(basename "$pidfile" .pid)
            if ps -p "$pid" >/dev/null 2>&1; then
              end_time=$(awk '{print $2}' "$pidfile")
              remaining=$((end_time - $(date +%s)))
              if [ $remaining -gt 0 ]; then
                hours_left=$((remaining / 3600))
                minutes_left=$(((remaining % 3600) / 60))
                seconds_left=$((remaining % 60))
                finish_time=$(date -d @$end_time +'%H:%M:%S')
                timers+=("{\"id\":$pid,\"counter\":$counter,\"target\":\"$finish_time\",\"hours_left\":$hours_left,\"minutes_left\":$minutes_left,\"seconds_left\":$seconds_left}")
                counter=$((counter + 1))
              fi
            else
              rm -f "$pidfile"
            fi
          done
        fi

        if [ ''${#timers[@]} -eq 0 ]; then
          echo '{"timers":[]}'
        else
          printf '{"timers":[%s]}\n' "$(IFS=,; echo "''${timers[*]}")"
        fi
        exit 0
      fi
      
      TIMER_TOTAL=$((HOURS * 3600 + MINUTES * 60 + SECONDS))
      DURATION=$TIMER_TOTAL
      TIMER_MINUTES=$((DURATION / 60))
   
      start_time=$(date +%s)
      end_time=$((start_time + DURATION))

      (
        while [ $(date +%s) -lt $end_time ]; do
          now=$(date +%s)
          remaining=$((end_time - now))
          echo -ne "Time remaining: ''${remaining}s\r"
          sleep 1
        done

        echo -e "\n\e[1;5;31m[TIMER FINISHED]\e[0m"
        rm -f "$LOGFILE_DIR/$$.pid"


        if [ -f "$SOUNDFILE" ]; then
          for i in {1..10}; do
            aplay "$SOUNDFILE" >/dev/null 2>&1
          done
          sleep 15
          for i in {1..8}; do
            aplay "$SOUNDFILE" >/dev/null 2>&1
          done
        else
          echo "Sound file not found: $SOUNDFILE"
        fi
      ) > /tmp/yo-timer.log 2>&1 &
      pid=$!
      echo "$pid $end_time" > "$LOGFILE_DIR/$pid.pid"
      disown "$pid"
  '';
  # or use a pre-built binary:
  # binary = /path/to/executable;  
};

```

<br>

</details>

<details><summary><strong>
Voice configuration
</strong></summary>

```nix
(these|are|alternative|words)  
[these|are|optional|words]  
{parameters}
```

You can see real yo.scripts in the [./examples](https://github.com/QuackHack-McBlindy/yo/tree/main/examples) directory.  

```nix
  yo.scripts.timer = {
    voice = {
      priority = 1;           # (1-5) 5 is priorities last
      fuzzy.enabled = true;   # script specific
      fuzzy.threshold = 0.8;  # script specific 
      sentences = [
        "(skapa|ställ|sätt|starta) [en] (time|timer|timern) [på] {hours} (timme|timmar) {minutes} (minut|minuter) {seconds} (sekund|sekunder)"
        "(skapa|ställ|sätt|starta) [en] (time|timer|timern) [på] {minutes} (minut|minuter) [och] {seconds} (sekund|sekunder)"
        "(skapa|ställ|sätt|starta) [en] (time|timer|timern) [på] {minutes} (minut|minuter)"                     
        "(skapa|ställ|sätt|starta) [en] (time|timer|timern) [på] {seconds} sekunder"      
        
        "hur {list} är det kvar på (time|timer|timern)"
        "tid {list} på (time|timer|timern)"
        "när {list} (time|timer|timern)"
      ];        
      lists = {
        list.values = [
          { "in" = "länge|kvar"; out = "true"; }
        ];
        seconds.values = builtins.concatLists (builtins.genList (
                i: let n = i + 1; in [
                  { "in" = toString n; out = toString n; }     
                  { "in" = swedishNumber n; out = toString n; }
                ]
              ) 60);
              minutes.values = builtins.concatLists (builtins.genList (
                i: let n = i + 1; in [
                  { "in" = toString n; out = toString n; }
                  { "in" = swedishNumber n; out = toString n; }
                ]
              ) 60);
              hours.values = builtins.concatLists (builtins.genList (
                i: let n = i + 1; in [
                  { "in" = toString n; out = toString n; }
                  { "in" = swedishNumber n; out = toString n; }
                ]
              ) 24);
        };
      }; 
    };
```


<br>


</details>


<details><summary><strong>
Compile-time sentence conflict evaluation
</strong></summary>

All checks are pure Nix assertions – if a conflict is found, `nixos-rebuild` fails and a helpful error message is shown.  

```bash
          200|     if failedAssertions != [ ] then
          201|       throw "\nFailed assertions:\n${concatStringsSep "\n" (map (x: "- ${x}") failedAssertions)}"
             |       ^
          202|     else

       error:
       Failed assertions:
       - Sentence conflicts detected in voice definition:

       🦆 says ⮞ CONFLICT!
         Pattern "set a reminder for {time} to {task}"
         In scripts: calendar_event, reminderr

       🦆 says ⮞ fix da conflicts before rebuildin' yo!
```

<br>

**Fuzzy Conflict Detection**

**Jaccard Similarity** compares two sentences by looking at their sets of words (tokens). It’s calculated as:  

`similarity = (number of shared words) / (total unique words in both sentences)`  

The result is a percentage.  


> **Example:**  
`"play music in the living room"` vs `"play radio in the living room"`  
Shared words: `play, in, the, living, room` (5)  
Unique words total: `play, music, in, the, living, room, radio` (7)  
Similarity = **5 / 7 ≈ 71%**

<br>

```nix
{
  yo.fuzzy.conflict.detection = true; # default: false
  yo.fuzzy.conflict.threshold = 70;   # default: 80
}
```

Will enable the fuzzy conflict detection and configure its sensitivity value.  
It's disabled by default as it *(of course)* increases the duration of user rebuilds, but is quite useful for testing.  


```bash
          200|     if failedAssertions != [ ] then
          201|       throw "\nFailed assertions:\n${concatStringsSep "\n" (map (x: "- ${x}") failedAssertions)}"
             |       ^
          202|     else

       error:
       Failed assertions:
       - 🦆 duck say ⮞ fuck ❌ Fuzzy index may contain near-duplicate sentences (token similarity > 70%):
         'play music in the living room' (play_music) vs 'play radio in the living room' (play_radio) [71%]
```

<br>

</details>

<details><summary><strong>
Commandline
</strong></summary>

**Natural Language Command**  

Exact matches are blazing fast. 
Fuzzy matching has great coverage/accuracy.  

Adding `\?` at the end of your command will run it with `DEBUG` logging.  

Run `yo --help` to see all your defined yo scripts as a table.    

`yo <script> --help` shows the generated patterns and phrases for the defined voice commands.  
The ratio could be a good way to measure potential combinatorial explosion as you can see below.  

```bash
❄️ DOTFILES  on  main [!] 
00:41:44 ❯ yo tv -h
  ...                                                                           
  ## Voice Commands                                                           
                                                                              
  Patterns: 245                                                               
  Phrases: 1608                                                               
  Ratio: 6                                                                              
```

```bash
❄️ DOTFILES  on  main [!] 
00:41:52 ❯ yo timer -h
  ...                                                                                                                                
  ## Voice Commands                                                           
                                                                              
  Patterns: 921                                                               
  Phrases: 262010985                                                          
  Ratio: 284485
```

<br>

> **Note:** for **legacy** that timer script becomes **6.66 MB**, while for Rust version only a kilobytes.    

<br>

**Text-To-Speech**  

If you would run for example:  

```bash
yo say "this is my spoken text"
```

From your yo server, you would hear `this is my spoken text` on all connected client's speakers.  

<br>

**Runtime Sentence Testing**  

Runtime sentence testing is also supported.      

```bash
yo tests
``` 

If you have many voice commands it's advised to provide a maximum variants parameter for the tests:  

```bash
yo tests --max-variants 50
# or if you want to test single script 
yo tests --script <name> --max-variants 200 
```

<br>

</details>


## **Further reading**

Learn how to write your own voice commands in the [examples/](https://github.com/QuackHack-McBlindy/yo/tree/main/examples)  

For inspiration, view my [/bin](https://github.com/QuackHack-McBlindy/dotfiles/tree/main/bin) - which has voice scripts that range from easy to advanced usage.   

Read about the fuzzy matching logic in the [docs/](https://github.com/QuackHack-McBlindy/yo/tree/main/docs/FUZZ.md)  

Read more about the feature set in the [docs/](https://github.com/QuackHack-McBlindy/yo/tree/main/docs/FEATURES.md)  

<br>

## **Sponsor My Work**

[![Sponsors](https://img.shields.io/github/sponsors/QuackHack-McBlindy?logo=githubsponsors&label=Sponsor&style=flat&labelColor=ff1493&logoColor=fff&color=rgba(234,74,170,0.5) "")](https://github.com/sponsors/QuackHack-McBlindy) [![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-Sponsor?style=flat&logo=buymeacoffee&logoColor=fff&labelColor=ff1493&color=ff1493)](https://buymeacoffee.com/quackhackmcblindy)
> 🦆🧑‍🦯 says ⮞ Hi! I'm QuackHack-McBlindy!  
> Like my work?  
> Buy me a coffee, or become a sponsor.  
> Thanks for supporting open source/hungry developers ♥️🦆!   

♥️₿ *Wallet:* `pungkula.x`  
<a href="https://www.buymeacoffee.com/quackhackmcblindy" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

<br>


## **License**

**MIT**  <br>
Contributions are welcomed.

