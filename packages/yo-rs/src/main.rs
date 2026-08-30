use std::{
    env,
    collections::HashMap,
    io::Read,
    io::Write,
    path::PathBuf,
    fs::{self},
    net::{TcpStream},
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant},
    sync::{Arc, Mutex},
};

use oww_rs::oww::{OwwModel, OWW_MODEL_CHUNK_SIZE};
use whisper_rs::{WhisperContext, WhisperContextParameters};

use serde::{Serialize, Deserialize};
use ducktrace_logger::*;
use anyhow::Result;
use anyhow::Context;
use byteorder::{LittleEndian, ReadBytesExt, WriteBytesExt};

use rodio::{OutputStream, Sink, buffer::SamplesBuffer};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

mod helpers;
use helpers::{play_sound_in_background, play_done_sound, play_fail_sound};
mod transcription;
use crate::transcription::TranscriptionProcessor;

struct ChildGuard(std::process::Child);

impl Drop for ChildGuard {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ClientEntry {
    room: String,
    ip: String,
    connected_at: u64,
}

struct ClientRegistry {
    entries: HashMap<(String, String), (usize, u64)>,
    file_path: PathBuf,
}

impl ClientRegistry {
    fn new() -> Self {
        let home = env::var("HOME").unwrap_or_else(|_| ".".to_string());
        let dir = PathBuf::from(&home).join(".config/yo");
        fs::create_dir_all(&dir).unwrap_or_else(|e| {
            dt_error!("Failed to create config dir: {}", e);
        });
        let file_path = dir.join("clients.json");
        Self {
            entries: HashMap::new(),
            file_path,
        }
    }

    fn add_connection(&mut self, room: &str, ip: &str) {
        let key = (room.to_string(), ip.to_string());
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();
        let (count, _) = self.entries.entry(key).or_insert((0, now));
        *count += 1;
        self.save();
    }

    fn remove_connection(&mut self, room: &str, ip: &str) {
        let key = (room.to_string(), ip.to_string());
        if let std::collections::hash_map::Entry::Occupied(mut entry) = self.entries.entry(key) {
            let (count, _) = entry.get_mut();
            if *count > 1 {
                *count -= 1;
            } else { entry.remove(); }
            self.save();
        }
    }

