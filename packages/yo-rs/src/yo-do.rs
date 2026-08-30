#![allow(dead_code)]
#![allow(unused)]
use std::{
    env,
    fs::{OpenOptions, File},
    io::{self, Write},
    sync::Once,
    collections::HashMap,
    process::{Command, exit},
    time::Instant,
};
use ducktrace_logger::*;

use std::fs;
use regex::Regex;
use serde::{Deserialize, Serialize};

use futures_util::{SinkExt, StreamExt};
use serde_json::Value;
use std::sync::Arc;
use tokio::sync::Mutex;

const DEFAULT_SPLIT_WORDS_PATH: &str = "/etc/yo/split-words.json";
const DEFAULT_SORRY_PHRASES_PATH: &str = "/etc/yo/sorry-phrases.json";
const DEFAULT_INTENT_DATA_PATH: &str = "/etc/yo/intent-data.json";
const DEFAULT_FUZZY_INDEX_PATH: &str = "/etc/yo/fuzzy-index.json";


struct CliArgs {
    input: Option<String>,
    fuzzy: i32,
    room: Option<String>,
}

#[derive(Clone)]
struct CompiledPattern {
    regex: Regex,
    param_names: Vec<String>,
    script_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct MemoryContext {
    last_action: String,
    active_servers: Vec<String>,
    environment: String,
    user_preferences: HashMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct CommandHistory {
    recent_commands: Vec<RecentCommand>,
    confirmed_matches: HashMap<String, u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RecentCommand {
    script: String,
    args: String,
    matched_sentence: String,
    match_type: String,
    timestamp: String,
    confirmed: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct MemoryData {
    context: MemoryContext,
    history: CommandHistory,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ScriptConfig {
    description: String,
    aliases: Vec<String>,
    category: String,
    log_level: String,
    auto_start: bool,
    parameters: Vec<Parameter>,
    help_footer: String,
    code: String,
    voice: Option<VoiceConfig>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Parameter {
    name: String,
    description: String,
    optional: bool,
    param_type: Option<String>,
    default: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct VoiceConfig {
    enabled: bool,
    priority: i32,
    #[serde(default)]
    speak: bool,
    sentences: Vec<String>,
    lists: HashMap<String, ListConfig>,    
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RangeConfig {
    r#type: String,
    from: f64,
    to: f64,
    multiplier: f64,
}


#[derive(Debug, Clone, Serialize, Deserialize)]
struct ListConfig {
    #[serde(default)]
    wildcard: bool,
    values: Vec<ListValue>,
    #[serde(default)]
    range: Option<RangeConfig>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct EntityValue {
    #[serde(rename = "in")]
    r#in: String,
    out: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)] 
struct EntityList {
    wildcard: Option<bool>,
    values: Vec<EntityValue>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct VoiceData {
    sentences: Vec<String>,
    lists: HashMap<String, EntityList>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ScriptIntentData {
    substitutions: Vec<Substitution>,
    sentences: Vec<String>,
    voice_data: Option<HashMap<String, VoiceData>>,
}  

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ListValue {
    #[serde(rename = "in")]
    r#in: String,
    out: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct IntentData {
    substitutions: Vec<Substitution>,
    sentences: Vec<String>,
    lists: HashMap<String, ListConfig>,  
    #[serde(default)]
    speak: bool,
}    

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Substitution {
    pattern: String,
    value: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct FuzzyIndexEntry {
    script: String,
    sentence: String,
    signature: String,
    #[serde(default = "default_fuzzy_threshold")]
    fuzzy_threshold: f32,
    #[serde(default = "default_fuzzy_enabled")]
    fuzzy_enabled: bool,
}

fn default_fuzzy_threshold() -> f32 { 0.8 }
fn default_fuzzy_enabled() -> bool { true }

#[derive(Debug, Clone)]
struct ScriptPriority {
    name: String,
    priority: i32,
    has_complex_patterns: bool,
}

#[derive(Debug)]
struct MatchResult {
    script_name: String,
    args: Vec<String>,
    matched_sentence: String,
    processing_time: std::time::Duration,
    match_type: String,
}

#[derive(Clone)]     
struct YoDo {
    intent_data: HashMap<String, IntentData>,
    fuzzy_index: Vec<FuzzyIndexEntry>,
    fuzzy_entity_dict: HashMap<String, HashMap<String, Vec<EntityMapping>>>,
    processing_order: Vec<ScriptPriority>,
    fuzzy_threshold: i32,
    debug: bool,
    memory_data: MemoryData,  
    split_words: Vec<String>,
    sorry_phrases: Vec<String>,
    compiled_patterns: HashMap<String, Vec<CompiledPattern>>,
}

#[derive(Debug, Clone, Deserialize)]
struct EntityMapping {
    input: String,
    output: String,
}

impl YoDo {
    fn new() -> Self {
        let split_words = load_split_words();
        let sorry_phrases = load_sorry_phrases();
        let memory_data = Self::load_memory_data().unwrap_or_else(|_| {
            MemoryData {
                context: MemoryContext {
                    last_action: "".to_string(),
                    active_servers: Vec::new(),
                    environment: "default".to_string(),
                    user_preferences: HashMap::new(),
                },
                history: CommandHistory {
                    recent_commands: Vec::new(),
                    confirmed_matches: HashMap::new(),
                },
            }
        });
    
        Self {
            intent_data: HashMap::new(),
            fuzzy_index: Vec::new(),
            fuzzy_entity_dict: HashMap::new(),
            processing_order: Vec::new(),
            fuzzy_threshold: 15,
            debug: env::var("DEBUG").is_ok() || env::var("DT_DEBUG").is_ok(),
            memory_data,
            split_words,
            sorry_phrases,
            compiled_patterns: HashMap::new(),
        }
    }

    fn log_intent_time(&self, ms: u128) -> io::Result<()> {
        let home = env::var("HOME").unwrap_or_else(|_| ".".to_string());
        let dir = format!("{}/.config/yo", home);
        let file_path = format!("{}/exec.txt", dir);
        std::fs::create_dir_all(&dir)?;

        let mut sum: u128 = 0;
        let mut count: u64 = 0;
        let mut entries = Vec::new();

        if let Ok(content) = std::fs::read_to_string(&file_path) {
            for line in content.lines().skip(1) {
                let trimmed = line.trim();
                if let Some(num_str) = trimmed.strip_suffix(" ms") {
                    if let Ok(num) = num_str.parse::<u128>() {
                        sum += num;
                        count += 1;
                        entries.push(trimmed.to_string());
                    }
                }
            }
        }

        sum += ms;
        count += 1;
        entries.push(format!("{} ms", ms));

        let average = if count > 0 { sum as f64 / count as f64 } else { 0.0 };
        let header = format!("{:.2} ms average ({} entries)", average, count);
        let mut output = header + "\n";
        for entry in &entries {
            output.push_str(entry);
            output.push('\n');
        }
        std::fs::write(&file_path, output)?;
        Ok(())
    }

    fn normalize_input(input: &str) -> String {
        input.replace(['?', '!', '.', ',', '&', '/', '\''], "").to_lowercase().split_whitespace().collect::<Vec<_>>().join(" ")
    }

    fn is_param_token(word: &str) -> Option<&str> {
        if word.starts_with('{') && word.ends_with('}') {
            Some(&word[1..word.len() - 1])
        } else { None }
    }

    fn align_words(&self, pattern: &[String], text: &[String]) -> Vec<Option<usize>> {
        let p_len = pattern.len();
        let t_len = text.len();

        let mut dp = vec![vec![0usize; t_len + 1]; p_len + 1];

        for i in 0..=p_len {
            dp[i][0] = i;
        }
        for j in 0..=t_len {
            dp[0][j] = j;
        }

        for i in 1..=p_len {
            for j in 1..=t_len {
                let cost = if Self::is_param_token(&pattern[i - 1]).is_some() {
                    0
                } else if pattern[i - 1].eq_ignore_ascii_case(&text[j - 1]) {
                    0
                } else { 1 };

                dp[i][j] = (dp[i - 1][j] + 1)
                    .min(dp[i][j - 1] + 1)
                    .min(dp[i - 1][j - 1] + cost);
            }
        }


        let mut alignment = vec![None; p_len];
        let (mut i, mut j) = (p_len, t_len);

        while i > 0 && j > 0 {
            let cost = if Self::is_param_token(&pattern[i - 1]).is_some() {
                0
            } else if pattern[i - 1].eq_ignore_ascii_case(&text[j - 1]) {
                0
            } else { 1 };

            if dp[i][j] == dp[i - 1][j - 1] + cost {
                alignment[i - 1] = Some(j - 1);
                i -= 1;
                j -= 1;
            } else if dp[i][j] == dp[i - 1][j] + 1 {
                i -= 1;
            } else { j -= 1; }
        }

        while i > 0 { i -= 1; }

        alignment
    }

    fn fuzzy_resolve_entity(
        &self,
        script_name: &str,
        param_name: &str,
        value: &str,
        threshold: i32,
    ) -> Option<String> {
        let param_dict = self.fuzzy_entity_dict
            .get(script_name)?
            .get(param_name)?;

        let normalized_value = value.to_lowercase();
        let mut best_score = 0;
        let mut best_output = None;

        for mapping in param_dict {
            let input = &mapping.input.to_lowercase();
            let distance = self.levenshtein_distance(&normalized_value, input);
            let max_len = normalized_value.len().max(input.len());
            if max_len == 0 {
                continue;
            }
            let score = 100 - (distance * 100 / max_len) as i32;
            if score >= threshold && score > best_score {
                best_score = score;
                best_output = Some(mapping.output.clone());
            }
        }

        if let Some(ref out) = best_output {
            dt_debug(&format!(
                "      Fuzzy entity match ({}%): {} → {}",
                best_score, value, out
            ));
        }
        best_output
    }

    fn load_fuzzy_entity_dict(&mut self, path: &str) -> Result<(), Box<dyn std::error::Error>> {
        let data = fs::read_to_string(path)?;
        self.fuzzy_entity_dict = serde_json::from_str(&data)?;
        dt_debug(&format!(
            "🦆 Loaded fuzzy entity dict for {} scripts",
            self.fuzzy_entity_dict.len()
        ));
        Ok(())
    }

    fn is_wildcard_param(&self, script_name: &str, param_name: &str) -> bool {
        self.intent_data
            .get(script_name)
            .and_then(|intent| intent.lists.get(param_name))
            .map(|list| list.wildcard)
            .unwrap_or(false)
    }
    
    fn is_valid_param_value(&self, script_name: &str, param_name: &str, value: &str) -> bool {
        if self.is_wildcard_param(script_name, param_name) {
            return true;
        }

        if let Some(intent) = self.intent_data.get(script_name) {
            if let Some(list) = intent.lists.get(param_name) {
                if !list.values.is_empty() {
                    return list.values.iter().any(|v| v.out.as_str() == value);
                }
            }
        }
        true
    }
    
    fn load_memory_data() -> Result<MemoryData, Box<dyn std::error::Error>> {
        let stats_dir = std::env::var("HOME").unwrap_or_else(|_| ".".to_string()) + "/.local/share/yo/stats";
    
        let context_path = format!("{}/current_context.json", stats_dir);
        let context: MemoryContext = if let Ok(file) = std::fs::File::open(&context_path) {
            serde_json::from_reader(file).unwrap_or_else(|_| MemoryContext {
                last_action: "".to_string(),
                active_servers: Vec::new(),
                environment: "default".to_string(),
                user_preferences: HashMap::new(),
            })
        } else {
            MemoryContext {
                last_action: "".to_string(),
                active_servers: Vec::new(),
                environment: "default".to_string(),
                user_preferences: HashMap::new(),
            }
        };
    
        let history_path = format!("{}/command_history.json", stats_dir);
        let history: CommandHistory = if let Ok(file) = std::fs::File::open(&history_path) {
            serde_json::from_reader(file).unwrap_or_else(|_| CommandHistory {
                recent_commands: Vec::new(),
                confirmed_matches: HashMap::new(),
            })
        } else {
            CommandHistory {
                recent_commands: Vec::new(),
                confirmed_matches: HashMap::new(),
            }
        }; 
        Ok(MemoryData { context, history })
    }

    fn log_failed_command(&self, input: &str, fuzzy_candidates: &[(String, String, i32)]) -> Result<(), Box<dyn std::error::Error>> {
        let stats_dir = std::env::var("HOME").unwrap_or_else(|_| ".".to_string()) + "/.local/share/yo/stats";
        let _ = std::fs::create_dir_all(&stats_dir);
        
        let log_file = format!("{}/failed_commands.log", stats_dir);
        let stats_file = format!("{}/command_stats.json", stats_dir);
        
        let timestamp = chrono::Local::now().format("%Y-%m-%d %H:%M:%S");
        let log_entry = format!("[{}] FAILED: '{}'\n", timestamp, input);
        
        if let Ok(mut file) = std::fs::OpenOptions::new().create(true).append(true).open(&log_file) {
            use std::io::Write;
            let _ = file.write_all(log_entry.as_bytes());
        }
        
        let mut stats: serde_json::Value = if let Ok(content) = std::fs::read_to_string(&stats_file) {
            serde_json::from_str(&content).unwrap_or_else(|_| {
                serde_json::json!({
                    "failed_commands": {},
                    "successful_commands": {},
                    "fuzzy_matches": {}
                })
            })
        } else {
            serde_json::json!({
                "failed_commands": {},
                "successful_commands": {}, 
                "fuzzy_matches": {}
            })
        };
        
        if let Some(failed_commands) = stats.get_mut("failed_commands").and_then(|v| v.as_object_mut()) {
            let count = failed_commands.get(input).and_then(|v| v.as_u64()).unwrap_or(0);
            failed_commands.insert(input.to_string(), serde_json::Value::from(count + 1));
        }
        
        if let Ok(content) = serde_json::to_string_pretty(&stats) {
            let _ = std::fs::write(&stats_file, content);
        }
        
        if !fuzzy_candidates.is_empty() {
            dt_debug(&format!("Fuzzy candidates for '{}':", input));
            for (script, sentence, score) in fuzzy_candidates {
                dt_debug(&format!("  {}%: {} -> {}", score, sentence, script));
            }
        }        
        Ok(())
    }


    fn log_successful_command(&self, script_name: &str, args: &[String], processing_time: std::time::Duration) -> Result<(), Box<dyn std::error::Error>> {
        let stats_dir = std::env::var("HOME").unwrap_or_else(|_| ".".to_string()) + "/.local/share/yo/stats";
        let stats_file = format!("{}/command_stats.json", stats_dir);  
        let mut stats: serde_json::Value = if let Ok(content) = std::fs::read_to_string(&stats_file) {
            serde_json::from_str(&content).unwrap_or_else(|_| {
                serde_json::json!({
                    "failed_commands": {},
                    "successful_commands": {},
                    "fuzzy_matches": {}
                })
            })
        } else {
            serde_json::json!({
                "failed_commands": {},
                "successful_commands": {},
                "fuzzy_matches": {}
            })
        }; 
        if let Some(successful_commands) = stats.get_mut("successful_commands").and_then(|v| v.as_object_mut()) {
            let count = successful_commands.get(script_name).and_then(|v| v.as_u64()).unwrap_or(0);
            successful_commands.insert(script_name.to_string(), serde_json::Value::from(count + 1));
        }
        
        if let Ok(content) = serde_json::to_string_pretty(&stats) {
            let _ = std::fs::write(&stats_file, content);
        }     
        Ok(())
    }

    fn load_intent_data(&mut self, intent_data_path: &str) -> Result<(), Box<dyn std::error::Error>> {
        let data = fs::read_to_string(intent_data_path)?;
        self.intent_data = serde_json::from_str(&data)?;
        dt_debug(&format!("🦆 Loaded intent data for {} scripts", self.intent_data.len()));
        Ok(())
    }

    fn load_fuzzy_index(&mut self, fuzzy_index_path: &str) -> Result<(), Box<dyn std::error::Error>> {
        let data = fs::read_to_string(fuzzy_index_path)?;
        self.fuzzy_index = serde_json::from_str(&data)?;
        dt_debug(&format!("🦆 Loaded {} fuzzy index entries", self.fuzzy_index.len()));
        Ok(())
    }
   
    fn precompile_patterns(&mut self) {
        let mut all_patterns: HashMap<String, Vec<CompiledPattern>> = HashMap::new();

        for (script_name, intent) in &self.intent_data {
            let mut patterns_for_script = Vec::new();

            for sentence in &intent.sentences {
                for variant in self.expand_optional_words(sentence) {
                    if let Some((regex, param_names)) = self.build_pattern_matcher(script_name, &variant) {
                        patterns_for_script.push(CompiledPattern {
                            regex,
                            param_names,
                            script_name: script_name.clone(),
                        });
                    }
                }
            }

            if !patterns_for_script.is_empty() {
                all_patterns.insert(script_name.clone(), patterns_for_script);
            }
        }

        self.compiled_patterns = all_patterns;
        dt_debug(&format!("🦆 Precompiled {} pattern groups", self.compiled_patterns.len()));
    }   
   
    fn expand_optional_words(&self, sentence: &str) -> Vec<String> {
        let tokens: Vec<&str> = sentence.split_whitespace().collect();
        let mut variants = Vec::new();
        
        fn generate_combinations(tokens: &[&str], current: Vec<String>, index: usize, result: &mut Vec<String>) {
            if index >= tokens.len() {
                let sentence = current.join(" ").trim().to_string();
                if !sentence.is_empty() {
                    result.push(sentence);
                }
                return;
            }

            let token = tokens[index];
            let mut alternatives = Vec::new();

            if token.starts_with('(') && token.ends_with(')') {
                let clean = &token[1..token.len()-1];
                alternatives.extend(clean.split('|').map(|s| s.to_string()));
            } 
            else if token.starts_with('[') && token.ends_with(']') {
                let clean = &token[1..token.len()-1];
                alternatives.extend(clean.split('|').map(|s| s.to_string()));
                alternatives.push("".to_string());
            } 
            else {
                alternatives.push(token.to_string());
            }

            for alt in alternatives {
                let mut new_current = current.clone();
                if !alt.is_empty() {
                    new_current.push(alt);
                }
                generate_combinations(tokens, new_current, index + 1, result);
            }
        }

        generate_combinations(&tokens, Vec::new(), 0, &mut variants);
        
        variants.iter()
            .map(|v| v.replace("  ", " ").trim().to_string())
            .filter(|v| !v.is_empty())
            .collect()
    }

    fn resolve_entity(&self, script_name: &str, param_name: &str, param_value: &str) -> String {
        if self.is_wildcard_param(script_name, param_name) {
            return param_value.to_string();
        }
    
        if let Some(intent) = self.intent_data.get(script_name) {
            if let Some(list_config) = intent.lists.get(param_name) {
                let normalized_input = param_value.to_lowercase();
    
                for entry in &list_config.values {
                    for alt in entry.r#in.split('|') {
                        if alt.trim().to_lowercase() == normalized_input {
                            dt_debug(&format!("      List match: {} → {}", param_value, entry.out));
                            return entry.out.clone();
                        }
                    }
                }
            }
        }
    

        if let Some(intent) = self.intent_data.get(script_name) {
            let normalized_input = param_value.to_lowercase();
            
            for sub in &intent.substitutions {
                let pattern = sub.pattern.to_lowercase();

                if pattern == normalized_input {
                    dt_debug(&format!("      Exact entity match: {} → {}", param_value, sub.value));
                    return sub.value.clone();
                }

                if pattern.starts_with('(') && pattern.ends_with(')') {
                    let content = &pattern[1..pattern.len()-1];
                    if content == normalized_input {
                        dt_debug(&format!("      Parenthesized entity match: {} → {}", param_value, sub.value));
                        return sub.value.clone();
                    }
                    if pattern.contains('|') {
                        for alt in content.split('|') {
                            if alt.trim() == normalized_input {
                                dt_debug(&format!("      Parenthesized alternative match: {} → {}", param_value, sub.value));
                                return sub.value.clone();
                            }
                        }
                    }
                }
            }

            if let Some(list_config) = intent.lists.get(param_name) {
                if let Some(range_config) = &list_config.range {
                    if let Ok(num) = param_value.parse::<f64>() {
                        let scaled = num * range_config.multiplier;
                        if scaled >= range_config.from && scaled <= range_config.to {
                            dt_debug(&format!("      Range match: {} (scaled to {})", param_value, scaled));
                            if scaled.fract() == 0.0 {
                                return format!("{}", scaled as i64);
                            } else { return format!("{}", scaled); }
                        }
                    }
                }
            }
            dt_debug(&format!("      No entity match found for '{}'", param_value));
        }
        
        if let Some(fuzzy_result) = self.fuzzy_resolve_entity(script_name, param_name, param_value, 70) {
            return fuzzy_result;
        }

        param_value.to_string()
    }
   
    fn build_pattern_matcher(&self, script_name: &str, sentence: &str) -> Option<(Regex, Vec<String>)> {
        let start_time = Instant::now();
        dt_debug(&format!("    Building pattern matcher for: '{}'", sentence));

        let mut regex_parts = Vec::new();
        let mut param_names = Vec::new();
        let mut current = sentence.to_string();

        while let Some(start) = current.find('{') {
            if let Some(end) = current.find('}') {
                let before_param = &current[..start];
                let param = &current[start+1..end];
                let after_param = &current[end+1..];

                if !before_param.is_empty() {
                    let escaped = regex::escape(before_param);
                    regex_parts.push(escaped);
                }

                param_names.push(param.to_string());
                let is_wildcard = self.is_wildcard_param(script_name, param);

                let regex_group = if is_wildcard {
                    dt_debug(&format!("      Wildcard parameter: {}", param));
                    "(.*)".to_string()
                } else {
                    dt_debug(&format!("      Specific parameter: {}", param));
                    let mut lookahead = after_param.to_string();
                    let next_is_wildcard = loop {
                        if let Some(next_start) = lookahead.find('{') {
                            if let Some(next_end) = lookahead.find('}') {
                                let next_param = &lookahead[next_start+1..next_end];
                                if self.is_wildcard_param(script_name, next_param) {
                                    break true;
                                }

                                lookahead = lookahead[next_end+1..].to_string();
                            } else { break false; }
                        } else { break false; }
                    };

                    if next_is_wildcard {
                        r"([^ ]+)".to_string()
                    } else { r"\b([^ ]+)\b".to_string() }
                };

                regex_parts.push(regex_group);
                current = after_param.to_string();
            } else { break; }
        }

        if !current.is_empty() {
            regex_parts.push(regex::escape(&current));
        }

        let regex_pattern = format!("^{}$", regex_parts.join(""));
        
        let build_time = start_time.elapsed();
        dt_debug(&format!("      Final regex: {}", regex_pattern));
        dt_debug(&format!("      Parameter names: {:?}", param_names));
        dt_debug(&format!("      Regex build time: {:?}", build_time));  
        match Regex::new(&regex_pattern) {
            Ok(re) => {
                dt_debug("      Regex compiled successfully");
                Some((re, param_names))
            },
            Err(e) => {
                dt_debug(&format!("🦆 says ⮞ fuck ❌ Regex compilation failed: {}", e));
                None
            },
        }
    }

    fn calculate_processing_order(&mut self) {
        let mut script_priorities = Vec::new();    
        for (script_name, intent) in &self.intent_data {
            let base_priority = 3;
            dt_debug(&format!("Memory context: last_action={}, recent_commands={}", 
                self.memory_data.context.last_action, 
                self.memory_data.history.recent_commands.len()));
    
            let mut adjusted_priority = base_priority;      
            let recent_usage = self.memory_data.history.recent_commands
                .iter()
                .filter(|cmd| cmd.script == *script_name)
                .count();
            adjusted_priority -= recent_usage as i32;
            if self.memory_data.context.last_action == *script_name {
                adjusted_priority -= 2;
                dt_debug(&format!("  Context boost applied for {} (last action)", script_name));
            }        
            let confirmation_key = format!("{}:", script_name);
            let confirmation_count = self.memory_data.history.confirmed_matches
                .keys()
                .filter(|k| k.starts_with(&confirmation_key))
                .count();
            adjusted_priority -= confirmation_count as i32;
            if confirmation_count > 0 {
                dt_debug(&format!("  Confirmation boost: {} patterns confirmed", confirmation_count));
            }
            adjusted_priority = adjusted_priority.max(0);  
            let has_complex_patterns = intent.sentences.iter().any(|s| {
                s.contains('{') || s.contains('[') || s.contains('(')
            });

            script_priorities.push(ScriptPriority {
                name: script_name.clone(),
                priority: adjusted_priority,
                has_complex_patterns,
            });
    
            dt_debug(&format!("MEMORY ADJUSTMENT: {}: base={} → adjusted={} (uses={}, confirms={}, context={})", 
                script_name, base_priority, adjusted_priority, recent_usage, confirmation_count,
                if self.memory_data.context.last_action == *script_name { "YES" } else { "NO" }));
        }

        script_priorities.sort_by(|a, b| {
            a.priority.cmp(&b.priority)
                .then(a.has_complex_patterns.cmp(&b.has_complex_patterns))
                .then(a.name.cmp(&b.name))
        });

        self.processing_order = script_priorities;
        dt_debug(&format!("Final processing order with memory: {:?}", 
            self.processing_order.iter().map(|s| format!("{}[{}]", s.name, s.priority)).collect::<Vec<_>>()));
    }

    fn apply_real_time_substitutions(&self, script_name: &str, text: &str) -> (String, HashMap<String, String>) {
        let mut resolved_text = text.to_lowercase();
        let mut substitutions = HashMap::new();

        if let Some(intent) = self.intent_data.get(script_name) {
            for sub in &intent.substitutions {
                let pattern = format!(r"\b{}\b", regex::escape(&sub.pattern));
                if let Ok(re) = Regex::new(&pattern) {
                    if let Some(original_match) = re.find(&resolved_text) {
                        let original = original_match.as_str().to_string();
                        resolved_text = re.replace_all(&resolved_text, &sub.value).to_string();
                        substitutions.insert(original.clone(), sub.value.clone());
                        dt_debug(&format!("      Real-time sub: {} → {}", original, sub.value));
                    }
                }
            }
        }
        (resolved_text, substitutions)
    }


    fn exact_match(&self, text: &str) -> Option<MatchResult> {
        let global_start = Instant::now();
        let text = text.to_lowercase();
        dt_debug(&format!("Starting EXACT match for: '{}'", text));
    
        for (script_index, script_priority) in self.processing_order.iter().enumerate() {
            let script_name = &script_priority.name;
            dt_debug(&format!(
                "Trying script [{}/{}]: {}",
                script_index + 1,
                self.processing_order.len(),
                script_name
            ));
    
            let (resolved_text, substitutions) =
                self.apply_real_time_substitutions(script_name, &text);
            dt_debug(&format!("After substitutions: '{}'", resolved_text));
    
            if let Some(patterns) = self.compiled_patterns.get(script_name) {
                for pattern in patterns {
                    if let Some(captures) = pattern.regex.captures(&resolved_text) {
                        let mut args = Vec::new();
                        let mut valid_pattern = true;
    
                        for (i, param_name) in pattern.param_names.iter().enumerate() {
                            if let Some(matched) = captures.get(i + 1) {
                                let raw_value = matched.as_str().to_string();
    
                                let entity_resolved =
                                    self.resolve_entity(script_name, param_name, &raw_value);
                                let mut param_value = entity_resolved;
    
                                if let Some(sub) = substitutions.get(&param_value) {
                                    param_value = sub.clone();
                                }
    
                                if !self.is_valid_param_value(script_name, param_name, &param_value) {
                                    dt_debug(&format!(
                                        "Skipping pattern because param '{}' value '{}' is not allowed",
                                        param_name, param_value
                                    ));
                                    valid_pattern = false;
                                    break;
                                }
    
                                args.push(format!("--{}", param_name));
                                args.push(param_value);
                            }
                        }
    
                        if valid_pattern {
                            return Some(MatchResult {
                                script_name: script_name.clone(),
                                args,
                                matched_sentence: text.clone(),
                                processing_time: global_start.elapsed(),
                                match_type: "exact".to_string(),
                            });
                        }
                    }
                }
            }
        }
        None
    }
             
    fn levenshtein_distance(&self, a: &str, b: &str) -> usize {
        let a_chars: Vec<char> = a.chars().collect();
        let b_chars: Vec<char> = b.chars().collect();
        let a_len = a_chars.len();
        let b_len = b_chars.len();

        if a_len == 0 { return b_len; }
        if b_len == 0 { return a_len; }

        let mut matrix = vec![vec![0; b_len + 1]; a_len + 1];

        for i in 0..=a_len { matrix[i][0] = i; }
        for j in 0..=b_len { matrix[0][j] = j; }

        for i in 1..=a_len {
            for j in 1..=b_len {
                let cost = if a_chars[i-1] == b_chars[j-1] { 0 } else { 1 };
                matrix[i][j] = (matrix[i-1][j] + 1)
                    .min(matrix[i][j-1] + 1)
                    .min(matrix[i-1][j-1] + cost);
            }
        }
        matrix[a_len][b_len]
    }

    fn find_best_fuzzy_match(&self, text: &str) -> Option<(String, String, i32)> {
        use rayon::prelude::*;
    
        let normalized_input = text.to_lowercase();
        dt_debug(&format!("Fuzzy matching against {} entries", self.fuzzy_index.len()));
    
        self.fuzzy_index
            .par_iter()
            .filter(|entry| entry.fuzzy_enabled)
            .filter_map(|entry| {
                let normalized_sentence = entry.sentence.to_lowercase();
                let distance = self.levenshtein_distance(&normalized_input, &normalized_sentence);
                let max_len = normalized_input.len().max(normalized_sentence.len());
                if max_len == 0 {
                    return None;
                }
                let score = 100 - (distance * 100 / max_len) as i32;
                let threshold = (entry.fuzzy_threshold * 100.0) as i32;
                if score >= threshold {
                    Some((entry.script.clone(), entry.sentence.clone(), score))
                } else { None }
            })
            .max_by_key(|&(_, _, score)| score)
    }
        
    
    fn fuzzy_match(&self, text: &str) -> Option<MatchResult> {
        dt_debug(&format!("Starting FUZZY match for: '{}'", text));
    
        let (script_name, _sentence, score) = self.find_best_fuzzy_match(text)?;
        dt_info(&format!("Fuzzy match: {} (score: {}%)", script_name, score));
    
        let input_words: Vec<String> = text.split_whitespace().map(|s| s.to_string()).collect();
        let intent = self.intent_data.get(&script_name)?;
    
        for sentence in &intent.sentences {
            for pattern_str in self.expand_optional_words(sentence) {
                let pattern_words: Vec<String> = pattern_str
                    .split_whitespace()
                    .map(|s| s.to_string())
                    .collect();
    
                let alignment = self.align_words(&pattern_words, &input_words);
    
                let mut args = Vec::new();
                let mut valid = true;
    
                for (i, word) in pattern_words.iter().enumerate() {
                    if let Some(param_name) = Self::is_param_token(word) {
                        let raw_value = match alignment[i] {
                            Some(idx) => input_words[idx].clone(),
                            None => {
                                valid = false;
                                break;
                            }
                        };
    
                        let resolved = self.resolve_entity(&script_name, param_name, &raw_value);
                        if !self.is_valid_param_value(&script_name, param_name, &resolved) {
                            valid = false;
                            break;
                        }
    
                        args.push(format!("--{}", param_name));
                        args.push(resolved);
                    }
                }
    
                if valid {
                    return Some(MatchResult {
                        script_name,
                        args,
                        matched_sentence: text.to_string(),
                        processing_time: std::time::Duration::default(),
                        match_type: "fuzzy".to_string(),
                    });
                }
            }
        }
    
        Some(MatchResult {
            script_name,
            args: Vec::new(),
            matched_sentence: text.to_string(),
            processing_time: std::time::Duration::default(),
            match_type: "fuzzy".to_string(),
        })
    }
    
    fn update_memory_context(&self, script_name: &str, args: &[String]) -> Result<(), Box<dyn std::error::Error>> {
        let stats_dir = std::env::var("HOME").unwrap_or_else(|_| ".".to_string()) + "/.local/share/yo/stats";
        let context_path = format!("{}/current_context.json", stats_dir);
        std::fs::create_dir_all(&stats_dir)?;

        let mut context = self.memory_data.context.clone();
        context.last_action = script_name.to_string();

        let mut active_servers = Vec::new();
        for arg in args {
            if arg.contains("dads") || arg == "--server" && args.iter().any(|a| a == "dads") {
                active_servers.push("dads_media_server".to_string());
            }
            if arg.contains("moms") || arg == "--server" && args.iter().any(|a| a == "moms") {
                active_servers.push("moms_media_server".to_string());
            }
        }
        if !active_servers.is_empty() {
            context.active_servers = active_servers;
        }
        if script_name == "deploy" {
            context.environment = "deployment".to_string();
        } else {
            context.environment = "default".to_string();
        }

        let context_json = serde_json::to_string_pretty(&context)?;
        std::fs::write(&context_path, context_json)?;    
        dt_debug(&format!("Updated memory context: last_action={}, environment={}", 
            context.last_action, context.environment));    
        Ok(())
    }    

    fn execute_script(&self, result: &MatchResult) -> Result<(), Box<dyn std::error::Error>> {
        dt_debug(&format!("Executing: yo {} {}", result.script_name, result.args.join(" ")));  
        
        dt_debug!("🦆MEMORY:SCRIPT:{}", result.script_name);
        dt_debug!("🦆MEMORY:ARGS:{}", result.args.join(" "));
        dt_debug!("🦆MEMORY:SENTENCE:{}", result.matched_sentence);
        dt_debug!("🦆MEMORY:TYPE:{}", result.match_type);

        if let Err(e) = self.update_memory_context(&result.script_name, &result.args) {
            dt_debug(&format!("Failed to update memory context: {}", e));
        }
               
        println!("   ┌─(yo-{})", result.script_name);
        let quack = if result.match_type == "exact" {
            "quack!"
        } else { "quack?!" };
        println!("   │ 🦆 {} {}", quack, result.matched_sentence);
        if result.args.is_empty() {
            println!("   └─ 🦆 says ⮞ no parameters yo");
        } else {
            for chunk in result.args.chunks(2) {
                if chunk.len() == 2 {
                    println!("   └─⮞ {} {}", chunk[0], chunk[1]);
                }
            }
        }      
        println!("   └─ ⏰ do took {:?}", result.processing_time);

        let should_speak = self
            .intent_data
            .get(&result.script_name)
            .map(|intent| intent.speak)
            .unwrap_or(false);

        let output = Command::new(format!("yo-{}", result.script_name))
            .args(&result.args)
            .output()?;
    
        if !output.stdout.is_empty() { io::stdout().write_all(&output.stdout)?; }
        if !output.stderr.is_empty() { io::stderr().write_all(&output.stderr)?; }
    
        if !output.status.success() {
            eprintln!("🦆 says ⮞ fuck ❌ Script execution failed with status: {}", output.status);
            return Ok(());
        }
    
        if should_speak {
            let spoken_text = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !spoken_text.is_empty() { self.say(&spoken_text); }
        }
        Ok(())
    }
    

    fn say(&self, text: &str) {
        let _ = std::process::Command::new("yo")
            .arg("say")
            .arg(text)
            .status();
    }

    fn say_no_match(&self) {
        use rand::seq::SliceRandom;
        if let Some(response) = self.sorry_phrases.choose(&mut rand::thread_rng()) {
            self.say(response);
        }
    }
    
    pub fn run(&mut self, input: &str, fuzzy_threshold: i32) -> Result<(), Box<dyn std::error::Error>> {
        let total_start = Instant::now(); 
        self.fuzzy_threshold = fuzzy_threshold;

        if let Ok(memory_data) = Self::load_memory_data() {
            self.memory_data = memory_data;
            dt_debug("🦆 Memory data reloaded for context-aware processing");
        } else { dt_debug("🦆 Using default memory data"); }

        self.calculate_processing_order();
        
        let parts: Vec<&str> = {
            let mut found = false;
            for word in &self.split_words {
                if input.to_lowercase().contains(word) {
                    found = true;
                    break;
                }
            }
            if found {
                let pattern = regex::Regex::new(&self.split_words.join("|")).unwrap();
                pattern.split(input)
                    .map(|part| part.trim())
                    .filter(|part| !part.is_empty())
                    .collect()
            } else { vec![input] }
        };
        
        if parts.len() > 1 {
            dt_debug(&format!("Found {} parts to process: {:?}", parts.len(), parts));
            let mut all_successful = true;
            let mut processed_count = 0;
            
            for (index, part) in parts.iter().enumerate() {
                dt_info(&format!("Processing part {}/{}: '{}'", index + 1, parts.len(), part));
                
                match self.process_single_input(part, total_start) {
                    Ok(_) => {
                        processed_count += 1;
                        dt_debug(&format!("Successfully processed part {}/{}", index + 1, parts.len()));
                    }
                    Err(e) => {
                        all_successful = false;
                        dt_debug(&format!("🦆 says ⮞ fuck ❌ Failed to process part {}: {}", index + 1, e));
                    }
                }
                if index < parts.len() - 1 {
                    std::thread::sleep(std::time::Duration::from_millis(10));
                }
            }
            if processed_count > 0 {
                dt_debug(&format!("Successfully processed {}/{} parts", processed_count, parts.len()));
                return Ok(());
            } else {
                dt_info("🦆 says ⮞ fuck ❌ All parts failed to process");
                std::process::exit(1);
            }
        } else {
            self.process_single_input(parts[0], total_start)
        }
    }
    
    fn process_single_input(&self, input: &str, total_start: Instant) -> Result<(), Box<dyn std::error::Error>> {
        let part_start = Instant::now();
        let normalized = Self::normalize_input(input);
    
        
        let fuzzy_candidates: Vec<(String, String, i32)> = self.fuzzy_index.iter()
            .filter(|entry| entry.fuzzy_enabled)
            .filter_map(|entry| {
                let normalized_input = input.to_lowercase();
                let normalized_sentence = entry.sentence.to_lowercase();
                let distance = self.levenshtein_distance(&normalized_input, &normalized_sentence);
                let max_len = normalized_input.len().max(normalized_sentence.len());
                if max_len == 0 { return None; }
                let score = 100 - (distance * 100 / max_len) as i32;
                let threshold = (entry.fuzzy_threshold * 100.0) as i32;
                if score >= threshold {
                    Some((entry.script.clone(), entry.sentence.clone(), score))
                } else {
                    None
                }
            })
            .collect();
        

    
        let yo_do_clone = self.clone();
        let normalized_clone = normalized.clone();
        let (fuzzy_tx, fuzzy_rx) = std::sync::mpsc::channel();
        let fuzzy_handle = std::thread::spawn(move || {
            let result = yo_do_clone.fuzzy_match(&normalized_clone);
            let _ = fuzzy_tx.send(result);
        });
    
        if let Some(match_result) = self.exact_match(&normalized) {
            let part_elapsed = part_start.elapsed();
            let _ = self.log_intent_time(part_elapsed.as_millis());
            dt_debug(&format!("Exact match found: {}", match_result.script_name));
            let _ = self.log_successful_command(&match_result.script_name, &match_result.args, part_elapsed);
            let final_result = MatchResult {
                script_name: match_result.script_name,
                args: match_result.args,
                matched_sentence: match_result.matched_sentence,
                processing_time: part_elapsed,
                match_type: "exact".to_string(),
            };
            self.execute_script(&final_result)?;
            return Ok(());
        }
    
        if let Ok(Some(match_result)) = fuzzy_rx.recv() {
            let part_elapsed = part_start.elapsed();
            let _ = self.log_intent_time(part_elapsed.as_millis());
            dt_info(&format!("Fuzzy match found: {}", match_result.script_name));
            let final_result = MatchResult {
                script_name: match_result.script_name,
                args: match_result.args,
                matched_sentence: match_result.matched_sentence,
                processing_time: part_elapsed,
                match_type: "fuzzy".to_string(),
            };
            let _ = self.log_successful_command(&final_result.script_name, &final_result.args, final_result.processing_time);
            self.execute_script(&final_result)?;
            return Ok(());
        }
    
        let part_elapsed = part_start.elapsed();
        println!("   ┌─(yo-do)");
        println!("   │ 🦆 qwack! {}", input);
        println!("   │ 🦆 says ⮞ fuck ❌ no match!");
    
        if !fuzzy_candidates.is_empty() {
            let top_candidates: Vec<_> = fuzzy_candidates.iter()
                .filter(|(_, _, score)| *score >= 50)
                .take(3)
                .collect();
    
            for (script, sentence, score) in top_candidates {
                println!("   │   {}%: '{}' -> yo {}", score, sentence, script);
            }
        }
        println!("   └─⏰ do took {:?}", part_elapsed);
    
        self.say_no_match();
    
        dt_debug("No match found for part, logging statistics...");
        let _ = self.log_failed_command(input, &fuzzy_candidates);
        Err("No match found for this part".into())
    }
}

fn load_split_words() -> Vec<String> {
    let path = std::env::var("YO_SPLIT_WORDS")
        .unwrap_or_else(|_| DEFAULT_SPLIT_WORDS_PATH.to_string());
    match fs::read_to_string(&path) {
        Ok(content) => serde_json::from_str(&content).unwrap_or_default(),
        Err(_) => Vec::new(),
    }
}

fn load_sorry_phrases() -> Vec<String> {
    let path = std::env::var("YO_SORRY_PHRASES")
        .unwrap_or_else(|_| DEFAULT_SORRY_PHRASES_PATH.to_string());
    match fs::read_to_string(&path) {
        Ok(content) => serde_json::from_str(&content).unwrap_or_default(),
        Err(_) => Vec::new(),
    }
}



fn parse_args() -> CliArgs {
    let mut args = env::args().skip(1).peekable();
    let mut input = None;
    let mut fuzzy = 25;
    let mut room = None;

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--input" => {
                let value = args.next().expect("Missing value for --input");
                if input.is_some() {
                    eprintln!("🦆 says ⮞ fuck ❌ Duplicate --input provided");
                    std::process::exit(1);
                }
                input = Some(value);
            }
            "--fuzzy" => {
                let value = args.next().expect("Missing value for --fuzzy");
                fuzzy = value.parse().unwrap_or_else(|_| {
                    eprintln!("🦆 says ⮞ fuck ❌ Invalid integer for --fuzzy");
                    std::process::exit(1);
                });
            }
            "--room" => {
                let value = args.next().expect("Missing value for --room");
                if room.is_some() {
                    eprintln!("🦆 says ⮞ fuck ❌ Duplicate --room provided");
                    std::process::exit(1);
                }
                room = Some(value);
            }
            _ => {
                eprintln!("🦆 says ⮞ fuck ❌ Unknown argument: {}", arg);
                std::process::exit(1);
            }
        }
    }

    CliArgs { input, fuzzy, room }
}



fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cli = parse_args();
    let debug = std::env::var("DEBUG").is_ok();
    if debug { std::env::set_var("DT_LOG_LEVEL", "DEBUG"); }
    dt_setup(None, None);
    dt_debug!("Started yo-do!");

    let input = match cli.input {
        Some(i) => i,
        None => {
            eprintln!("🦆 says ⮞ fuck ❌ Missing required argument: --input");
            std::process::exit(1);
        }
    };

    let mut yo_do = YoDo::new();

    let intent_data_path = env::var("YO_INTENT_DATA")
        .unwrap_or_else(|_| DEFAULT_INTENT_DATA_PATH.to_string());
    yo_do.load_intent_data(&intent_data_path)?;
    yo_do.precompile_patterns();

    let fuzzy_entity_path = env::var("YO_FUZZY_ENTITY_DICT")
        .unwrap_or_else(|_| "/etc/yo/fuzzy-entity-dict.json".to_string());
    yo_do.load_fuzzy_entity_dict(&fuzzy_entity_path)?;

    let fuzzy_index_path = env::var("YO_FUZZY_INDEX")
        .unwrap_or_else(|_| DEFAULT_FUZZY_INDEX_PATH.to_string());
    if let Err(e) = yo_do.load_fuzzy_index(&fuzzy_index_path) {
        dt_warning!("Failed to load fuzzy index: {}", e);
    }

    yo_do.run(&input, cli.fuzzy)
}




#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    const TEST_INTENT_JSON: &str = r#"
    {
      "timer": {
        "sentences": [
          "set a timer for {minutes} minutes and {seconds} seconds",
          "start timer {minutes} minutes"
        ],
        "lists": {
          "minutes": { "wildcard": false, "values": [ {"in": "5", "out": "5"}, {"in": "10", "out": "10"} ] },
          "seconds": { "wildcard": false, "values": [ {"in": "30", "out": "30"}, {"in": "45", "out": "45"} ] }
        },
        "substitutions": []
      },
      "reminder": {
        "sentences": [
          "set a reminder for {time} to {task}"
        ],
        "lists": {
          "time": { "wildcard": false, "values": [ {"in": "8am", "out": "08:00"} ] },
          "task": { "wildcard": true, "values": [] }
        },
        "substitutions": []
      },
      "play": {
        "sentences": [
          "play [some] music by {artist}",
          "play {song} by {artist}"
        ],
        "lists": {
          "artist": { "wildcard": false, "values": [] },
          "song": { "wildcard": true, "values": [] }
        },
        "substitutions": [
          { "pattern": "beatles", "value": "beatles_band" },
          { "pattern": "queen", "value": "queen" }
        ]
      }
    }
    "#;

    const TEST_FUZZY_INDEX_JSON: &str = r#"
    [
      {
        "script": "timer",
        "sentence": "set a timer for 5 minutes and 30 seconds",
        "signature": "timer_5_30",
        "fuzzy_threshold": 0.8,
        "fuzzy_enabled": true
      },
      {
        "script": "reminder",
        "sentence": "set a reminder for 8am to buy milk",
        "signature": "reminder_8am_buy milk",
        "fuzzy_threshold": 0.8,
        "fuzzy_enabled": true
      },
      {
        "script": "play",
        "sentence": "play some music by the beatles",
        "signature": "play_beatles",
        "fuzzy_threshold": 0.75,
        "fuzzy_enabled": true
      }
    ]
    "#;

    fn create_test_yodo() -> YoDo {
        let mut yodo = YoDo::new();
        yodo.intent_data = serde_json::from_str(TEST_INTENT_JSON).unwrap();
        yodo.fuzzy_index = serde_json::from_str(TEST_FUZZY_INDEX_JSON).unwrap();
        yodo.precompile_patterns();
        yodo.calculate_processing_order();
        yodo
    }

    struct TempHomeGuard {
        original_home: Option<String>,
        temp_dir: std::path::PathBuf,
    }

    impl TempHomeGuard {
        fn new() -> Self {
            let original_home = std::env::var("HOME").ok();
            let temp_dir = std::env::temp_dir().join(format!(
                "yo_do_test_{}_{}",
                std::process::id(),
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_nanos()
            ));
            std::fs::create_dir_all(&temp_dir).unwrap();
            std::env::set_var("HOME", &temp_dir);
            Self {
                original_home,
                temp_dir,
            }
        }
    }

    impl Drop for TempHomeGuard {
        fn drop(&mut self) {
            if let Some(orig) = &self.original_home {
                std::env::set_var("HOME", orig);
            } else {
                std::env::remove_var("HOME");
            }
            let _ = std::fs::remove_dir_all(&self.temp_dir);
        }
    }

    #[test]
    fn test_levenshtein_distance() {
        let yodo = YoDo::new();
        assert_eq!(yodo.levenshtein_distance("kitten", "sitting"), 3);
        assert_eq!(yodo.levenshtein_distance("", "abc"), 3);
        assert_eq!(yodo.levenshtein_distance("abc", "abc"), 0);
        assert_eq!(yodo.levenshtein_distance("flaw", "lawn"), 2);
    }

    #[test]
    fn test_normalize_input() {
        assert_eq!(YoDo::normalize_input("Hello, World!"), "hello world");
        assert_eq!(YoDo::normalize_input("What's up?"), "whats up");
        assert_eq!(YoDo::normalize_input("  Multiple   Spaces  "), "multiple spaces");
        assert_eq!(YoDo::normalize_input("UPPER lower MiXeD"), "upper lower mixed");
        assert_eq!(YoDo::normalize_input("Punctuation! & symbols/"), "punctuation symbols");
    }

    #[test]
    fn test_expand_optional_words() {
        let yodo = YoDo::new();
        let variants = yodo.expand_optional_words("turn [on|off] the light");
        assert!(variants.contains(&"turn on the light".to_string()));
        assert!(variants.contains(&"turn off the light".to_string()));
        assert!(variants.contains(&"turn the light".to_string()));
        let variants2 = yodo.expand_optional_words("play [some] music");
        assert!(variants2.contains(&"play some music".to_string()));
        assert!(variants2.contains(&"play music".to_string()));
        let variants3 = yodo.expand_optional_words("set (high|low) volume");
        assert!(variants3.contains(&"set high volume".to_string()));
        assert!(variants3.contains(&"set low volume".to_string()));
        assert!(!variants3.contains(&"set volume".to_string()));
    }

    #[test]
    fn test_build_pattern_matcher_simple() {
        let yodo = create_test_yodo();
        let (regex, params) = yodo.build_pattern_matcher("timer", "set a timer for {minutes} minutes").unwrap();
        assert_eq!(params, vec!["minutes".to_string()]);
        assert!(regex.is_match("set a timer for 5 minutes"));
        assert!(!regex.is_match("set a timer for minutes"));
    }

    #[test]
    fn test_build_pattern_matcher_wildcard() {
        let yodo = create_test_yodo();
        let (regex, params) = yodo.build_pattern_matcher("reminder", "set a reminder for {time} to {task}").unwrap();
        assert_eq!(params, vec!["time".to_string(), "task".to_string()]);
        assert!(regex.is_match("set a reminder for 8am to buy milk"));
        assert!(regex.is_match("set a reminder for 8am to anything with spaces"));
        assert!(!regex.is_match("set a reminder for to buy milk"));
    }

    #[test]
    fn test_align_words_exact() {
        let yodo = YoDo::new();
        let pattern = vec!["set".to_string(), "{param}".to_string(), "timer".to_string()];
        let text = vec!["set".to_string(), "a".to_string(), "timer".to_string()];
        let alignment = yodo.align_words(&pattern, &text);
        assert_eq!(alignment, vec![Some(0), Some(1), Some(2)]);
    }

    #[test]
    fn test_align_words_with_extra_words() {
        let yodo = YoDo::new();
        let pattern = vec!["play".to_string(), "{song}".to_string()];
        let text = vec!["play".to_string(), "the".to_string(), "beatles".to_string()];
        let alignment = yodo.align_words(&pattern, &text);
        assert!(alignment[1].is_some());
    }

    #[test]
    fn test_exact_match_timer() {
        let yodo = create_test_yodo();
        let result = yodo.exact_match("set a timer for 10 minutes and 45 seconds").unwrap();
        assert_eq!(result.script_name, "timer");
        assert_eq!(result.args, vec!["--minutes", "10", "--seconds", "45"]);
        assert_eq!(result.match_type, "exact");
    }

    #[test]
    fn test_exact_match_reminder_wildcard() {
        let yodo = create_test_yodo();
        let result = yodo.exact_match("set a reminder for 8am to buy milk and eggs").unwrap();
        assert_eq!(result.script_name, "reminder");
        assert_eq!(result.args, vec!["--time", "08:00", "--task", "buy milk and eggs"]);
    }

    #[test]
    fn test_exact_match_with_substitution() {
        let yodo = create_test_yodo();
        let result = yodo.exact_match("play some music by beatles").unwrap();
        assert_eq!(result.script_name, "play");
        assert!(result.args.contains(&"--artist".to_string()));
        assert!(result.args.contains(&"beatles_band".to_string()));
    }

    #[test]
    fn test_exact_match_optional_variant() {
        let yodo = create_test_yodo();
        let result = yodo.exact_match("play music by queen").unwrap();
        assert_eq!(result.script_name, "play");
        assert_eq!(result.args, vec!["--artist", "queen"]);
    }

    #[test]
    fn test_exact_match_no_match() {
        let yodo = create_test_yodo();
        assert!(yodo.exact_match("this does not match anything").is_none());
    }

    #[test]
    fn test_fuzzy_match_typo() {
        let yodo = create_test_yodo();
        let result = yodo.fuzzy_match("set a timr for 5 minuts and 30 secnds").unwrap();
        assert_eq!(result.script_name, "timer");
        assert!(result.args.contains(&"--minutes".to_string()));
        assert!(result.args.contains(&"--seconds".to_string()));
    }

    #[test]
    fn test_fuzzy_match_distinguishes_timer_reminder() {
        let yodo = create_test_yodo();
        let result = yodo.fuzzy_match("set a remindr for 8am to buy milk").unwrap();
        assert_eq!(result.script_name, "reminder");
    }

    #[test]
    fn test_fuzzy_match_threshold() {
        let mut yodo = create_test_yodo();
        yodo.fuzzy_index[0].fuzzy_threshold = 0.99;
        assert!(yodo.fuzzy_match("completely unrelated sentence").is_none());
    }

    #[test]
    fn test_find_best_fuzzy_match() {
        let yodo = create_test_yodo();
        let best = yodo.find_best_fuzzy_match("set a timr for 5 minuts and 30 secnds");
        assert!(best.is_some());
        let (script, _sentence, score) = best.unwrap();
        assert_eq!(script, "timer");
        assert!(score >= 70);
    }

    #[test]
    fn test_resolve_entity_list_exact() {
        let yodo = create_test_yodo();
        assert_eq!(yodo.resolve_entity("timer", "minutes", "5"), "5");
        assert_eq!(yodo.resolve_entity("timer", "minutes", "10"), "10");
        assert_eq!(yodo.resolve_entity("timer", "minutes", "15"), "15");
    }

    #[test]
    fn test_resolve_entity_wildcard() {
        let yodo = create_test_yodo();
        assert_eq!(yodo.resolve_entity("reminder", "task", "buy milk"), "buy milk");
    }

    #[test]
    fn test_resolve_entity_substitution() {
        let yodo = create_test_yodo();
        assert_eq!(yodo.resolve_entity("play", "artist", "beatles"), "beatles_band");
        assert_eq!(yodo.resolve_entity("play", "artist", "queen"), "queen");
    }

    #[test]
    fn test_is_wildcard_param() {
        let yodo = create_test_yodo();
        assert!(!yodo.is_wildcard_param("timer", "minutes"));
        assert!(yodo.is_wildcard_param("reminder", "task"));
        assert!(!yodo.is_wildcard_param("play", "artist"));
        assert!(yodo.is_wildcard_param("play", "song"));
    }

    #[test]
    fn test_is_valid_param_value() {
        let yodo = create_test_yodo();
        assert!(yodo.is_valid_param_value("timer", "minutes", "5"));
        assert!(yodo.is_valid_param_value("timer", "minutes", "10"));
        assert!(!yodo.is_valid_param_value("timer", "minutes", "15"));
        assert!(yodo.is_valid_param_value("reminder", "task", "anything"));
        assert!(yodo.is_valid_param_value("play", "artist", "the beatles"));
    }

    #[test]
    fn test_fuzzy_resolve_entity() {
        let mut yodo = create_test_yodo();
        let mut param_dict = HashMap::new();
        param_dict.insert(
            "artist".to_string(),
            vec![
                EntityMapping { input: "the beatles".to_string(), output: "the beatles".to_string() },
                EntityMapping { input: "beetles".to_string(), output: "the beatles".to_string() },
            ],
        );
        yodo.fuzzy_entity_dict.insert("play".to_string(), param_dict);
        assert_eq!(yodo.fuzzy_resolve_entity("play", "artist", "beetles", 80), Some("the beatles".to_string()));
        assert_eq!(yodo.fuzzy_resolve_entity("play", "artist", "rolling stones", 80), None);
    }

    #[test]
    fn test_apply_real_time_substitutions() {
        let yodo = create_test_yodo();
        let (resolved, subs) = yodo.apply_real_time_substitutions("play", "play music by beatles");
        assert_eq!(resolved, "play music by beatles_band");
        assert_eq!(subs.get("beatles"), Some(&"beatles_band".to_string()));
    }

    #[test]
    fn test_update_memory_context() {
        let _guard = TempHomeGuard::new();
        let yodo = create_test_yodo();
        let script = "timer";
        let args = vec!["--minutes".to_string(), "5".to_string()];
        let result = yodo.update_memory_context(script, &args);
        assert!(result.is_ok());
        let memory = YoDo::load_memory_data().unwrap();
        assert_eq!(memory.context.last_action, script);
    }

    #[test]
    fn test_empty_input_exact_match() {
        let yodo = create_test_yodo();
        assert!(yodo.exact_match("").is_none());
    }

    #[test]
    fn test_empty_input_fuzzy_match() {
        let yodo = create_test_yodo();
        assert!(yodo.fuzzy_match("").is_none());
    }

    #[test]
    fn test_no_patterns_compiled() {
        let mut yodo = YoDo::new();
        yodo.intent_data = serde_json::from_str("{}").unwrap();
        yodo.precompile_patterns();
        yodo.calculate_processing_order();
        assert!(yodo.exact_match("anything").is_none());
        assert!(yodo.fuzzy_match("anything").is_none());
    }
}
