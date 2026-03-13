use std::{
    io::{self, Write},
    process::{Command, Stdio},
    os::unix::net::UnixStream,
};
use clap::Parser;
use ducktrace_logger::*;
use tempfile::NamedTempFile;

#[derive(Parser)]
#[command(author, version, about, long_about = None)]
struct Args {
    text_pos: Option<String>,

    #[arg(long)]
    text: Option<String>,

    #[arg(long, required = true)]
    model: String,

    #[arg(long, num_args = 0..=1, default_missing_value = "true")]
    blocking: Option<bool>,

    #[arg(long)]
    path: Option<String>,
}

fn try_broadcast(text: &str) -> bool {
    if let Ok(mut stream) = UnixStream::connect("/tmp/yo-tts.sock") {
        if stream.write_all(text.as_bytes()).is_ok() && stream.flush().is_ok() {
            dt_info!("Broadcasted TTS via Unix socket");
            return true;
        }
    }
    false
}

fn main() -> io::Result<()> {
    let args = Args::parse();

    let text = match (args.text, args.text_pos) {
        (Some(t), None) | (None, Some(t)) => t,
        (Some(_), Some(_)) => {
            eprintln!("🦆 says ⮞ fuck ❌ Both --text and positional text provided. Please use only one.");
            std::process::exit(1);
        }
        (None, None) => {
            eprintln!("🦆 says ⮞ fuck ❌ No text provided. Usage: yo-say [--text] <text> [options]");
            std::process::exit(1);
        }
    };

    if try_broadcast(&text) {
        return Ok(());
    }

    let blocking = args.blocking.unwrap_or(false);

    let (path, is_temp) = match args.path {
        Some(p) => (p, false),
        None => {
            let temp_file = tempfile::Builder::new()
                .suffix(".wav")
                .tempfile()?;

            let temp_path = temp_file.into_temp_path();
            let path_buf = temp_path.keep()?;
            let path_str = path_buf.to_string_lossy().into_owned();
            (path_str, true)
        }
    };

    run_piper_to_file(&args.model, &text, &path)?;

    if blocking {
        play_file(&path, true)?;
        if is_temp {
            std::fs::remove_file(&path)?;
            dt_info!("Removed temporary file: {}", path);
        }
    } else {
        if is_temp {
            let mut child = Command::new("sh")
                .arg("-c")
                .arg(format!("aplay '{}' && rm '{}'", path, path))
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()?;
            dt_debug!("Playing in background (file: {}, will be auto‑deleted)", path);
        } else { play_file(&path, false)?; }
    }

    Ok(())
}

fn run_piper_to_file(model: &str, text: &str, path: &str) -> io::Result<()> {
    let status = Command::new("piper")
        .arg("-m")
        .arg(model)
        .arg("-f")
        .arg(path)
        .arg("--text")
        .arg(text)
        .status()?;

    if !status.success() {
        dt_info!("Piper failed with exit code: {:?}", status.code());
        std::process::exit(status.code().unwrap_or(1));
    }
    Ok(())
}

fn play_file(path: &str, blocking: bool) -> io::Result<()> {
    let mut player = Command::new("aplay")
        .arg(path)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;

    if blocking {
        let status = player.wait()?;
        if !status.success() {
            dt_info!("aplay failed with exit code: {:?}", status.code());
            std::process::exit(status.code().unwrap_or(1));
        }
    } else { dt_debug!("Playing in background (file: {})", path); }

    Ok(())
}