    fn save(&self) {
        let entries: Vec<ClientEntry> = self
            .entries
            .iter()
            .map(|((room, ip), &(_, connected_at))| ClientEntry {
                room: room.clone(),
                ip: ip.clone(),
                connected_at,
            })
            .collect();

        let json = serde_json::to_string_pretty(&entries).unwrap_or_else(|e| {
            dt_error!("failed to serialize client list: {}", e);
            "[]".to_string()
        });

        let tmp_path = self.file_path.with_extension(".tmp");
        if let Err(e) = std::fs::write(&tmp_path, &json) {
            dt_error!("failed to write client list to {:?}: {}", tmp_path, e);
            return;
        }
        if let Err(e) = std::fs::rename(&tmp_path, &self.file_path) {
            dt_error!("failed to rename client list: {}", e);
        }
    }
}

fn rms_f32(samples: &[f32]) -> f32 {
    if samples.is_empty() {
        return 0.0;
    }
    let sum_squares: f32 = samples.iter().map(|&x| x * x).sum();
    (sum_squares / samples.len() as f32).sqrt()
}

const NOISE_PROFILE_BYTES: &[u8] = include_bytes!("./../noise.prof");

fn sox_noisered(samples: &[f32], sample_rate: u32, amount: f32) -> Result<Vec<f32>> {
    let mut tmp = tempfile::NamedTempFile::new()?;
    tmp.write_all(NOISE_PROFILE_BYTES)?;
    tmp.flush()?;
    tmp.as_file().sync_all()?; 
    let profile_path = tmp.path().to_str().unwrap();

    let mut wav_bytes = Vec::new();
    {
        let spec = hound::WavSpec {
            channels: 1,
            sample_rate,
            bits_per_sample: 16,
            sample_format: hound::SampleFormat::Int,
        };
        let mut writer = hound::WavWriter::new(std::io::Cursor::new(&mut wav_bytes), spec)?;
        for &s in samples {
            let clamped = s.clamp(-1.0, 1.0);
            writer.write_sample((clamped * i16::MAX as f32) as i16)?;
        }
        writer.finalize()?;
    }

    let mut child = Command::new("sox")
        .args([
            "-t", "wav", "-",
            "-t", "raw",
            "-e", "signed-integer",
            "-b", "16",
            "-c", "1",
            "-r", &format!("{}", sample_rate),
            "-",
            "noisered", profile_path,
            &format!("{:.2}", amount),
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;

    {
        let mut stdin = child.stdin.take().unwrap();
        stdin.write_all(&wav_bytes)?;
    }

    let mut raw_bytes = Vec::new();
    child.stdout.take().unwrap().read_to_end(&mut raw_bytes)?;

    let status = child.wait()?;
    if !status.success() {
        let mut err_msg = String::new();
        if let Some(mut stderr) = child.stderr {
            stderr.read_to_string(&mut err_msg).ok();
        }
        anyhow::bail!("SoX failed (exit {}): {}", status.code().unwrap_or(-1), err_msg.trim());
    }

    if raw_bytes.len() % 2 != 0 {
        anyhow::bail!("Raw output size {} is odd, expected even number of bytes for i16", raw_bytes.len());
    }
    let num_samples = raw_bytes.len() / 2;
    let mut cleaned = Vec::with_capacity(num_samples);
    for chunk in raw_bytes.chunks_exact(2) {
        let sample = i16::from_le_bytes([chunk[0], chunk[1]]);
        cleaned.push(sample as f32 / i16::MAX as f32);
    }

    Ok(cleaned)
}

fn log_transcription_time(
    client_id: &str,
    start: Instant,
    audio_samples: usize,
    sample_rate: u32,
    model: &str,
    beam_size: i32,
    threads: i32,
) {
    let elapsed = start.elapsed();
    let audio_secs = audio_samples as f64 / sample_rate as f64;
    dt_info!(
        "[{}] Transcription finished: audio={:.2}s, proc={:.3}s (model={}, beam={}, threads={})",
        client_id,
        audio_secs,
        elapsed.as_secs_f64(),
        model,
        beam_size,
        threads
    );
}

fn log_transcription_benchmark(time_secs: f64, model: &str) {
    let home = env::var("HOME").unwrap_or_else(|_| ".".to_string());
    let dir = PathBuf::from(&home).join(".config/yo");
    let file_path = dir.join("whisper-bench.txt");

    if let Err(e) = fs::create_dir_all(&dir) {
        dt_error!("Failed to create config dir for benchmark: {}", e);
        return;
    }

    let mut entries: Vec<(f64, String)> = Vec::new();
    if let Ok(content) = fs::read_to_string(&file_path) {
        for line in content.lines().skip(1) {
            let trimmed = line.trim();
            if let Some(parts) = trimmed.split_once(" s (") {
                if let Ok(secs) = parts.0.trim().parse::<f64>() {
                    let model_part = parts.1.trim_end_matches(')').to_string();
                    entries.push((secs, model_part));
                }
            }
        }
    }
    let model_name = std::path::Path::new(model)
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or(model)
        .to_string();
    entries.push((time_secs, model_name));
    
    let latest_model = entries
        .last()
        .map(|(_, m)| m.clone())
        .unwrap_or_else(|| model.to_string());

    let (sum, count) = entries
        .iter()
        .filter(|(_, m)| *m == latest_model)
        .fold((0.0_f64, 0_u64), |(acc, cnt), (t, _)| (acc + t, cnt + 1));
    let average = if count > 0 { sum / count as f64 } else { 0.0 };

    let header = format!("{:.2} s average using model: {} ({} entries)", average, latest_model, count);
    let mut output = header + "\n";
    for (secs, model_entry) in &entries {
        output.push_str(&format!("{:.3} s ({})\n", secs, model_entry));
    }
    if let Err(e) = fs::write(&file_path, output) {
        dt_error!("Failed to write benchmark file: {}", e);
    }
}

fn handle_intercom(
    mut stream: TcpStream,
    client_id: String,
    debug: bool,
    _room: String,
    esp_ip: String,
) -> Result<()> {
    let (_stream, handle) = OutputStream::try_default()?;
    let sink = Sink::try_new(&handle)?;
    const SAMPLE_RATE: u32 = 16000;

    let _reverse_guard = {
        let ip = esp_ip;
        Command::new("sh")
            .arg("-c")
            .arg(format!(
                "ffmpeg -f alsa -i default -f s16le -ar 16000 -ac 2 - | nc {} 12345",
                ip
            ))
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .context("failed to start reverse audio stream")
            .map(ChildGuard)?
    };

    loop {
        let num_samples = match stream.read_u32::<LittleEndian>() {
            Ok(n) => n as usize,
            Err(e) => {
                dt_info!("[{}] Intercom disconnected ({})", client_id, e);
                break;
            }
        };

        let mut raw = vec![0u8; num_samples * 4];
        if let Err(e) = stream.read_exact(&mut raw) {
            dt_info!("[{}] Intercom read error: {}", client_id, e);
            break;
        }

        let samples: Vec<f32> = raw
            .chunks_exact(4)
            .map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]]))
            .collect();

        if debug {
            dt_debug!("[{}] Intercom got {} samples", client_id, samples.len());
        }

        let i16_samples: Vec<i16> = samples
            .iter()
            .map(|s| (s * i16::MAX as f32) as i16)
            .collect();

        let source = SamplesBuffer::new(1, SAMPLE_RATE, i16_samples);
        sink.append(source);
    }

    Ok(())
}


fn save_audio_to_file(audio: &[f32], client_id: &str) -> std::io::Result<()> {
    use std::fs::{File, create_dir_all};
    use std::io::Write;
    use std::path::Path;

    let dir = Path::new("recordings");
    if !dir.exists() {
        create_dir_all(dir)?;
    }

    let safe_client_id = client_id
        .chars()
        .map(|c| if c.is_alphanumeric() { c } else { '_' })
        .collect::<String>();

    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();

    let filename = format!("recordings/esp_{}_{}.raw", safe_client_id, timestamp);
    let mut file = File::create(filename)?;
    for &sample in audio {
        file.write_all(&sample.to_le_bytes())?;
    }
    Ok(())
}

const LISTEN_ADDR: &str = "0.0.0.0:12345";
const DING_WAV: &[u8] = include_bytes!("./../ding.wav");
const DONE_WAV: &[u8] = include_bytes!("./../done.wav");
const FAIL_WAV: &[u8] = include_bytes!("./../fail.wav");

const DEFAULT_WAKE_MODEL: &[u8] = include_bytes!("./../models/wake-words/yo_bitch.onnx");

const PTT_START: u8 = 0x10; // CLIENT: “HERE COMES AUDIO”
const PTT_DATA:  u8 = 0x11; // LENGTH + f32 SAMPLES
const PTT_END:   u8 = 0x12; // CLIENT: “DONE!, TRANSCRIBE NOW”

