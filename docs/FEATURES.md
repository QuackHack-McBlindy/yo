# **Key Features**


### **Pattern Matching Engine**

Dual-layer system with pre-compiled regex for exact matches and Levenshtein-based fuzzy matching as fallback.  

Automatic parameter resolution.  

Supports command chaining by splitting patterns with pre-defined word in the module option.  


### **Declarative Pattern Definition**

All command patterns and variants defined in Nix.  

Build-time pattern expansion eliminates runtime regex compilation.  

Prioritization by weight, complexity, and lexicographic order.  


### **Signature-Based Fuzzy Index**

Pre-computed, word-order–independent signatures for accelerated fuzzy lookup.  

Optimized for large-scale command sets and voice variations.  


### **Centralized Script Management**

Define all your scripts in one place with consistent structure, eliminating scattered scripts across your system.  

Unified --help command, Markdown rendered beautifully in the terminal that have extensive parameter documentation.  


### **Parameter & Entity System**

Type validation, optional parameters, default values, allowed values, and both positional & named parameter support.  

Entity resolution maps natural phrases to canonical flags or arguments.  

**Three Parameter Types:**    

{param} - Required parameters with entity resolution  

(option1|option2) - Required alternative  

[optional|words] - Optional components  


### **Extensive Sentence Testing Framework**

Generates test cases by expanding sentence patterns with optional words and alternatives.  

Validates both exact and fuzzy matching against defined voice commands.  

Verifies command recognition accuracy, handles parameter extraction, and provides detailed statistics about voice command coverage and performance.  


### **Conflict-Free Validation**

Build-time assertion checks prevent overlapping or ambiguous sentence definitions.  

Detects prefix and duplicate conflicts before deployment.  


### **Statistical Learning**

Tracks match success rates, fuzzy distance effectiveness, and failure patterns.  

Feeds data back for tuning and pattern optimization.  


### **Automated Execution**

Schedule scripts to run at boot, periodically, or specific times with systemd integration.  

### **Smart Validation**

Comprehensive error checking with friendly duck error messages and parameter validation.  


### **yo --help**


<img src="https://quackhack-mcblindy.github.io/blog/img/yo-help.png" width="200px"/>

<br>

<img src="https://quackhack-mcblindy.github.io/blog/img/yo-script-help.png" width="200px"/>

<br>


# **What Does All THis Mean?**

It means that you can say for example:  

*"Update the flake and rebuild the system and deploy dad's media server and wait 5 minutes and check for errors at dad's media server"*   
