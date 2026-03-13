# **Writing voice commands**

Brief explaination of how to define your voice sentences for scripts you want to activate by voice.  
You can include as many parameters as you like – they will be passed to your script automatically.     


* Alternative words or phrases - atleast one must be used
  * `(red|green|blue)`  
  * `turn(s|ed|ing)`
* Optional words or phrases - may be omitted
  * `[the]`  
  * `[this|that]`  
  * `light[s]`
* Parameters - unless `wildcard = true`, the spoken value must match an "in" entry in the corresponding list, and the script receives the "out" value.
  * `{brightness}`
  * `{color}`
  * `{search}`

<br>

**Example:**

```ǹix
  yo.scripts.<name> = {
    description = "describe your script"
    parameters = [   
      { 
        name = "state";
        type = "string";
        description = "State of the device or room";
        values = [ "ON" "OFF" ]; # optional: limits to only these values
      }    
      { 
        name = "device";
        description = "Device to control";
        optional = true;
      }
      { 
        name = "room";
        description = "Room to target";
        optional = true;
      }        
	  { 
	    name = "brightness";
	    description = "Brightness value (1-100)";
	    optional = true;
	    type = "int";
	  }
    ];
    code ''
      # parameters can then be used
      # $state, $device, and so on
    '';
    voice = {
      enabled = true;
      priority = 2;
      sentences = [
        "turn {state} the light in {room}"
        "set {device} to {brightness} percent"
      ];
      lists = {
		state.values = [
		  { "in" = "[on|activate]"; out = "ON"; }             
		  { "in" = "off"; out = "OFF"; } 
		];
		device.wildcard = true; # will match anything		
		room.values = [
		  { "in" = "livingroom"; out = "livingroom"; }             
		  { "in" = "kitchen"; out = "kitchen"; } 
		];
		brightness.range = {
          from = 1;
          to = 100;
          multiplier = 1;
        };  
      };
    };  
  };  
```

<br>

**Pro tip**

There are built‑in assertions that detect sentence conflicts and poorly configured voice intents at build-time.
Once system has been rebuilt, you can test all your sentences througly by running:  

```bash
$ yo tests
```

