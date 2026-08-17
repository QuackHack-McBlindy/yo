# **Yo!**

[![Sponsors](https://img.shields.io/github/sponsors/QuackHack-McBlindy?logo=githubsponsors&label=Sponsor&style=flat&labelColor=ff1493&logoColor=fff&color=rgba(234,74,170,0.5) "")](https://github.com/sponsors/QuackHack-McBlindy) [![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-Sponsor?style=flat&logo=buymeacoffee&logoColor=fff&labelColor=ff1493&color=ff1493)](https://buymeacoffee.com/quackhackmcblindy)


`yo` is:  
- *50%* **Nix: compile-time grammar compiler**  
- *50%* **Rust: run-time deterministic interpreter with some fuzziness on top**    

   
It takes declarative sentence templates with optional parameters and entity lists, expands them into all possible variants, generates optimized regular expressions. <br>
At runtime it takes input, runs it through exact and fuzzy matching against the pre‑compiled patterns, extracts any parameter, and executes the corresponding script  with those arguments – effectively translating plain‑language commands into system shell actions.



`yo` is a **full-stack voice assistant** that's:  
- **Very Fast** - Pre-compiled indexing, smartt priority ordering & Rust high performance makes it super fast.  
- **Lightweight** - Very few dependencies.  
- **Simple** - Everything neatly packaged and runs on one port.  
- **Safe** - Rule based, user defines the rules.  
- **Offline** - No internet required after setup.  
- **Easy to deploy** - Using the NixOS module.  

<br>

`yo` is **NOT**:    
- **❌ An LLM with shell access!**  

<br>

## **Runtime Example**  

Thanks to fuzzy parameter resolution, not a single word needs to be correct for it to find and execute the right script.  

``` 
🦆🏠  HOME via 🐍 via 🦀 
16:03:13 ❯ yo do "seetlt ao tiimezrr fobor twoz hourazs ninre minuotes twentyonz<e secondips"
   ┌─(yo-timer)
   │🦆 qwack!? seetlt ao tiimezrr fobor twoz hourazs ninre minuotes twentyonz<e secondips
   └─⮞ --hours 2
   └─⮞ --minutes 9
   └─⮞ --seconds 21
   └─⏰ do took 283.959385ms
```

<br>
  
## **Installation**

<details><summary><strong>
❄️ Using flakes (recommended)
</strong></summary>

Use `yo` as voice assistant in 4 steps:  
  

#### **1: Add yo as an input in your flake.nix**

```nix
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    yo.url = "github:quackhack-mcblindy/yo";
  };
```


#### **2: Import the yo module into your configuration**  
  

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


#### **3: Enable the services**  

```nix
services.yo-rs = {
  # Handles Wake-word detection/Transcription/Shell execution/Text-to-speech generation
  server = {
    enable         = true;
    shellTranslate = true;

    # Optional settings:
    # host                  = "0.0.0.0:12345";
    # wakeWordPath          = "/path/to/custom/model.onnx";
    # threshold             = 0.8;
    # awakeSound            = "/path/to/custom/awake.wav";
    # doneSound             = "/path/to/custom/done.wav";
    # failSound             = "/path/to/custom/fail.wav";
    # whisperModelPath      = "/path/to/custom/ggml-model.bin";
    # textToSpeechModelPath = "/path/to/custom/tts/model.onnx";
    # language              = "sv";
    # beamSize              = 5;
    # temperature           = 0.2;
    # threads               = 4;
    # debug                 = true;
    # logFile               = "/path/to/custom/log/path/yo-rs-server.log";

    # You can use Home Assistant's intent handler instead:
    # execCommand = ''
    #   curl -X POST "http://HOME_ASSISTANT_IP:8123/api/conversation/process" \
    #   -H "Authorization: Bearer YOUR_LONG_LIVED_ACCESS_TOKEN" \
    #   -H "Content-Type: application/json" \
    #   -d "{\"text\":\"$1\",\"language\":\"sv\"}"
    # '';
  };

  # Microphone client (streams audio - RMS based VAD)
  client = {
    enable = true;   # starts the microphone client

    # Optional settings:
    # uri                = "192.168.1.111:12345";
    # awakeSound         = "/path/to/custom/awake.wav";
    # doneSound          = "/path/to/custom/done.wav";
    # failSound          = "/path/to/custom/fail.wav";
    # awakeCmd           = "notify-send 'Wake word detected'";
    # doneCmd            = "mpg123 /path/to/success.mp3";
    # silenceThreshold   = 0.03;
    # silenceTimeout     = 1.5;
    # debug              = true;
    # logFile            = "/path/to/custom/log/path/yo-rs-client.log";
  };
};
```


<br>


> **Note:** the server and the generated scripts call `piper`, `ffmpeg` and `aplay` from `PATH`. Add them to your packages — in nixpkgs the TTS engine is `piper-tts` (do not use `pkgs.piper`, which is the gaming-mouse GUI): `environment.systemPackages = [ pkgs.piper-tts pkgs.ffmpeg pkgs.alsa-utils ];`

#### **4: Rebuild your system**  

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

*But if you don't like Rust, or have a basic setup you can use Bash instead by setting:*  

```nix
yo.legacy = true;
```

 
Which only relies on `pkgs.jq` and `pkgs.coreutils`.


</details>


<br>

**`yo` uses ONNX Runtime for text-to-speech inference and wake-word detection.**  
**GGML-based bin models from the Whisper family is used for speech-to-text.**  

Run the following command to download a tiny GGML model and `amy` an `en_US` TTS model:  
    
```
mkdir -p "$HOME/models/stt" && mkdir -p "$HOME/models/tts"
curl -L -o "$HOME/models/stt/ggml-tiny.bin" \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin"
curl -L -o "$HOME/models/tts/en_US-amy-medium.onnx" \
    "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx"
curl -L -o "$HOME/models/tts/en_US-amy-medium.onnx.json" \
    "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx.json"    
```

<br>

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