const INTERCOM_AUDIO: u8 = 0x20;

const ESP_SILENCE_THRESHOLD: f32 = 0.005;
const ESP_SILENCE_TIMEOUT_SECS: f64 = 1.0;
const ESP_ADDITIONAL_SILENCE_TRIM: f32 = 0.5;
const ESP_MAX_DURATION_SECS: f64 = 5.0;
const ESP_CUT_TRANSCRIPTION_AT_PUNCTUATION: bool = true;
const COOLDOWN_SECS: f64 = 5.0;  

// RESET WAKE MODEL BY SENDING ZERO
fn reset_wake_model(model: &mut OwwModel, chunks_to_flush: usize) {
    let zero_chunk = vec![0.0; OWW_MODEL_CHUNK_SIZE];
    for _ in 0..chunks_to_flush {
        let _ = model.detection(zero_chunk.clone());
    }
}

async fn handle_client_async(
    mut stream: tokio::net::TcpStream,
    mut wake_model: OwwModel,
    whisper_ctx: Arc<WhisperContext>,
    client_id: String,
    debug: bool,
    cooldown_secs: u64,
    beam_size: i32,
    temperature: f32,
    language: Option<String>,
    threads: i32,
    sound_data: Vec<u8>,
    done_sound_data: Vec<u8>,
    fail_sound_data: Vec<u8>,
    exec_command: Option<String>,
    translate_to_shell: bool,
    room: String,
    sender_ip: String,
    whisper_model_path: String,
) -> Result<()> {
    let mut last_detection: Option<Instant> = None;

    loop {
        let len = match stream.read_u32_le().await {
            Ok(l) => l as usize,
            Err(e) => {
                dt_error!("[{}] Failed to read length: {} – client disconnected", client_id, e);
                break;
            }
        };

        let mut sample_bytes = vec![0u8; len * 4];
        if let Err(e) = stream.read_exact(&mut sample_bytes).await {
            dt_error!("[{}] Failed to read samples: {}", client_id, e);
            break;
        }

        let samples: Vec<f32> = sample_bytes
            .chunks_exact(4)
            .map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]]))
            .collect();

        if samples.len() != OWW_MODEL_CHUNK_SIZE {
            dt_warning!(
                "[{}] Warning: received chunk of size {}, expected {}",
                client_id, samples.len(), OWW_MODEL_CHUNK_SIZE
            );
        }

        let detection = wake_model.detection(samples.clone());

        if detection.detected {
            if let Some(last) = last_detection {
                if last.elapsed() < Duration::from_secs(1) {
                    tokio::time::sleep(Duration::from_millis(100)).await;
                    continue;
                }
            }

            let mut timer = dt_timer("voice pipeline");
            dt_info!("💥 DETECTED! {} Probability: {:.4}", client_id, detection.probability);

            play_sound_in_background(sound_data.clone(), &client_id, debug, "awake sound");

            stream.write_all(&[0x01]).await?;
            stream.flush().await?;

            let transcription_audio = loop {
                let mut msg_type = [0u8; 1];
                stream.read_exact(&mut msg_type).await?;
                match msg_type[0] {
                    0x02 => {
                        let num_samples = stream.read_u32_le().await? as usize;
                        let mut audio_bytes = vec![0u8; num_samples * 4];
                        stream.read_exact(&mut audio_bytes).await?;
                        let audio_f32: Vec<f32> = audio_bytes
                            .chunks_exact(4)
                            .map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]]))
                            .collect();
                        break audio_f32;
                    }
                    _ => {
                        let len = stream.read_u32_le().await? as usize;
                        let mut discard = vec![0u8; len * 4];
                        stream.read_exact(&mut discard).await?;
                        dt_error!("[{}] Discarded a pending wake chunk ({} samples)", client_id, len);
                        continue;
                    }
                }
            };

            let perf_start = Instant::now();

            let processor = TranscriptionProcessor {
                whisper_ctx: whisper_ctx.clone(),
                beam_size,
                temperature,
                language: language.clone(),
                threads,
                exec_command: exec_command.clone(),
                translate_to_shell,
                room: room.clone(),
                done_sound: done_sound_data.clone(),
                fail_sound: fail_sound_data.clone(),
                debug,
                model_path: whisper_model_path.clone(),
                sender_ip: sender_ip.clone(),
                client_id: client_id.clone(),
                cut_at_punctuation: false,
            };

            let audio_clone = transcription_audio.clone();
            let (normalized, success) = {
                let processor = processor.clone();
                tokio::task::spawn_blocking(move || processor.process_audio(&audio_clone))
                    .await??
            };

            if success {
                play_done_sound(done_sound_data.clone(), &client_id, debug);
            } else { play_fail_sound(fail_sound_data.clone(), &client_id, debug); }

            let byte = if success { 0x03 } else { 0x04 };
            stream.write_all(&[byte]).await?;
            stream.flush().await?;

            processor.log_benchmark(perf_start, transcription_audio.len());

            last_detection = Some(Instant::now());
        } else if debug && detection.probability > 0.0 {
            dt_debug!("[{}] Probability: {:.4}", client_id, detection.probability);
        }
    }

    dt_info!("🚫 ❌ {} Disconnected!", client_id);
    Ok(())
}

