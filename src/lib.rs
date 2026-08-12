#[cfg(not(target_os = "macos"))]
compile_error!("luxel-cli supports macOS only");

mod cli;
mod credentials;
pub mod protocol;
mod transport;

use std::{
    ffi::OsString,
    path::{Component, Path, PathBuf},
    process::Command as ProcessCommand,
    time::Duration,
};

use thiserror::Error;
use uuid::Uuid;

use cli::{AccessCommand, Fps};
pub use cli::{Cli, CliCommand};
use credentials::Credential;
use protocol::*;

pub fn normalize_aliases<I>(arguments: I) -> Vec<OsString>
where
    I: IntoIterator<Item = OsString>,
{
    arguments
        .into_iter()
        .map(|argument| match argument.to_str() {
            Some("-an") => OsString::from("--mute"),
            value => value.map_or(argument.clone(), OsString::from),
        })
        .collect()
}

pub fn run(cli: Cli) -> Result<(), CliError> {
    let scheme = std::env::var("LUXEL_URL_SCHEME").unwrap_or_else(|_| "luxel".into());
    if let CliCommand::Pair { name } = &cli.command {
        let name = name.clone().unwrap_or_else(default_client_name);
        let request_id = Uuid::new_v4();
        let events = transport::pair(
            request_id,
            &name,
            &scheme,
            Duration::from_secs(cli.timeout),
            open_luxel_url,
        )?;
        let pairing = events
            .last()
            .and_then(|event| event.result.as_ref())
            .and_then(|result| result.pairing.clone())
            .ok_or_else(|| remote_error(&events))?;
        credentials::save(&Credential::from(pairing))?;
        if !cli.quiet {
            println!("Paired with Luxel.");
        }
        return Ok(());
    }

    let request_id = Uuid::new_v4();
    let request = request_from_cli(request_id, &cli)?;
    let events = transport::invoke(
        request_id,
        serde_json::to_vec(&request)?,
        &credentials::load()?,
        &scheme,
        Duration::from_secs(cli.timeout),
        open_luxel_url,
    )?;
    render_events(&events, cli.json, cli.quiet)
}

