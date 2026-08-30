use std::sync::Arc;
use std::time::Instant;
use anyhow::Result;
use whisper_rs::{WhisperContext, FullParams, SamplingStrategy};
use crate::helpers::{normalize_transcription, write_last_sender_ip};

#[derive(Clone)]
pub struct TranscriptionProcessor {
    pub whisper_ctx: Arc<WhisperContext>,
    pub beam_size: i32,
    pub temperature: f32,
    pub language: Option<String>,
    pub threads: i32,
    pub exec_command: Option<String>,
    pub translate_to_shell: bool,
    pub room: String,
    pub done_sound: Vec<u8>,
    pub fail_sound: Vec<u8>,
    pub debug: bool,
    pub model_path: String,
    pub sender_ip: String,
    pub client_id: String,
    pub cut_at_punctuation: bool,
}

impl TranscriptionProcessor {
    pub fn process_audio(&self, audio: &[f32]) -> Result<(String, bool)> {
        let text = self.transcribe(audio)?;
        let normalized = normalize_transcription(&text);

        crate::dt_info!("[{}] Transcription: {}", self.client_id, text);
        crate::dt_info!("[{}] Normalized: {}", self.client_id, normalized);

        let success = self.execute_command(&normalized)?;
        Ok((normalized, success))
    }

    pub fn log_benchmark(&self, perf_start: Instant, audio_len: usize) {
        let elapsed = perf_start.elapsed().as_secs_f64();
        crate::log_transcription_time(
            &self.client_id,
            perf_start,
            audio_len,
            16000,
            &self.model_path,
            self.beam_size,
            self.threads,
        );
        crate::log_transcription_benchmark(elapsed, &self.model_path);
        write_last_sender_ip(&self.sender_ip);
    }

    fn transcribe(&self, audio: &[f32]) -> Result<String> {
        let sampling_strategy = if self.beam_size > 0 {
            SamplingStrategy::BeamSearch { beam_size: self.beam_size, patience: 1.0 }
        } else {
            SamplingStrategy::Greedy { best_of: 1 }
        };

        let mut params = FullParams::new(sampling_strategy);
        params.set_n_threads(self.threads);
        params.set_translate(false);
        params.set_language(self.language.as_deref());
        params.set_print_special(false);
        params.set_print_progress(false);
        params.set_print_realtime(false);
        params.set_print_timestamps(false);
        params.set_temperature(self.temperature);
        params.set_suppress_blank(true);
        params.set_suppress_nst(true);

        let mut state = self.whisper_ctx.create_state()?;
        state.full(params, audio)?;

        let num_segments = state.full_n_segments() as usize;
        let mut transcription = String::new();
        for i in 0..num_segments {
            if let Some(segment) = state.get_segment(i as i32) {
                transcription.push_str(&segment.to_string());
            }
        }

        if self.cut_at_punctuation {
            if let Some(pos) = transcription.find(['?', '!', '.']) {
                transcription.truncate(pos);
            }
        }

        Ok(transcription)
    }

    fn execute_command(&self, text: &str) -> Result<bool> {
        if text.is_empty() {
            return Ok(false);
        }

        if self.translate_to_shell {
            let mut cmd = std::process::Command::new("yo");
            cmd.arg("do");
            if !self.room.is_empty() {
                cmd.arg("--room").arg(&self.room);
            }
            cmd.arg(text).env("VOICE_MODE", "1");
            let status = cmd.status()?;
            return Ok(status.success());
        }

        if let Some(cmd_str) = &self.exec_command {
            let mut parts = cmd_str.split_whitespace();
            if let Some(program) = parts.next() {
                let mut cmd = std::process::Command::new(program);
                for arg in parts {
                    cmd.arg(arg);
                }
                cmd.arg(text).env("VOICE_MODE", "1");
                let status = cmd.status()?;
                return Ok(status.success());
            }
        }

        Ok(false)
    }
}