async fn handle_ptt_async(
    mut stream: tokio::net::TcpStream,
    whisper_ctx: Arc<WhisperContext>,
    client_id: String,
    debug: bool,
    beam_size: i32,
    temperature: f32,
    language: Option<String>,
    threads: i32,
    exec_command: Option<String>,
    translate_to_shell: bool,
    room: String,
    sound_data: Vec<u8>,
    done_sound_data: Vec<u8>,
    fail_sound_data: Vec<u8>,
    sender_ip: String,
    whisper_model_path: String,
) -> Result<()> {
    let mut audio_buffer: Vec<f32> = Vec::new();

    loop {
        let msg_type = match stream.read_u8().await {
            Ok(b) => b,
            Err(_) => {
                dt_info!("[{}] PTT client disconnected", client_id);
                break;
            }
        };

        match msg_type {
            PTT_START => {
                dt_debug!("[{}] PTT recording started", client_id);
                audio_buffer.clear();
                play_sound_in_background(sound_data.clone(), &client_id, debug, "awake sound for PTT");
            }
            PTT_DATA => {
                let num_samples = stream.read_u32_le().await? as usize;
                let mut buf = vec![0u8; num_samples * 4];
                stream.read_exact(&mut buf).await?;

                let samples: Vec<f32> = buf
                    .chunks_exact(4)
                    .map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]]))
                    .collect();

                let sample_count = samples.len();
                audio_buffer.extend(samples);
                if debug {
                    dt_debug!("[{}] PTT received {} samples, total {}",
                        client_id, sample_count, audio_buffer.len());
                }
            }
            PTT_END => {
                let duration_millis = audio_buffer.len() as f64 / 16_000.0 * 1000.0;
                dt_info!("[{}] assumed duration: {:.0} ms", client_id, duration_millis);
                dt_info!("[{}] PTT recording ended, transcribing…", client_id);

                if audio_buffer.is_empty() {
                    dt_warning!("[{}] no audio to transcribe", client_id);
                    if let Err(e) = stream.write_all(&[0x04]).await {
                        dt_error!("[{}] failed to send empty-audio failure: {}", client_id, e);
                    }
                    if let Err(e) = stream.flush().await {
                        dt_error!("[{}] failed to flush after failure: {}", client_id, e);
                    }
                    continue;
                }

                let audio_for_noisered = audio_buffer.clone();
                let cleaned_audio = {
                    let client_id_clone = client_id.clone();
                    tokio::task::spawn_blocking(move || {
                        let AMOUNT = 0.21;
                        match sox_noisered(&audio_for_noisered, 16000, AMOUNT) {
                            Ok(audio) => audio,
                            Err(e) => {
                                dt_error!("[{}] Noise reduction failed: {} – using raw audio", client_id_clone, e);
                                audio_for_noisered.clone()
                            }
                        }
                    })
                    .await?
                };

                let rms_clean = rms_f32(&cleaned_audio);
                dt_debug!("[{}] Cleaned audio RMS: {:.6}", client_id, rms_clean);

                let processor = TranscriptionProcessor {
                    whisper_ctx: whisper_ctx.clone(),
                    beam_size,
                    temperature,
                    language: language.clone(),
                    threads,
                    exec_command: exec_command.clone(),
                    translate_to_shell,
                    room: room.clone(),
                    done_sound: done_sound_data.clone(),
                    fail_sound: fail_sound_data.clone(),
                    debug,
                    model_path: whisper_model_path.clone(),
                    sender_ip: sender_ip.clone(),
                    client_id: client_id.clone(),
                    cut_at_punctuation: false,
                };

                let perf_start = Instant::now();

                let audio_for_whisper = cleaned_audio.clone();
                let (normalized, success) = {
                    let processor = processor.clone();
                    tokio::task::spawn_blocking(move || processor.process_audio(&audio_for_whisper))
                        .await??
                };

                if success {
                    play_done_sound(done_sound_data.clone(), &client_id, debug);
                } else { play_fail_sound(fail_sound_data.clone(), &client_id, debug); }

                let byte = if success { 0x03 } else { 0x04 };
                if let Err(e) = stream.write_all(&[byte]).await {
                    dt_error!("[{}] failed to send result notification: {}", client_id, e);
                }
                if let Err(e) = stream.flush().await {
                    dt_error!("[{}] failed to flush after result: {}", client_id, e);
                }

                if let Err(e) = save_audio_to_file(&cleaned_audio, &client_id) {
                    dt_error!("[{}] failed to save audio: {}", client_id, e);
                }

                processor.log_benchmark(perf_start, cleaned_audio.len());
                audio_buffer.clear();

                dt_info!("[{}] PTT processing complete, ready for next recording", client_id);
            }
            _ => {
                dt_error!("[{}] unexpected PTT message type 0x{:02x}", client_id, msg_type);
                break;
            }
        }
    }

    dt_info!("🚫 ❌ {} Disconnected!", client_id);
    Ok(())
}



