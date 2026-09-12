use std::path::PathBuf;

use clap::{Args, Parser, Subcommand};
use uuid::Uuid;

#[derive(Debug, Parser)]
#[command(
    name = "luxel",
    version,
    about = "Control the Luxel macOS app from Terminal"
)]
pub struct Cli {
    #[arg(long, global = true, help = "Print the terminal result as JSON")]
    pub json: bool,
    #[arg(long, global = true, help = "Suppress non-error output")]
    pub quiet: bool,
    #[arg(
        long,
        global = true,
        default_value_t = 3600,
        help = "Seconds to wait for Luxel"
    )]
    pub timeout: u64,
    #[command(subcommand)]
    pub command: CliCommand,
}

#[derive(Debug, Subcommand)]
pub enum CliCommand {
    #[command(about = "Pair this command with Luxel")]
    Pair {
        #[arg(long)]
        name: Option<String>,
    },
    #[command(about = "Start a recording")]
    Record(RecordArgs),
    #[command(about = "Stop the active recording")]
    Stop,
    #[command(about = "Start or stop recording")]
    Toggle(ToggleArgs),
    #[command(about = "Save a clip from Replay Buffer")]
    Clip {
        #[arg(long)]
        seconds: Option<u32>,
    },
    #[command(about = "Open or reveal the latest recording")]
    Latest {
        #[arg(long)]
        reveal: bool,
    },
    #[command(about = "Open Luxel settings")]
    Preferences {
        #[arg(long)]
        pane: Option<String>,
    },
    #[command(about = "Open a media file in Luxel's editor")]
    Editor { file: PathBuf },
    #[command(about = "Convert media through Luxel")]
    Convert(ConvertArgs),
    #[command(about = "Run a complete Luxel ExportRequest JSON document")]
    Export(ExportArgs),
    #[command(about = "Transcribe media locally through Luxel")]
    Transcribe(TranscribeArgs),
    #[command(subcommand, about = "Manage Luxel folder access")]
    Access(AccessCommand),
    #[command(about = "Report app, protocol, permission, and folder status")]
    Doctor,
    #[command(about = "Cancel an active command-line job")]
    Cancel { job_id: Uuid },
}

#[derive(Debug, Args)]
pub struct RecordArgs {
    #[command(flatten)]
    pub target: RequiredTarget,
    #[arg(long)]
    pub preset: Option<String>,
    #[arg(long, value_parser = parse_fps)]
    pub fps: Option<Fps>,
    #[arg(long, value_parser = clap::value_parser!(u32).range(0..=60))]
    pub countdown: Option<u32>,
    #[arg(long)]
    pub save_to: Option<PathBuf>,
}

#[derive(Debug, Args)]
#[group(id = "target", required = true, multiple = false)]
pub struct RequiredTarget {
    #[arg(long, num_args = 0..=1, default_missing_value = "main")]
    pub display: Option<String>,
    #[arg(long)]
    pub active_window: bool,
    #[arg(long)]
    pub last_area: bool,
}

#[derive(Debug, Args)]
pub struct ToggleArgs {
    #[command(flatten)]
    pub target: OptionalTarget,
    #[arg(long)]
    pub preset: Option<String>,
    #[arg(long, value_parser = parse_fps)]
    pub fps: Option<Fps>,
    #[arg(long, value_parser = clap::value_parser!(u32).range(0..=60))]
    pub countdown: Option<u32>,
    #[arg(long)]
    pub save_to: Option<PathBuf>,
}

#[derive(Debug, Args)]
#[group(id = "target", required = false, multiple = false)]
pub struct OptionalTarget {
    #[arg(long, num_args = 0..=1, default_missing_value = "main")]
    pub display: Option<String>,
    #[arg(long)]
    pub active_window: bool,
    #[arg(long)]
    pub last_area: bool,
}

#[derive(Debug, Clone, Copy)]
pub enum Fps {
    Fixed(u32),
    Display,
}

fn parse_fps(value: &str) -> Result<Fps, String> {
    if value.eq_ignore_ascii_case("display") {
        return Ok(Fps::Display);
    }
    let value: u32 = value
        .parse()
        .map_err(|_| "use display or a whole number from 1 to 120".to_string())?;
    if !(1..=120).contains(&value) {
        return Err("FPS must be from 1 to 120".into());
    }
    Ok(Fps::Fixed(value))
}

#[derive(Debug, Args)]
pub struct ConvertArgs {
    pub input: PathBuf,
    pub output: PathBuf,
    #[arg(long)]
    pub format: Option<String>,
    #[arg(long)]
    pub width: Option<u32>,
    #[arg(long)]
    pub height: Option<u32>,
    #[arg(short = 's', value_parser = parse_size)]
    pub size: Option<(u32, u32)>,
    #[arg(long, short = 'r')]
    pub fps: Option<u32>,
    #[arg(long, alias = "ss")]
    pub start: Option<f64>,
    #[arg(long, alias = "to")]
    pub end: Option<f64>,
    #[arg(long, alias = "t")]
    pub duration: Option<f64>,
    #[arg(long, default_value_t = 1.0)]
    pub speed: f64,
    #[arg(long)]
    pub mute: bool,
    #[arg(long)]
    pub crop_to_fill: bool,
    #[arg(long, value_parser = parse_crop)]
    pub crop: Option<(i32, i32, u32, u32)>,
    #[arg(long)]
    pub quality: Option<String>,
    #[arg(long, short = 'y')]
    pub overwrite: bool,
}

fn parse_size(value: &str) -> Result<(u32, u32), String> {
    let (width, height) = value.split_once(['x', 'X']).ok_or("use WIDTHxHEIGHT")?;
    Ok((
        width.parse().map_err(|_| "invalid width")?,
        height.parse().map_err(|_| "invalid height")?,
    ))
}

fn parse_crop(value: &str) -> Result<(i32, i32, u32, u32), String> {
    let values = value.split(',').collect::<Vec<_>>();
    if values.len() != 4 {
        return Err("use x,y,width,height".into());
    }
    Ok((
        values[0].parse().map_err(|_| "invalid x")?,
        values[1].parse().map_err(|_| "invalid y")?,
        values[2].parse().map_err(|_| "invalid width")?,
        values[3].parse().map_err(|_| "invalid height")?,
    ))
}

#[derive(Debug, Args)]
pub struct ExportArgs {
    pub request: PathBuf,
    pub output: PathBuf,
    #[arg(long, short = 'y')]
    pub overwrite: bool,
}

#[derive(Debug, Args)]
pub struct TranscribeArgs {
    pub file: PathBuf,
    #[arg(long)]
    pub locale: Option<String>,
    #[arg(long)]
    pub output: Option<PathBuf>,
    #[arg(long)]
    pub semantic_turns: bool,
    #[arg(long)]
    pub diarize: bool,
    #[arg(long, default_value = "text", value_parser = ["text", "json"])]
    pub format: String,
    #[arg(long, short = 'y')]
    pub overwrite: bool,
}

#[derive(Debug, Subcommand)]
pub enum AccessCommand {
    #[command(about = "Ask Luxel to grant access to a folder")]
    Add { path: PathBuf },
    #[command(about = "Check whether Luxel can access a path")]
    Check { path: PathBuf },
    #[command(about = "List Luxel's available folders")]
    List,
    #[command(about = "Revoke an additional folder grant")]
    Revoke { grant_id: Uuid },
}