fn request_from_cli(request_id: Uuid, cli: &Cli) -> Result<Request, CliError> {
    let (command, arguments) = match &cli.command {
        CliCommand::Pair { .. } => unreachable!(),
        CliCommand::Record(args) => (
            Command::Record,
            Arguments {
                recording: Some(recording(
                    args.target.display.as_deref(),
                    args.target.active_window,
                    args.target.last_area,
                    args.preset.clone(),
                    args.fps,
                    args.countdown,
                    args.save_to.as_deref(),
                )?),
                ..Default::default()
            },
        ),
        CliCommand::Stop => (Command::Stop, Default::default()),
        CliCommand::Toggle(args) => {
            let has_target =
                args.target.display.is_some() || args.target.active_window || args.target.last_area;
            let recording = has_target
                .then(|| {
                    recording(
                        args.target.display.as_deref(),
                        args.target.active_window,
                        args.target.last_area,
                        args.preset.clone(),
                        args.fps,
                        args.countdown,
                        args.save_to.as_deref(),
                    )
                })
                .transpose()?;
            (
                Command::Toggle,
                Arguments {
                    recording,
                    ..Default::default()
                },
            )
        }
        CliCommand::Clip { seconds } => (
            Command::Clip,
            Arguments {
                clip: Some(ClipArguments { seconds: *seconds }),
                ..Default::default()
            },
        ),
        CliCommand::Latest { reveal } => (
            Command::Latest,
            Arguments {
                latest: Some(LatestArguments { reveal: *reveal }),
                ..Default::default()
            },
        ),
        CliCommand::Preferences { pane } => (
            Command::Preferences,
            Arguments {
                preferences: Some(PreferencesArguments { pane: pane.clone() }),
                ..Default::default()
            },
        ),
        CliCommand::Editor { file } => (
            Command::Editor,
            Arguments {
                editor: Some(EditorArguments {
                    input_path: absolute_path(file)?,
                }),
                ..Default::default()
            },
        ),
        CliCommand::Convert(args) => {
            let (width, height) = resolved_size(args.width, args.height, args.size)?;
            let crop = args.crop.map(|(x, y, width, height)| CropRect {
                x,
                y,
                width,
                height,
            });
            (
                Command::Convert,
                Arguments {
                    convert: Some(ConvertArguments {
                        input_path: absolute_path(&args.input)?,
                        output_path: absolute_path(&args.output)?,
                        format: args.format.clone(),
                        width,
                        height,
                        frames_per_second: args.fps,
                        start_seconds: args.start,
                        end_seconds: args.end,
                        duration_seconds: args.duration,
                        speed: args.speed,
                        mute: args.mute,
                        crop_to_fill: args.crop_to_fill,
                        crop,
                        quality: args.quality.clone(),
                        overwrite: args.overwrite,
                    }),
                    ..Default::default()
                },
            )
        }
        CliCommand::Export(args) => (
            Command::Export,
            Arguments {
                export: Some(ExportArguments {
                    request_path: absolute_path(&args.request)?,
                    output_path: absolute_path(&args.output)?,
                    overwrite: args.overwrite,
                }),
                ..Default::default()
            },
        ),
        CliCommand::Transcribe(args) => (
            Command::Transcribe,
            Arguments {
                transcribe: Some(TranscribeArguments {
                    input_path: absolute_path(&args.file)?,
                    locale: args.locale.clone(),
                    output_path: args.output.as_deref().map(absolute_path).transpose()?,
                    semantic_turns: args.semantic_turns,
                    diarize: args.diarize,
                    format: if args.format == "json" {
                        TranscriptFormat::Json
                    } else {
                        TranscriptFormat::Text
                    },
                    overwrite: args.overwrite,
                }),
                ..Default::default()
            },
        ),
        CliCommand::Access(access) => match access {
            AccessCommand::Add { path } => (
                Command::AccessAdd,
                Arguments {
                    access: Some(AccessArguments {
                        path: Some(absolute_path(path)?),
                        grant_id: None,
                    }),
                    ..Default::default()
                },
            ),
            AccessCommand::Check { path } => (
                Command::AccessCheck,
                Arguments {
                    access: Some(AccessArguments {
                        path: Some(absolute_path(path)?),
                        grant_id: None,
                    }),
                    ..Default::default()
                },
            ),
            AccessCommand::List => (Command::AccessList, Default::default()),
            AccessCommand::Revoke { grant_id } => (
                Command::AccessRevoke,
                Arguments {
                    access: Some(AccessArguments {
                        path: None,
                        grant_id: Some(*grant_id),
                    }),
                    ..Default::default()
                },
            ),
        },
        CliCommand::Doctor => (Command::Doctor, Default::default()),
        CliCommand::Cancel { job_id } => (
            Command::Cancel,
            Arguments {
                cancel: Some(CancelArguments { job_id: *job_id }),
                ..Default::default()
            },
        ),
    };
    Ok(Request {
        protocol_version: PROTOCOL_VERSION,
        request_id,
        command,
        arguments,
        output: OutputOptions {
            json: cli.json,
            progress: !cli.quiet,
            quiet: cli.quiet,
        },
    })
}

fn recording(
    display: Option<&str>,
    active_window: bool,
    last_area: bool,
    preset: Option<String>,
    fps: Option<Fps>,
    countdown: Option<u32>,
    save_to: Option<&Path>,
) -> Result<RecordingArguments, CliError> {
    let (target, display_id) = if let Some(display) = display {
        (CaptureTarget::Display, Some(display.to_string()))
    } else if active_window {
        (CaptureTarget::ActiveWindow, None)
    } else if last_area {
        (CaptureTarget::LastArea, None)
    } else {
        return Err(CliError::Usage(
            "choose --display, --active-window, or --last-area".into(),
        ));
    };
    let (frames_per_second, matches_display_frame_rate) = match fps {
        Some(Fps::Fixed(value)) => (Some(value), false),
        Some(Fps::Display) => (None, true),
        None => (None, false),
    };
    Ok(RecordingArguments {
        target,
        display_id,
        preset,
        frames_per_second,
        matches_display_frame_rate,
        countdown_seconds: countdown,
        output_directory_path: save_to.map(absolute_path).transpose()?,
    })
}

fn resolved_size(
    width: Option<u32>,
    height: Option<u32>,
    size: Option<(u32, u32)>,
) -> Result<(Option<u32>, Option<u32>), CliError> {
    if let Some((size_width, size_height)) = size {
        if width.is_some_and(|value| value != size_width)
            || height.is_some_and(|value| value != size_height)
        {
            return Err(CliError::Usage("--width/--height conflict with -s".into()));
        }
        return Ok((
            Some(width.unwrap_or(size_width)),
            Some(height.unwrap_or(size_height)),
        ));
    }
    if width.is_some() != height.is_some() {
        return Err(CliError::Usage(
            "use both --width and --height, or neither".into(),
        ));
    }
    Ok((width, height))
}

