# **Yo!**

[![Sponsors](https://img.shields.io/github/sponsors/QuackHack-McBlindy?logo=githubsponsors&label=Sponsor&style=flat&labelColor=ff1493&logoColor=fff&color=rgba(234,74,170,0.5) "")](https://github.com/sponsors/QuackHack-McBlindy) [![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-Sponsor?style=flat&logo=buymeacoffee&logoColor=fff&labelColor=ff1493&color=ff1493)](https://buymeacoffee.com/quackhackmcblindy)


`yo` is:  
- *50%* **Nix: compile-time grammar compiler**  
- *50%* **Rust: run-time deterministic interpreter with some optional fuzz on top**    

   
It takes declarative sentence templates with optional parameters and entity lists, expands them into all possible variants generates optimized regular expressions. <br>
This can easily create a combinational explosion - this should be concidered a **feature! Users should define their sentences to get the perfect exploision!**, because at runtime Rust can leverage very high accuracy gain at the cost of extremely low speed reduction. *(see stack overflow - then you pushed it too hard)* <br>
It takes input, runs it through exact and fuzzy matching against the pre‑compiled patterns, extracts any parameter, and executes the corresponding script  with those arguments – effectively translating plain‑language commands into system shell actions.


`yo` is a **full-stack voice assistant** that's:  
- **Very Fast** - Pre-compiled indexing, smartt priority ordering & Rust high performance makes it super fast.  
- **Lightweight** - CLI can be used using only `pkgs.jq` and `pkgs.coreutils`.  
- **Simple** - Bash or Rust - Everything neatly packaged and runs on single port.  
- **Safe** - Rule based, user defines the rules. Strong validation supported.    
- **Offline** - No internet required after setup.
- **Easy to deploy** - Using the NixOS flake.  

<br>

`yo` is **NOT**:    
- **❌ An LLM with shell access!**  

<br>

## **Runtime Example**  

Thanks to fuzzy parameter resolution, not a single word needs to be correct for `yo` to find and execute the right script.  

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
      language       = "sv"; # "en" by default
      model          = "base";
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

> **Note:** models are automatically downloaded at compile-time. Just remember to set a language in the server configuration.  


<br>



## **2. Usage**

<details><summary><strong>
Example configuration
</strong></summary>

Full usage example:  

```nix
  services.yo-rs = {
    port = "12345";
    openFirewall = true;
  
    server = {
      enable         = true;
      shellTranslate = true;     # true = executes yo scripts
      language       = "sv";     # controls the transcription language + TTS model
      whisper        = "medium"; # (tiny, base, small, medium, large) 
      threshold      = 0.8;      # wake word detection trigger threshold
      beamSize       = 0;        # 0 = greedy (often faster)
      temperature    = 0.2;      # can reduce hallucinations
      threads        = 4;        # CPU threads, increase for speed
      ttsSpeed       = 1.3M #
      
      # additional optional settings:
      # host                  = "0.0.0.0";
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
      uri              = "192.168.1.111"; # servert ip (leave unchanged when server & client on same host) 
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
  
  yo = {
    legacy = false;          # set to true to run using Bash
    SplitWords = [ "also" ]; # used for chaining commands
    sorryPhrases = [         # TTS when failing
      "Det låter som du har en köttebulle i käften. Ät klart middagen och försök sedan igen."
      "Vad fan säger du för något?"
      "Prata som en människa snälla"
    ];
  };
     
```

<br>

</details>


<details><summary><strong>
Example yo.script.<name>.voice definition
</strong></summary>

You can see real yo.scripts in [./examples](https://github.com/QuackHack-McBlindy/yo/tree/main/examples) directory.  

```nix
    yo.script.timer.voice = {
      priority = 1;
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
          { "in" = "[länge|kvar]"; out = "true"; }
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
Commandline usage
</strong></summary>

**Natural Language Command**  

Exact matches are blazing fast. 
Fyzzy matching has great coverage/accuracy.  

Run `yo --help` to see all your defined yo scripts as a table.    

To get the **perfect combinational explosion** - it's best practice to check the `--help` command for the script your writing voice commands for to see how many patterns and phrases you are actually generating:  

```bash
🦆🏠  HOME via 🐍 via 🦀 v1.98.0 
16:29:42 ❯ yo timer -h

   🚀🦆 yo timer                                                              
                                                                              
  Set a timer                                                                 
  Usage:  yo timer [OPTIONS]                                                  
                                                                              
  ## Parameters                                                               
                                                                              
  ...
  
  ## Voice Commands                                                           
                                                                              
  Patterns: 921                                                              
  Phrases: 262010985                                                          

  ...  
```

<br>

**Patterns to Phrases ratio:**  

```
921
----------- ≈ 0.000003515
262,010,985​
```

That means:  
**1** pattern for every **284,485** phrases.  
As a percentage: **0.0003515%**     


There is a actually a sweet spot based on logic here, it's recommend to experiment around until you find it.  


**Text-To-Speech**  

If you would run for example:  

```bash
yo say "this is my spoken text"
```

From your yo server, you would hear `this is my spoken text` on all your clients.  

<br>

**Sentence Testing**  

You can do quite extensive tests for your voice commands:    

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

For inspiration, view my [/bin](https://github.com/QuackHack-McBlindy/dotfiles/tree/main/bin) - which has voice scripts that ranges between easy to advanced usage.  

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

