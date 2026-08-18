#![allow(dead_code)]
#![allow(unused)]
use std::{
    env,
    fs::{OpenOptions, File},
    io::{self, Write},
    sync::Once,
    time::Instant,
};
use ducktrace_logger::*;


use std::collections::HashMap;
use std::fs;
use std::process::{Command, exit};
use regex::Regex;
use serde::{Deserialize, Serialize};
use colored::*;

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ScriptConfig {
    description: String,
    category: String,
    voice: Option<VoiceConfig>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct VoiceConfig {
    enabled: bool,
    priority: i32,
    sentences: Vec<String>,
    lists: HashMap<String, ListConfig>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ListConfig {
    wildcard: bool,
    values: Vec<ListValue>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ListValue {
    r#in: String,
    out: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct IntentData {
    substitutions: Vec<Substitution>,
    sentences: Vec<String>,
    lists: HashMap<String, ListConfig>,
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
}

struct TestRunner {
    intent_data: HashMap<String, IntentData>,
    fuzzy_index: Vec<FuzzyIndexEntry>,
    debug: bool,
    stats_mode: bool,
    single_input: Option<String>,
    script_filter: Option<String>,
    max_variants: usize,
}

#[derive(Debug)]
struct TestResult {
    passed_positive: usize,
    total_positive: usize,
    passed_negative: usize,
    total_negative: usize,
    passed_boundary: usize,
    total_boundary: usize,
    failures: Vec<String>,
    processing_time: std::time::Duration,
}

impl TestRunner {
    fn new() -> Self {
        Self {
            intent_data: HashMap::new(),
            fuzzy_index: Vec::new(),
            debug: env::var("DEBUG").is_ok() || env::var("DT_DEBUG").is_ok(),
            stats_mode: false,
            single_input: None,
            script_filter: None,
            max_variants: 1000,  
        }
    }

    fn load_data(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        if let Ok(intent_data_path) = env::var("YO_INTENT_DATA") {
            let data = fs::read_to_string(intent_data_path)?;
            self.intent_data = serde_json::from_str(&data)?;
            self.quack_debug(&format!("🦆 Loaded intent data for {} scripts", self.intent_data.len()));
        }

        if let Ok(fuzzy_index_path) = env::var("YO_FUZZY_INDEX") {
            let data = fs::read_to_string(fuzzy_index_path)?;
            self.fuzzy_index = serde_json::from_str(&data)?;
            self.quack_debug(&format!("🦆 Loaded {} fuzzy index entries", self.fuzzy_index.len()));
        }
        Ok(())
    }

    fn quack_debug(&self, msg: &str) {
        if self.debug {
            eprintln!("[🦆📜] ⁉️DEBUG⁉️ ⮞ {}", msg);
        }
    }

    fn quack_info(&self, msg: &str) {
        eprintln!("[🦆📜] ✅INFO✅ ⮞ {}", msg);
    }

    
    fn normalize_input(&self, input: &str) -> String {
        input.replace(['?', '!', '.', ',', '&', '/'], "").to_lowercase()
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
                        self.quack_debug(&format!("      Real-time sub: {} → {}", original, sub.value));
                    }
                }
            }
        }
        (resolved_text, substitutions)
    }
    
    
    fn resolve_entity(&self, script_name: &str, param_name: &str, param_value: &str) -> String {
        if let Some(intent) = self.intent_data.get(script_name) {
            let normalized_input = param_value.to_lowercase();
    
    
            for sub in &intent.substitutions {
                let pattern = sub.pattern.to_lowercase();
    
    
                if pattern == normalized_input {
                    self.quack_debug(&format!("      Exact entity match: {} → {}", param_value, sub.value));
                    return sub.value.clone();
                }
    
                if pattern.starts_with('(') && pattern.ends_with(')') {
                    let content = &pattern[1..pattern.len()-1];
                    if content == normalized_input {
                        self.quack_debug(&format!("      Parenthesized entity match: {} → {}", param_value, sub.value));
                        return sub.value.clone();
                    }
                    if pattern.contains('|') {
                        for alt in content.split('|') {
                            if alt.trim() == normalized_input {
                                self.quack_debug(&format!("      Parenthesized alternative match: {} → {}", param_value, sub.value));
                                return sub.value.clone();
                            }
                        }
                    }
                }
            }
    
            if let Some(list_config) = intent.lists.get(param_name) {
                if !list_config.wildcard {
                    for value in &list_config.values {
                        for literal in self.expand_list_entry(&value.r#in) {
                            if literal == normalized_input {
                                self.quack_debug(&format!("      List entity match: {} → {}", param_value, value.out));
                                return value.out.clone();
                            }
                        }
                    }
                }
            }
        }
    
        param_value.to_string()
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
            else { alternatives.push(token.to_string()); }

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

    fn resolve_sentence(&self, script_name: &str, sentence: &str) -> String {
        let mut resolved = sentence.to_string();
        
        let param_pattern = Regex::new(r"\{([^}]+)\}").unwrap();
        let mut params: Vec<String> = Vec::new();
        
        for cap in param_pattern.captures_iter(sentence) {
            if let Some(param) = cap.get(1) {
                params.push(param.as_str().to_string());
            }
        }

        for param in params {
            let replacement = if param.to_lowercase().contains("hour") 
                || param.to_lowercase().contains("minute") 
                || param.to_lowercase().contains("second") {
                "1".to_string()
            } else if param.to_lowercase().contains("room") 
                || param.to_lowercase().contains("device") {
                "livingroom".to_string()
            } else {
                "test".to_string()
            };
            
            resolved = resolved.replace(&format!("{{{}}}", param), &replacement);
        }

        let required_pattern = Regex::new(r"\(([^|)]+)(\|[^)]+)?\)").unwrap();
        resolved = required_pattern.replace_all(&resolved, "$1").to_string();
        
        let optional_pattern = Regex::new(r"\[([^]]+)\]").unwrap();
        resolved = optional_pattern.replace_all(&resolved, " $1 ").to_string();
        
        resolved = resolved.replace(" | ", " ").to_string();
        
        resolved = resolved.replace("  ", " ").trim().to_string();

        resolved
    }

    fn expand_list_entry(&self, pattern: &str) -> Vec<String> {
        let trimmed = pattern.trim();
        if trimmed.starts_with('[') && trimmed.ends_with(']') {
            let inner = &trimmed[1..trimmed.len()-1];
            inner.split('|')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect()
        } else if trimmed.contains('|') {
            trimmed.split('|')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect()
        } else {
            vec![trimmed.to_string()]
        }
    }

    fn generate_param_test_cases(&self, script_name: &str, sentence: &str) -> Vec<(String, HashMap<String, String>)> {
        if self.max_variants == 0 {
            return Vec::new();
        }

        let expanded_templates = self.expand_optional_words(sentence);
        let mut test_cases = Vec::new();

        for template in expanded_templates {
            if test_cases.len() >= self.max_variants {
                break;
            }        
            let param_pattern = Regex::new(r"\{([^}]+)\}").unwrap();
            let param_names: Vec<String> = param_pattern.captures_iter(&template)
                .map(|cap| cap[1].to_string())
                .collect();

            if param_names.is_empty() {
                test_cases.push((template.clone(), HashMap::new()));
                continue;
            }

            let mut param_options: Vec<Vec<(String, String)>> = Vec::new();
            for pname in &param_names {
                let mut options = Vec::new();
                if let Some(list_config) = self.intent_data.get(script_name)
                    .and_then(|intent| intent.lists.get(pname))
                {
                    if list_config.wildcard {
                        for sample in ["test", "star wars", "123"] {
                            options.push((sample.to_string(), sample.to_string()));
                        }
                    } else {
                        for value in &list_config.values {
                            for literal in self.expand_list_entry(&value.r#in) {
                                options.push((literal.clone(), value.out.clone()));
                            }
                        }
                    }
                } else { options.push((format!("<{}>", pname), format!("<{}>", pname))); }

                if options.is_empty() {
                    options.push((format!("<{}>", pname), format!("<{}>", pname)));
                }
                param_options.push(options);
            }

            fn cartesian_product(
                idx: usize,
                current_input: String,
                current_expected: HashMap<String, String>,
                param_names: &[String],
                param_options: &[Vec<(String, String)>],
                result: &mut Vec<(String, HashMap<String, String>)>,
            ) {
                if idx == param_names.len() {
                    result.push((current_input, current_expected));
                    return;
                }
                for (literal, out_val) in &param_options[idx] {
                    let mut new_input = current_input.clone();
                    new_input = new_input.replace(&format!("{{{}}}", param_names[idx]), literal);
                    let mut new_expected = current_expected.clone();
                    new_expected.insert(param_names[idx].clone(), out_val.clone());
                    cartesian_product(idx + 1, new_input, new_expected, param_names, param_options, result);
                }
            }

            cartesian_product(0, template.clone(), HashMap::new(), &param_names, &param_options, &mut test_cases);
        }

        test_cases.sort_by(|a, b| a.0.cmp(&b.0));
        test_cases.dedup_by(|a, b| a.0 == b.0);
        test_cases
    }

    fn extract_params_from_regex(re: &Regex, input: &str) -> Option<HashMap<String, String>> {
        let caps = re.captures(input)?;
        let mut map = HashMap::new();
        for name in re.capture_names().flatten() {
            if let Some(m) = caps.name(name) {
                map.insert(name.to_string(), m.as_str().to_string());
            }
        }
        Some(map)
    }
    
    
    fn test_param_extraction(&self, script_name: &str, input: &str, expected: &HashMap<String, String>) -> bool {
        let normalized_input = self.normalize_input(input);
    
        let (resolved_input, _substitutions) = self.apply_real_time_substitutions(script_name, &normalized_input);
    
        if let Some(intent) = self.intent_data.get(script_name) {
            for sentence in &intent.sentences {
                for variant in self.expand_optional_words(sentence) {
                    let pattern = self.build_test_regex(script_name, &variant);
                    if let Ok(re) = Regex::new(&pattern) {
                        if let Some(captures) = re.captures(&resolved_input) {
                            let mut actual = HashMap::new();
                            for name in re.capture_names().flatten() {
                                if let Some(m) = captures.name(name) {
                                    actual.insert(name.to_string(), m.as_str().to_string());
                                }
                            }
    
                            for (param_name, raw_value) in actual.iter_mut() {
                                *raw_value = self.resolve_entity(script_name, param_name, raw_value);
                            }
    
                            if &actual == expected {
                                self.quack_debug(&format!(
                                    "✅ Param extraction success: '{}' -> {:?}",
                                    input, actual
                                ));
                                return true;
                            } else {
                                self.quack_debug(&format!(
                                    "❌ Param mismatch for '{}': expected {:?}, got {:?}",
                                    input, expected, actual
                                ));
                            }
                        }
                    }
                }
            }
        }
        false
    }
    

    fn test_exact_match(&self, script_name: &str, input: &str) -> bool {
        if let Some(intent) = self.intent_data.get(script_name) {
            let normalized_input = input.to_lowercase();
            for sentence in &intent.sentences {
                for variant in self.expand_optional_words(sentence) {
                    let pattern = self.build_test_regex(script_name, &variant);
                    if let Ok(re) = Regex::new(&pattern) {
                        if re.is_match(&normalized_input) {
                            return true;
                        }
                    }
                }
            }
        }
        false
    }

    fn build_test_regex(&self, script_name: &str, sentence: &str) -> String {
        let mut regex_parts = Vec::new();
        let mut current = sentence.to_string();
    
        while let Some(start) = current.find('{') {
            if let Some(end) = current.find('}') {
                let before_param = &current[..start];
                let param = &current[start+1..end];
                let after_param = &current[end+1..];
    
                if !before_param.is_empty() {
                    regex_parts.push(regex::escape(before_param));
                }
    
                let is_wildcard = self.intent_data.get(script_name)
                    .and_then(|intent| intent.lists.get(param))
                    .map(|list| list.wildcard)
                    .unwrap_or(false);
    
                let regex_group = if is_wildcard {
                    format!("(?P<{}>.*)", regex::escape(param))
                } else { format!(r"(?P<{}>\b[^ ]+\b)", regex::escape(param)) };
    
                regex_parts.push(regex_group);
                current = after_param.to_string();
            } else { break; }
        }
    
        if !current.is_empty() {
            regex_parts.push(regex::escape(&current));
        }
    
        format!("^{}$", regex_parts.join(""))
    }
    


    fn test_single_input(&self, input: &str) {
        println!("{}", "[🦆📜] Testing single input:".bright_blue());
        println!("{} '{}'", "   └─".bright_blue(), input);
        let mut matched = false;
        for script_name in self.intent_data.keys() {
            if self.test_exact_match(script_name, input) {
                println!("{} {} {}", "   └─".green(), "✅ MATCH:".green(), script_name);
                matched = true;
                break;
            }
        }

        if !matched {
            if let Some(fuzzy_match) = self.find_best_fuzzy_match(input) {
                println!("{} {} {} (score: {}%)", "   └─".yellow(), "FUZZY:".yellow(), fuzzy_match.0, fuzzy_match.1);
            } else { println!("{} {}", "   └─".red(), "❌ NO MATCH".red()); }
        }
    }

    fn find_best_fuzzy_match(&self, text: &str) -> Option<(String, i32)> {
        let normalized_input = text.to_lowercase();
        let mut best_score = 0;
        let mut best_match = None;

        for entry in &self.fuzzy_index {
            let normalized_sentence = entry.sentence.to_lowercase();
            let distance = self.levenshtein_distance(&normalized_input, &normalized_sentence);
            let max_len = normalized_input.len().max(normalized_sentence.len()); 
            if max_len == 0 { continue; }
            let score = 100 - (distance * 100 / max_len) as i32;
    
            if score >= 15 && score > best_score {
                best_score = score;
                best_match = Some((entry.script.clone(), score));
            }
        }
        best_match
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

    fn run_test_suite(&self) -> TestResult {
        let start_time = Instant::now();
        let mut result = TestResult {
            passed_positive: 0,
            total_positive: 0,
            passed_negative: 0,
            total_negative: 0,
            passed_boundary: 0,
            total_boundary: 0,
            failures: Vec::new(),
            processing_time: std::time::Duration::default(),
        };

        let filter = self.script_filter.as_deref();

        self.test_positive_cases(&mut result, filter);
        self.test_negative_cases(&mut result, filter);
        self.test_boundary_cases(&mut result, filter);

        result.processing_time = start_time.elapsed();
        result
    }

    
    fn test_positive_cases(&self, result: &mut TestResult, filter: Option<&str>) {
        println!("{}", "[🦆📜] Testing Positive Cases".bright_blue());

        for (script_name, intent) in &self.intent_data {
            if let Some(f) = filter {
                if script_name != f {
                    continue;
                }
            }

            println!("{} {}", "   └─ Testing script:".bright_blue(), script_name);

            for sentence in &intent.sentences {
                let test_cases = self.generate_param_test_cases(script_name, sentence);

                for (input, expected_params) in test_cases {
                    result.total_positive += 1;
                    print!("{} {}", "     Testing:".bright_blue(), input);

                    if self.test_param_extraction(script_name, &input, &expected_params) {
                        println!(" {}", "✅".green());
                        result.passed_positive += 1;
                    } else {
                        println!(" {}", "❌".red());
                        result.failures.push(format!(
                            "POSITIVE: {} | input='{}' expected={:?}",
                            script_name, input, expected_params
                        ));
                    }
                }
            }
        }
    }
    
    fn test_negative_cases(&self, result: &mut TestResult, filter: Option<&str>) {
        println!("{}", "[🦆🚫] Testing Negative Cases".bright_blue());

        let negative_cases = vec![
            "make me a sandwich",
            "launch the nuclear torpedos!",
            "gör mig en macka",
            "avfyra kärnvapnen!",
            "ducks sure are the best dont you agree",
        ];

        for case in negative_cases {
            result.total_negative += 1;
            print!("{} {}", "   Testing:".bright_blue(), case);

            let mut matched = false;
            for script_name in self.intent_data.keys() {
                if let Some(f) = filter {
                    if script_name != f {
                        continue;
                    }
                }

                if self.test_exact_match(script_name, case) {
                    println!(" {}", "❌ FALSE POSITIVE".red());
                    result.failures.push(format!("NEGATIVE: {} | {}", script_name, case));
                    matched = true;
                    break;
                }
            }

            if !matched {
                println!(" {}", "✅".green());
                result.passed_negative += 1;
            }
        }
    }

    fn test_boundary_cases(&self, result: &mut TestResult, filter: Option<&str>) {
        println!("{}", "[🦆🔲] Testing Boundary Cases".bright_blue());
        let boundary_cases = vec!["", "   ", ".", "!@#$%^&*()"];

        for case in boundary_cases {
            result.total_boundary += 1;
            print!("{} '{}'", "   Testing:".bright_blue(), case);

            let mut matched = false;
            for script_name in self.intent_data.keys() {
                if let Some(f) = filter {
                    if script_name != f {
                        continue;
                    }
                }

                if self.test_exact_match(script_name, case) {
                    println!(" {}", "❌".red());
                    result.failures.push(format!("BOUNDARY: {} | '{}'", script_name, case));
                    matched = true;
                    break;
                }
            }

            if !matched {
                println!(" {}", "✅".green());
                result.passed_boundary += 1;
            }
        }
    }

    fn display_stats(&self) {
        println!("{}", "[🦆📊] Voice Command Statistics".bright_blue());
        println!();

        let mut scripts_with_voice = Vec::new();

        for (script_name, intent) in &self.intent_data {
            let patterns = intent.sentences.len();
            let phrases: usize = intent.sentences.iter()
                .map(|s| self.expand_optional_words(s).len())
                .sum();
            
            let ratio = if patterns > 0 {
                phrases as f64 / patterns as f64
            } else { 0.0 };

            scripts_with_voice.push((script_name.clone(), patterns, phrases, ratio));
        }

        scripts_with_voice.sort_by(|a, b| b.3.partial_cmp(&a.3).unwrap());

        for (name, patterns, phrases, ratio) in scripts_with_voice {
            let ratio_str = if patterns == 0 {
                "∞".to_string()
            } else { format!("{:.1}", ratio) };

            let status = if patterns == 0 {
                "EMPTY".red()
            } else if phrases == 0 || (patterns > 0 && ratio < 0.5) {
                "NEEDS PHRASES".yellow()
            } else if ratio > 50.0 {
                "HIGH RATIO".bright_yellow()
            } else { "OK".green() };
            
            println!("{}: patterns={}, phrases={}, ratio={} - {}", 
                name, patterns, phrases, ratio_str, status);
        }

        println!();
        println!("{}", "Key insights:".bright_blue());
        println!("  • High pattern count decreases matching speed but increases accuracy");
        println!("  • High ratio (>50) may indicate over-complex patterns");
        println!("  • Use priority=5 for scripts with many patterns to optimize performance");
    }

    fn display_final_report(&self, result: &TestResult) {
        let total_tests = result.total_positive + result.total_negative + result.total_boundary;
        let passed_tests = result.passed_positive + result.passed_negative + result.passed_boundary;
        let percent = if total_tests > 0 {
            (passed_tests * 100) / total_tests
        } else { 0 };

        let (color, duck_report) = if percent >= 80 {
            (Color::Green, "⭐")
        } else if percent >= 60 {
            (Color::Yellow, "🟢") 
        } else {
            (Color::Red, "😭")
        };

        if passed_tests != total_tests && !result.failures.is_empty() {
            println!();
            println!("{}", "# ────── FAILURES ──────#".red());
            for failure in &result.failures {
                println!("{} {}", "## ❌".red(), failure);
            }
            println!("{}", "# ────── FAILURES ──────#".red());
        }

        println!();
        println!("{}", "# ──────⋆⋅☆⋅⋆────── #".color(color));
        println!("{}", "Testing completed!".bold());
        println!("{} {}", "Positive:".bold(), 
            format!("{}/{}", result.passed_positive, result.total_positive).color(color));
        println!("{} {}", "Negative:".bold(),
            format!("{}/{}", result.passed_negative, result.total_negative).color(color));
        println!("{} {}", "Boundary:".bold(),
            format!("{}/{}", result.passed_boundary, result.total_boundary).color(color));
        println!("{} {}", "TOTAL:".bold(),
            format!("{}/{} ({}%)", passed_tests, total_tests, percent).color(color));
        println!("{}", "# ──────⋆⋅☆⋅⋆────── #".color(color));
        println!("{}", duck_report);   
        self.quack_info(&format!("Test completed with results: {}/{} {}%", 
            passed_tests, total_tests, percent));
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    if env::var("YO_INTENT_DATA").is_err() {
        env::set_var("YO_INTENT_DATA", "/etc/yo/intent-data.json");
    }
    if env::var("YO_FUZZY_INDEX").is_err() {
        env::set_var("YO_FUZZY_INDEX", "/etc/yo/fuzzy-index.json");
    }

        
    let debug = std::env::var("DEBUG").is_ok();
    if debug { std::env::set_var("DT_LOG_LEVEL", "DEBUG"); }
    dt_setup(None, None);
    dt_debug!("Started yo-tests!");    
    let args: Vec<String> = env::args().collect();
    let mut test_runner = TestRunner::new();

    let mut stats_mode = false;
    let mut single_input = None;
    let mut script_filter = None;
    let mut max_variants = 1000;
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--stats" => stats_mode = true,
            "--input" if i + 1 < args.len() => {
                single_input = Some(args[i + 1].clone());
                i += 1;
            }
            "--script" if i + 1 < args.len() => {
                script_filter = Some(args[i + 1].clone());
                i += 1;
            }
            "--max-variants" if i + 1 < args.len() => {
                max_variants = args[i + 1].parse().unwrap_or(1000);
                i += 1;
            }
            _ => {}
        }
        i += 1;
    }

    test_runner.stats_mode = stats_mode;
    test_runner.single_input = single_input;
    test_runner.script_filter = script_filter;
    test_runner.max_variants = max_variants;

    test_runner.load_data()?;

    if test_runner.stats_mode {
        test_runner.display_stats();
    } else if let Some(input) = &test_runner.single_input {
        test_runner.test_single_input(input);
    } else {
        let result = test_runner.run_test_suite();
        test_runner.display_final_report(&result);
        
        if result.passed_positive + result.passed_negative + result.passed_boundary 
            != result.total_positive + result.total_negative + result.total_boundary {
            exit(1);
        }
    } 
    Ok(())
}