fn absolute_path(path: &Path) -> Result<String, CliError> {
    let expanded = if let Some(value) = path.to_str().and_then(|value| value.strip_prefix("~/")) {
        PathBuf::from(
            std::env::var_os("HOME")
                .ok_or_else(|| CliError::Usage("HOME is unavailable".into()))?,
        )
        .join(value)
    } else if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir()?.join(path)
    };
    let mut normalized = PathBuf::new();
    for component in expanded.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => {
                normalized.pop();
            }
            other => normalized.push(other.as_os_str()),
        }
    }
    Ok(normalized.to_string_lossy().into_owned())
}

fn open_luxel_url(url: String) -> Result<(), CliError> {
    let bundle_id =
        std::env::var("LUXEL_BUNDLE_IDENTIFIER").unwrap_or_else(|_| "com.rawcontext.luxel".into());
    let status = ProcessCommand::new("/usr/bin/open")
        .args(["-b", &bundle_id, &url])
        .status()?;
    if status.success() {
        Ok(())
    } else {
        Err(CliError::AppUnavailable)
    }
}

fn default_client_name() -> String {
    let user = std::env::var("USER").unwrap_or_else(|_| "Terminal".into());
    format!("{user} in Terminal")
}

fn render_events(events: &[Event], json: bool, quiet: bool) -> Result<(), CliError> {
    let terminal = events
        .last()
        .ok_or_else(|| CliError::Protocol("Luxel returned no result".into()))?;
    match terminal.kind {
        EventKind::Error => Err(remote_error(events)),
        EventKind::Canceled => Err(CliError::Canceled),
        EventKind::Result if quiet => Ok(()),
        EventKind::Result if json => {
            println!("{}", serde_json::to_string_pretty(terminal)?);
            Ok(())
        }
        EventKind::Result => {
            let result = terminal.result.as_ref().cloned().unwrap_or_default();
            if let Some(text) = result.text {
                print!("{text}");
                if !text.ends_with('\n') {
                    println!();
                }
            } else if let Some(path) = result.file_path {
                println!("{path}");
            } else if let Some(id) = result.recording_id {
                println!("{id}");
            } else if let Some(value) = result.doctor.or(result.export).or(result.grant) {
                println!("{}", serde_json::to_string_pretty(&value)?);
            } else if let Some(values) = result.grants {
                println!("{}", serde_json::to_string_pretty(&values)?);
            }
            Ok(())
        }
        EventKind::Accepted | EventKind::Progress => Err(CliError::Protocol(
            "Luxel did not return a terminal result".into(),
        )),
    }
}

fn remote_error(events: &[Event]) -> CliError {
    let error = events.last().and_then(|event| event.error.as_ref());
    CliError::Remote {
        code: error
            .map(|error| error.code.clone())
            .unwrap_or_else(|| "command_failed".into()),
        message: error
            .map(|error| error.message.clone())
            .unwrap_or_else(|| "Luxel did not return a result".into()),
    }
}

#[derive(Debug, Error)]
pub enum CliError {
    #[error("{0}")]
    Usage(String),
    #[error("not paired; run `luxel pair`")]
    NotPaired,
    #[error("Luxel could not be opened")]
    AppUnavailable,
    #[error("credential error: {0}")]
    Credential(String),
    #[error("{message} ({code})")]
    Remote { code: String, message: String },
    #[error("timed out after {0} seconds waiting for Luxel")]
    Timeout(u64),
    #[error("command canceled")]
    Canceled,
    #[error("protocol error: {0}")]
    Protocol(String),
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
    #[error(transparent)]
    Url(#[from] url::ParseError),
}

impl CliError {
    pub fn exit_code(&self) -> i32 {
        match self {
            Self::Usage(_) => 2,
            Self::NotPaired => 3,
            Self::AppUnavailable => 4,
            Self::Credential(_) => 5,
            Self::Remote { code, .. } if code.contains("access") || code.contains("permission") => {
                6
            }
            Self::Remote { .. }
            | Self::Protocol(_)
            | Self::Io(_)
            | Self::Json(_)
            | Self::Url(_) => 7,
            Self::Timeout(_) => 8,
            Self::Canceled => 130,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::Parser;

    #[test]
    fn ffmpeg_style_mute_alias_is_normalized() {
        let cli = Cli::parse_from(normalize_aliases(
            ["luxel", "convert", "in.mp4", "out.mp4", "-an"].map(OsString::from),
        ));
        let CliCommand::Convert(convert) = cli.command else {
            panic!()
        };
        assert!(convert.mute);
    }

    #[test]
    fn shared_convert_fixture_decodes() {
        let request: Request =
            serde_json::from_str(include_str!("../protocol/v1/fixtures/convert-request.json"))
                .unwrap();
        assert_eq!(request.command, protocol::Command::Convert);
    }
}
