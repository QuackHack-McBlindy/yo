use std::{
    env,
    io::{self, Write},
    process::{Command, Stdio},
    os::unix::net::UnixStream,
};
use ducktrace_logger::*;

struct Args {
    text: String,
    model: String,
    blocking: bool,
    path: Option<String>,
    length_scale: f64,
}

fn parse_args() -> Args {
    let mut args = env::args().skip(1).peekable();
    let mut text = None;
    let mut model = None;
    let mut blocking = false;
    let mut path = None;
    let mut length_scale = 1.0;

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--text" => {
                let value = args.next().expect("Missing value for --text");
                if text.is_some() {
                    eprintln!("🦆 says ⮞ fuck ❌ Duplicate --text provided");
                    std::process::exit(1);
                }
                text = Some(value);
            }
            "--model" => {
                let value = args.next().expect("Missing value for --model");
                if model.is_some() {
                    eprintln!("🦆 says ⮞ fuck ❌ Duplicate --model provided");
                    std::process::exit(1);
                }
                model = Some(value);
            }
            "--blocking" => {
                match args.peek() {
                    Some(next) if !next.starts_with('-') => {
                        let value = args.next().unwrap();
                        blocking = value.parse::<bool>().unwrap_or_else(|_| {
                            eprintln!("🦆 says ⮞ fuck ❌ Invalid value for --blocking: {}", value);
                            std::process::exit(1);
                        });
                    }
                    _ => blocking = true,
                }
            }
            "--path" => {
                let value = args.next().expect("Missing value for --path");
                if path.is_some() {
                    eprintln!("🦆 says ⮞ fuck ❌ Duplicate --path provided");
                    std::process::exit(1);
                }
                path = Some(value);
            }
            "--length-scale" => {
                let value = args.next().expect("Missing value for --length-scale");
                length_scale = value.parse::<f64>().unwrap_or_else(|_| {
                    eprintln!("🦆 says ⮞ fuck ❌ Invalid floating point value for --length-scale: {}", value);
                    std::process::exit(1);
                });
            }
            _ => {
                eprintln!("🦆 says ⮞ fuck ❌ Unknown argument: {}", arg);
                std::process::exit(1);
            }
        }
    }

    let text = text.unwrap_or_else(|| {
        eprintln!("🦆 says ⮞ fuck ❌ Missing required argument: --text");
        std::process::exit(1);
    });

    let model = model.unwrap_or_else(|| {
        eprintln!("🦆 says ⮞ fuck ❌ Missing required argument: --model");
        std::process::exit(1);
    });

    Args { text, model, blocking, path, length_scale }
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

fn convert_wav(input: &str) -> io::Result<()> {
    let output = format!("{}_converted.wav", input);

    let status = Command::new("ffmpeg")
        .args([
            "-y",
            "-i", input,
            "-ar", "16000",
            "-ac", "2",
            "-sample_fmt", "s16",
            &output,
        ])
        .status()?;

    if !status.success() {
        eprintln!("ffmpeg conversion failed: {}", status);
    } else {
        dt_info!("Converted file saved as: {}", output);
    }
    Ok(())
}

fn convert_and_replace(path: &str) -> io::Result<()> {
    let temp = format!("{}.tmp", path);
    let status = Command::new("ffmpeg")
        .args([
            "-y",
            "-i", path,
            "-ar", "16000",
            "-ac", "2",
            "-sample_fmt", "s16",
            &temp,
        ])
        .status()?;
    if status.success() {
        std::fs::rename(&temp, path)?;
        dt_info!("Converted and replaced: {}", path);
    } else {
        eprintln!("ffmpeg conversion failed");
    }
    Ok(())
}


fn main() -> io::Result<()> {
    let args = parse_args();

    if try_broadcast(&args.text) {
        return Ok(());
    }

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

    run_piper_to_file(&args.model, &args.text, &path, args.length_scale)?;

    if args.blocking {
        play_file(&path, true)?;
        convert_and_replace(&path)?;
        if is_temp {
            std::fs::remove_file(&path)?;
            dt_info!("Removed temporary file: {}", path);
        }
    } else {
        let mut cmd = if is_temp {
            Command::new("sh")
                .arg("-c")
                .arg(format!(
                    "aplay '{}' && ffmpeg -y -i '{}' -ar 16000 -ac 2 -sample_fmt s16 '{}.tmp' && mv '{}.tmp' '{}' && rm '{}'",
                    path, path, path, path, path, path
                ))
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()?
        } else {
            Command::new("sh")
                .arg("-c")
                .arg(format!(
                    "aplay '{}' && ffmpeg -y -i '{}' -ar 16000 -ac 2 -sample_fmt s16 '{}.tmp' && mv '{}.tmp' '{}'",
                    path, path, path, path
                ))
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()?
        };
        dt_debug!("Playing and converting in background (file: {})", path);
    }

    Ok(())
}

fn run_piper_to_file(model: &str, text: &str, path: &str, length_scale: f64) -> io::Result<()> {
    dt_debug!("Running piper with:");
    dt_debug!("  model: {}", model);
    dt_debug!("  text: {}", text);
    dt_debug!("  output file: {}", path);
    dt_debug!("  length scale: {}", length_scale);
    dt_debug!("  command: piper --length-scale {} -m {} -f {} \"{}\"", length_scale, model, path, text);

    let status = Command::new("piper")
        .arg("--length-scale")
        .arg(length_scale.to_string())
        .arg("-m")
        .arg(model)
        .arg("-f")
        .arg(path)
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