// ESP32 clients are simplified – VAD handled on server
async fn handle_client_esp_async(
    mut stream: tokio::net::TcpStream,
    mut wake_model: OwwModel,
    whisper_ctx: Arc<WhisperContext>,
    client_id: String,
    debug: bool,
    _cooldown_secs: u64,
    beam_size: i32,
    temperature: f32,
    language: Option<String>,
    threads: i32,
    sound_data: Vec<u8>,
    done_sound_data: Vec<u8>,
    fail_sound_data: Vec<u8>,
    exec_command: Option<String>,
    translate_to_shell: bool,
    room: String,
    sender_ip: String,
    whisper_model_path: String,
) -> Result<()> {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    enum State {
        Normal,
        Recording {
            buffer: Vec<f32>,
            start: Instant,
            last_speech: Instant,
            duration: Duration,
            timeout: Duration,
            threshold: f32,
        },
        Cooldown { until: Instant },
    }

    const SAMPLE_RATE: u32 = 16000;
    const WINDOW_SECONDS: f64 = 0.5;

    let mut state = State::Normal;
    let mut last_detection: Option<Instant> = None;

    loop {
        let len = match stream.read_u32_le().await {
            Ok(l) => l as usize,
            Err(e) => {
                dt_error!("[{}] Failed to read length: {} – client disconnected", client_id, e);
                break;
            }
        };

        let mut sample_bytes = vec![0u8; len * 4];
        if let Err(e) = stream.read_exact(&mut sample_bytes).await {
            dt_error!("[{}] Failed to read samples: {}", client_id, e);
            break;
        }

        let samples: Vec<f32> = sample_bytes
            .chunks_exact(4)
            .map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]]))
            .collect();

        match state {
            State::Normal => {
                if samples.len() != OWW_MODEL_CHUNK_SIZE {
                    dt_warning!(
                        "[{}] Warning: received chunk of size {}, expected {}",
                        client_id, samples.len(), OWW_MODEL_CHUNK_SIZE
                    );
                }

                let detection = wake_model.detection(samples.clone());

                if detection.detected {
                    if let Some(last) = last_detection {
                        if last.elapsed() < Duration::from_secs_f64(COOLDOWN_SECS) {
                            continue;
                        }
                    }

                    dt_info!("💥 DETECTED! {} Probability: {:.4}", client_id, detection.probability);
                    last_detection = Some(Instant::now());

                    if let Err(e) = stream.write_all(&[0x01]).await {
                        dt_error!("[{}] Failed to send detection notification: {}", client_id, e);
                    }
                    if let Err(e) = stream.flush().await {
                        dt_error!("[{}] Failed to flush after detection: {}", client_id, e);
                    }

                    play_sound_in_background(sound_data.clone(), &client_id, debug, "awake sound");

                    let mut buffer = Vec::with_capacity((ESP_MAX_DURATION_SECS * SAMPLE_RATE as f64) as usize);
                    buffer.extend(samples);
                    let start = Instant::now();
                    let last_speech = Instant::now();
                    let duration = Duration::from_secs_f64(ESP_MAX_DURATION_SECS);
                    let timeout = Duration::from_secs_f64(ESP_SILENCE_TIMEOUT_SECS);
                    let threshold = ESP_SILENCE_THRESHOLD;
                    state = State::Recording { buffer, start, last_speech, duration, timeout, threshold };
                }
            }
            State::Recording {
                mut buffer,
                start,
                mut last_speech,
                duration,
                timeout,
                threshold,
            } => {
                buffer.extend(samples);

                let stop = if start.elapsed() >= duration {
                    true
                } else {
                    let window_samples = (WINDOW_SECONDS * SAMPLE_RATE as f64) as usize;
                    if buffer.len() >= window_samples {
                        let window_start = buffer.len() - window_samples;
                        let window = &buffer[window_start..];
                        let rms = rms_f32(window);
                        if debug { dt_debug!("[{}] RMS: {:.6}", client_id, rms); }
                        if rms > threshold {
                            last_speech = Instant::now();
                        }
                        if last_speech.elapsed() > timeout {
                            true
                        } else { false }
                    } else { false }
                };

                if stop {
                    let duration_secs = buffer.len() as f64 / SAMPLE_RATE as f64;
                    dt_info!("[{}] finished recording ({} samples, {:.2}s)", client_id, buffer.len(), duration_secs);

                    if let Err(e) = save_audio_to_file(&buffer, &client_id) {
                        dt_error!("[{}] failed to save audio: {}", client_id, e);
                    }

                    if let Err(e) = stream.write_all(&[0x02]).await {
                        dt_error!("[{}] failed to send 0x02 to client: {}", client_id, e);
                    }
                    if let Err(e) = stream.flush().await {
                        dt_error!("[{}] failed to flush after 0x02: {}", client_id, e);
                    }

                    let mut transcription_audio = buffer;
                    {
                        let trim_seconds = ESP_SILENCE_TIMEOUT_SECS + ESP_ADDITIONAL_SILENCE_TRIM as f64;
                        let trim_samples = (trim_seconds * SAMPLE_RATE as f64) as usize;
                        if transcription_audio.len() > trim_samples {
                            transcription_audio.truncate(transcription_audio.len() - trim_samples);
                            dt_debug!("[{}] Trimmed trailing silence ({:.2}s, {} samples)",
                                client_id, trim_seconds, trim_samples);
                        } else { dt_info!("[{}] Buffer too short to trim – sending as is", client_id); }
                    }

                    let processor = TranscriptionProcessor {
                        whisper_ctx: whisper_ctx.clone(),
                        beam_size,
                        temperature,
                        language: language.clone(),
                        threads,
                        exec_command: exec_command.clone(),
                        translate_to_shell,
                        room: room.clone(),
                        done_sound: done_sound_data.clone(),
                        fail_sound: fail_sound_data.clone(),
                        debug,
                        model_path: whisper_model_path.clone(),
                        sender_ip: sender_ip.clone(),
                        client_id: client_id.clone(),
                        cut_at_punctuation: ESP_CUT_TRANSCRIPTION_AT_PUNCTUATION,
                    };

                    let perf_start = Instant::now();
                    dt_info!("[{}] Sending to Whisper: {} samples ({:.2}s)",
                        client_id, transcription_audio.len(),
                        transcription_audio.len() as f64 / SAMPLE_RATE as f64);

                    let audio_clone = transcription_audio.clone();
                    let (normalized, success) = {
                        let processor = processor.clone();
                        tokio::task::spawn_blocking(move || processor.process_audio(&audio_clone))
                            .await??
                    };

                    if success {
                        play_done_sound(done_sound_data.clone(), &client_id, debug);
                    } else {
                        play_fail_sound(fail_sound_data.clone(), &client_id, debug);
                    }

                    let byte = if success { 0x03 } else { 0x04 };
                    if let Err(e) = stream.write_all(&[byte]).await {
                        dt_error!("[{}] failed to send notification to client: {}", client_id, e);
                    }
                    if let Err(e) = stream.flush().await {
                        dt_error!("[{}] failed to flush after notification: {}", client_id, e);
                    }

                    processor.log_benchmark(perf_start, transcription_audio.len());

                    reset_wake_model(&mut wake_model, 10);

                    let cooldown_until = Instant::now() + Duration::from_secs_f64(COOLDOWN_SECS);
                    state = State::Cooldown { until: cooldown_until };
                } else {
                    state = State::Recording {
                        buffer,
                        start,
                        last_speech,
                        duration,
                        timeout,
                        threshold,
                    };
                }
            }
            State::Cooldown { until } => {
                if Instant::now() >= until {
                    state = State::Normal;
                }
            }
        }
    }

    dt_info!("🚫 ❌ {} Disconnected!", client_id);
    Ok(())
}

