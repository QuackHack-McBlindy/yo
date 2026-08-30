use std::io::Write;
use std::net::TcpStream;
use std::thread;
use std::io::Cursor;
use std::env;
use std::fs;
use std::path::PathBuf;
use std::fs::File;
use rodio::OutputStream;
use anyhow::Result;
use ducktrace_logger::*;
use tokio::io::AsyncWriteExt;

pub fn play_sound_in_background(
    data: Vec<u8>,
    client_id: &str,
    debug: bool,
    description: &str,
) {
    let id = client_id.to_string();
    let desc = description.to_string();
    thread::spawn(move || {
        if let Ok((_stream, handle)) = OutputStream::try_default() {
            let cursor = Cursor::new(data);
            if let Ok(sink) = handle.play_once(cursor) {
                sink.sleep_until_end();
            }
            if debug {
                dt_debug!("[{}] finished playing {}", id, desc);
            }
        } else if debug {
            dt_error!("[{}] failed to open audio output for {}", id, desc);
        }
    });
}

pub fn play_done_sound(data: Vec<u8>, client_id: &str, debug: bool) {
    play_sound_in_background(data, client_id, debug, "done sound");
}

pub fn play_fail_sound(data: Vec<u8>, client_id: &str, debug: bool) {
    play_sound_in_background(data, client_id, debug, "fail sound");
}

pub fn send_notification(stream: &mut TcpStream, byte: u8) -> Result<()> {
    stream.write_all(&[byte])?;
    stream.flush()?;
    Ok(())
}

pub async fn send_notification_async(
    stream: &mut tokio::net::TcpStream,
    byte: u8,
) -> Result<()> {
    stream.write_all(&[byte]).await?;
    stream.flush().await?;
    Ok(())
}

pub fn normalize_transcription(text: &str) -> String {
    text.trim()
        .to_lowercase()
        .chars()
        .filter(|c| {
            c.is_alphanumeric() || c.is_whitespace() || *c == '-' || *c == '_'
        })
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<&str>>()
        .join(" ")
}

pub fn write_last_sender_ip(ip: &str) {
    let home = env::var("HOME").unwrap_or_else(|_| ".".to_string());
    let dir = PathBuf::from(&home).join(".config/yo");
    let _ = fs::create_dir_all(&dir);
    let dest = dir.join("last_sender_ip");
    let tmp = dest.with_extension(".tmp");
    if let Ok(mut f) = File::create(&tmp) {
        let _ = writeln!(f, "{}", ip);
        let _ = fs::rename(&tmp, &dest);
    }
}