fn print_usage(program_name: &str) {
    dt_error!(
        "Usage: {} [OPTIONS]\n\
         Options:\n\
         --host <ADDRESS>         Listening address (default: 0.0.0.0:12345)\n\
         --awake-sound <PATH>     Path to WAV file to play on wake (default: ding)\n\
         --wake-word <PATH>       Path to wake word model (default: yo_bitch.onnx)\n\
         --done-sound <PATH>      Path to WAV file to play after successful command execution (default: done)\n\
         --fail-sound <PATH>      Path to WAV file to play after failed command execution (default: fail)\n\
         --threshold <FLOAT>      Detection threshold (default: 0.5)\n\
         --model <PATH>           Path to Whisper model (default: ./ggml-tiny.bin)\n\
         --cooldown <SECONDS>     Cooldown between detections (default: auto)\n\
         --beam-size <INT>        Beam size for Whisper (0 = greedy, >0 = beam search, default: 5)\n\
         --temperature <FLOAT>    Whisper temperature (default: 0.2)\n\
         --language <LANG>        Language code (e.g., sv, en) or 'auto' (default: en)\n\
         --threads <INT>          Number of threads for Whisper (default: 4)\n\
         --exec-command <CMD>     Command to execute with transcribed text as argument (default: none)\n\
         --tts-model <PATH>       Path to TTS ONNX model (default: ./models/tts/en_US-amy-medium.onnx)\n\
         --debug                  Enable debug logging\n\
         --help, -h               Show this help message",
        program_name
    );
}

async fn handle_new_client_async(
    mut stream: tokio::net::TcpStream,
    debug: bool,
    cooldown_secs: u64,
    beam_size: i32,
    temperature: f32,
    language: Option<String>,
    threads: i32,
    exec_command: Option<String>,
    translate_to_shell: bool,
    sound_data: Vec<u8>,
    done_sound_data: Vec<u8>,
    fail_sound_data: Vec<u8>,
    whisper_ctx: Arc<WhisperContext>,
    whisper_model_path: String,
    custom_wake_word_provided: bool,
    wake_word_path: String,
    threshold: f32,
    client_registry: Arc<Mutex<ClientRegistry>>,
) -> Result<()> {
    use tokio::io::AsyncReadExt;

    let peer_addr = match stream.peer_addr() {
        Ok(addr) => addr.to_string(),
        Err(_) => "unknown".to_string(),
    };
    let peer_ip = peer_addr.split(':').next().unwrap_or("127.0.0.1").to_string();

    let room_len = stream.read_u32_le().await.unwrap_or(0) as usize;
    let room = if room_len > 0 {
        let mut room_buf = vec![0u8; room_len];
        if let Err(e) = stream.read_exact(&mut room_buf).await {
            dt_error!("[{}] Failed to read room: {} – using empty", peer_addr, e);
            String::new()
        } else { String::from_utf8_lossy(&room_buf).to_string() }
    } else { String::new() };

    let display_id = if room.is_empty() {
        format!("client @ {}", peer_addr)
    } else { format!("room '{}'", room) };
    dt_info!("📡 ☑️ 🎙️ {} Connected [{}]", display_id, peer_addr);

    if room == "intercom" {
        let std_stream = stream.into_std()?;
        std_stream.set_nonblocking(false)?;
        let room_clone = room.clone();
        let ip_for_removal = peer_ip.clone();
        let registry = client_registry.clone();
        let display_id_clone = display_id.clone();
        let esp_ip = peer_ip.clone();
        tokio::task::spawn_blocking(move || {
            if let Err(e) = handle_intercom(std_stream, display_id_clone, debug, room_clone.clone(), esp_ip) {
                dt_error!("[{}] Intercom error: {}", display_id, e);
            }
            let mut reg = registry.lock().unwrap_or_else(|p| p.into_inner());
            reg.remove_connection(&room_clone, &ip_for_removal);
        });
        return Ok(());
    }


    if room == "oneshot" {
        let registry_room = "esp".to_string();
        {
            let mut reg = client_registry.lock().unwrap();
            reg.add_connection(&registry_room, &peer_ip);
        }

        let sender_ip = peer_ip.clone();
        let room_clone = room.clone();
        let registry = client_registry.clone();
        let ip_clone = peer_ip.clone();
        let display_id_clone = display_id.clone();
        let whisper_model_path_clone = whisper_model_path.clone();

        tokio::spawn(async move {
            if let Err(e) = handle_ptt_async(
                stream,
                whisper_ctx,
                display_id_clone,
                debug,
                beam_size,
                temperature,
                language,
                threads,
                exec_command,
                translate_to_shell,
                room_clone,
                sound_data,
                done_sound_data,
                fail_sound_data,
                sender_ip,
                whisper_model_path_clone,
            ).await { dt_error!("[{}] PTT handler error: {}", display_id, e); }
            let mut reg = registry.lock().unwrap_or_else(|p| p.into_inner());
            reg.remove_connection(&registry_room, &ip_clone);
        });
        return Ok(());
    }

    if !room.is_empty() {
        let mut reg = client_registry.lock().unwrap();
        reg.add_connection(&room, &peer_ip);
    }

    let wake_model = if custom_wake_word_provided {
        match OwwModel::from_path(&wake_word_path, threshold) {
            Ok(m) => m,
            Err(e) => {
                dt_error!("[{}] Failed to load wake model from {}: {}", display_id, wake_word_path, e);
                if !room.is_empty() {
                    let mut reg = client_registry.lock().unwrap();
                    reg.remove_connection(&room, &peer_ip);
                }
                return Ok(());
            }
        }
    } else {
        match OwwModel::from_bytes(DEFAULT_WAKE_MODEL, threshold) {
            Ok(m) => m,
            Err(e) => {
                dt_error!("[{}] Failed to load embedded wake model: {}", display_id, e);
                if !room.is_empty() {
                    let mut reg = client_registry.lock().unwrap();
                    reg.remove_connection(&room, &peer_ip);
                }
                return Ok(());
            }
        }
    };

    let room_clone = room.clone();
    let ip_clone = peer_ip.clone();
    let ip_for_removal = ip_clone.clone();
    let registry = client_registry.clone();
    let display_id_clone = display_id.clone();
    let whisper_model_path_clone = whisper_model_path.clone();

    tokio::spawn(async move {
        let result = if room_clone == "esp" {
            handle_client_esp_async(
                stream,
                wake_model,
                whisper_ctx,
                display_id_clone,
                debug,
                cooldown_secs,
                beam_size,
                temperature,
                language,
                threads,
                sound_data,
                done_sound_data,
                fail_sound_data,
                exec_command,
                translate_to_shell,
                room_clone.clone(),
                ip_clone,
                whisper_model_path_clone,
            ).await
        } else {
            handle_client_async(
                stream,
                wake_model,
                whisper_ctx,
                display_id_clone,
                debug,
                cooldown_secs,
                beam_size,
                temperature,
                language,
                threads,
                sound_data,
                done_sound_data,
                fail_sound_data,
                exec_command,
                translate_to_shell,
                room_clone.clone(),
                ip_clone,
                whisper_model_path_clone,
            ).await
        };

        if let Err(e) = result {
            dt_error!("[{}] Handler error: {}", display_id, e);
        }

        if !room_clone.is_empty() {
            let mut reg = registry.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
            reg.remove_connection(&room_clone, &ip_for_removal);
        }
    });

    Ok(())
}


#[tokio::main]
async fn main() -> Result<()> {
    env_logger::init();

    let args: Vec<String> = env::args().collect();

    if args.len() > 1 && (args[1] == "--help" || args[1] == "-h") {
        print_usage(&args[0]);
        return Ok(());
    }

    let mut host = LISTEN_ADDR.to_string();
    let mut sound_path: Option<String> = None;
    let mut done_sound_path: Option<String> = None;
    let mut fail_sound_path: Option<String> = None;
    let mut wake_word_path = String::new();
    let mut custom_wake_word_provided = false;
    let mut threshold = 0.5;
    let mut whisper_model_path = "./models/stt/ggml-tiny.bin".to_string();
    let mut cooldown_secs = 10;
    let mut debug = false;
    let mut beam_size = 5;
    let mut temperature = 0.2;
    let mut language = Some("sv".to_string());
    let mut threads = 4;
    let mut exec_command: Option<String> = None;
    let mut translate_to_shell = false;
    let mut tts_model_path = "./../models/tts/en_US-amy-medium.onnx".to_string();

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--host" => { if i+1 < args.len() { host = args[i+1].clone(); i += 2; } else { dt_error!("Missing value for --host"); std::process::exit(1); } }
            "--translate-to-shell" => { translate_to_shell = true; i += 1; }
            "--awake-sound" => { if i+1 < args.len() { sound_path = Some(args[i+1].clone()); i += 2; } else { dt_error!("Missing value for --awake-sound"); std::process::exit(1); } }
            "--done-sound" => { if i+1 < args.len() { done_sound_path = Some(args[i+1].clone()); i += 2; } else { dt_error!("Missing value for --done-sound"); std::process::exit(1); } }
            "--fail-sound" => { if i+1 < args.len() { fail_sound_path = Some(args[i+1].clone()); i += 2; } else { dt_error!("Missing value for --fail-sound"); std::process::exit(1); } }
            "--beam-size" => { if i+1 < args.len() { beam_size = args[i+1].parse().unwrap_or_else(|_| { dt_error!("Invalid beam size"); std::process::exit(1); }); i += 2; } else { dt_error!("Missing value for --beam-size"); std::process::exit(1); } }
            "--wake-word" => { if i+1 < args.len() { wake_word_path = args[i+1].clone(); custom_wake_word_provided = true; i += 2; } else { dt_error!("Missing value for --wake-word"); std::process::exit(1); } }
            "--threshold" => { if i+1 < args.len() { threshold = args[i+1].parse().unwrap_or_else(|_| { dt_error!("Invalid threshold"); std::process::exit(1); }); i += 2; } else { dt_error!("Missing value for --threshold"); std::process::exit(1); } }
            "--model" => { if i+1 < args.len() { whisper_model_path = args[i+1].clone(); i += 2; } else { dt_error!("Missing value for --model"); std::process::exit(1); } }
            "--cooldown" => { if i+1 < args.len() { cooldown_secs = args[i+1].parse().unwrap_or_else(|_| { dt_error!("Invalid cooldown"); std::process::exit(1); }); i += 2; } else { dt_error!("Missing value for --cooldown"); std::process::exit(1); } }
            "--temperature" => { if i+1 < args.len() { temperature = args[i+1].parse().unwrap_or_else(|_| { dt_error!("Invalid temperature"); std::process::exit(1); }); i += 2; } else { dt_error!("Missing value for --temperature"); std::process::exit(1); } }
            "--language" => { if i+1 < args.len() { let lang = args[i+1].clone(); language = if lang == "auto" { None } else { Some(lang) }; i += 2; } else { dt_error!("Missing value for --language"); std::process::exit(1); } }
            "--threads" => { if i+1 < args.len() { threads = args[i+1].parse().unwrap_or_else(|_| { dt_error!("Invalid threads"); std::process::exit(1); }); i += 2; } else { dt_error!("Missing value for --threads"); std::process::exit(1); } }
            "--exec-command" => { if i+1 < args.len() { exec_command = Some(args[i+1].clone()); i += 2; } else { dt_error!("Missing value for --exec-command"); std::process::exit(1); } }
            "--tts-model" => { if i+1 < args.len() { tts_model_path = args[i+1].clone(); i += 2; } else { dt_error!("Missing value for --tts-model"); std::process::exit(1); } }
            "--debug" => { debug = true; i += 1; }
            _ => { dt_error!("Unknown argument: {}", args[i]); std::process::exit(1); }
        }
    }

    if debug { std::env::set_var("DT_LOG_LEVEL", "DEBUG"); }
    dt_setup(None, None);

    let done_sound_data = if let Some(ref path) = done_sound_path {
        match std::fs::read(path) { Ok(data) => { dt_info!("Loaded custom done sound from {}", path); data }, Err(e) => { dt_error!("Failed to read done sound file '{}': {}. Using embedded sound.", path, e); DONE_WAV.to_vec() } }
    } else { DONE_WAV.to_vec() };

    let fail_sound_data = if let Some(ref path) = fail_sound_path {
        match std::fs::read(path) { Ok(data) => { dt_info!("Loaded custom fail sound from {}", path); data }, Err(e) => { dt_error!("Failed to read fail sound file '{}': {}. Using embedded sound.", path, e); FAIL_WAV.to_vec() } }
    } else { FAIL_WAV.to_vec() };

    let sound_data = if let Some(ref path) = sound_path {
        match std::fs::read(path) { Ok(data) => { dt_info!("Loaded custom awake sound from {}", path); data }, Err(e) => { dt_error!("Failed to read awake sound file '{}': {}. Using embedded sound.", path, e); DING_WAV.to_vec() } }
    } else { DING_WAV.to_vec() };

    let listener = tokio::net::TcpListener::bind(&host).await?;

    let done_sound_display = done_sound_path.as_deref().unwrap_or("done.wav (embedded)");
    let fail_sound_display = fail_sound_path.as_deref().unwrap_or("fail.wav (embedded)");
    let awake_sound_display = sound_path.as_deref().unwrap_or("ding.wav (embedded)");
    let exec_display = exec_command.as_deref().unwrap_or("none");
    let wake_word_display = if custom_wake_word_provided { wake_word_path.as_str() } else { "yo_bitch" };

    dt_info!(
        r#"Settings:
      Host:           {}
      Debug:          {}
      Wake word:      {}
      Threshold:      {}
      Whisper model:  {}
      TTS model:      {}
      Temperature:    {}
      Language:       {}
      Threads:        {}
      Awake sound:    {}
      Done sound:     {}
      Fail sound:     {}
      Exec command:   {}
      Translate to shell: {}"#,
        host, debug, wake_word_display, threshold, whisper_model_path, tts_model_path,
        temperature, language.as_deref().unwrap_or("auto"), threads,
        awake_sound_display, done_sound_display, fail_sound_display, exec_display,
        translate_to_shell,
    );

    let whisper_ctx = Arc::new(WhisperContext::new_with_params(
        &whisper_model_path,
        WhisperContextParameters::default(),
    )?);

    let client_registry = Arc::new(Mutex::new(ClientRegistry::new()));
 
    loop {
        let (stream, _) = listener.accept().await?;
    
        let wake_word_path_clone = wake_word_path.clone();
        let sound_data = sound_data.clone();
        let done_sound_data = done_sound_data.clone();
        let fail_sound_data = fail_sound_data.clone();
        let exec_command = exec_command.clone();
        let whisper_ctx = Arc::clone(&whisper_ctx);
        let language = language.clone();
        let client_registry = Arc::clone(&client_registry);
        let whisper_model_path = whisper_model_path.clone();
    
        tokio::spawn(handle_new_client_async(
            stream,
            debug,
            cooldown_secs,
            beam_size,
            temperature,
            language,
            threads,
            exec_command,
            translate_to_shell,
            sound_data,
            done_sound_data,
            fail_sound_data,
            whisper_ctx,
            whisper_model_path,
            custom_wake_word_provided,
            wake_word_path_clone,
            threshold,
            client_registry,
        ));
    }
}
