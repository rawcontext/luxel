use serde::{Deserialize, Serialize};
use uuid::Uuid;

pub const PROTOCOL_VERSION: u32 = 1;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Request {
    pub protocol_version: u32,
    #[serde(rename = "requestID")]
    pub request_id: Uuid,
    pub command: Command,
    pub arguments: Arguments,
    pub output: OutputOptions,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum Command {
    Record,
    Stop,
    Toggle,
    Clip,
    Latest,
    Preferences,
    Editor,
    Convert,
    Export,
    Transcribe,
    AccessAdd,
    AccessCheck,
    AccessList,
    AccessRevoke,
    Doctor,
    Cancel,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Arguments {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub recording: Option<RecordingArguments>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub clip: Option<ClipArguments>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub latest: Option<LatestArguments>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub preferences: Option<PreferencesArguments>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub editor: Option<EditorArguments>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub convert: Option<ConvertArguments>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub export: Option<ExportArguments>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub transcribe: Option<TranscribeArguments>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub access: Option<AccessArguments>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cancel: Option<CancelArguments>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct RecordingArguments {
    pub target: CaptureTarget,
    #[serde(rename = "displayID", skip_serializing_if = "Option::is_none")]
    pub display_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub preset: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub frames_per_second: Option<u32>,
    pub matches_display_frame_rate: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub countdown_seconds: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub output_directory_path: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum CaptureTarget {
    Display,
    ActiveWindow,
    LastArea,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ClipArguments {
    pub seconds: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LatestArguments {
    pub reveal: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PreferencesArguments {
    pub pane: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct EditorArguments {
    pub input_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ConvertArguments {
    pub input_path: String,
    pub output_path: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub format: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub width: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub height: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub frames_per_second: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub start_seconds: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub end_seconds: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub duration_seconds: Option<f64>,
    pub speed: f64,
    pub mute: bool,
    pub crop_to_fill: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub crop: Option<CropRect>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub quality: Option<String>,
    pub overwrite: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CropRect {
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ExportArguments {
    pub request_path: String,
    pub output_path: String,
    pub overwrite: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct TranscribeArguments {
    pub input_path: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub locale: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub output_path: Option<String>,
    pub semantic_turns: bool,
    pub diarize: bool,
    pub format: TranscriptFormat,
    pub overwrite: bool,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum TranscriptFormat {
    Text,
    Json,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AccessArguments {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
    #[serde(rename = "grantID", skip_serializing_if = "Option::is_none")]
    pub grant_id: Option<Uuid>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CancelArguments {
    #[serde(rename = "jobID")]
    pub job_id: Uuid,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct OutputOptions {
    pub json: bool,
    pub progress: bool,
    pub quiet: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Event {
    pub protocol_version: u32,
    #[serde(rename = "requestID")]
    pub request_id: Uuid,
    pub sequence: u32,
    pub kind: EventKind,
    #[serde(rename = "jobID", default)]
    pub job_id: Option<Uuid>,
    #[serde(default)]
    pub progress: Option<Progress>,
    #[serde(default)]
    pub result: Option<ResultPayload>,
    #[serde(default)]
    pub error: Option<ErrorPayload>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum EventKind {
    Accepted,
    Progress,
    Result,
    Error,
    Canceled,
}

impl EventKind {
    pub fn is_terminal(self) -> bool {
        matches!(self, Self::Result | Self::Error | Self::Canceled)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Progress {
    pub phase: String,
    pub fraction: Option<f64>,
    pub message: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ResultPayload {
    #[serde(default)]
    pub file_path: Option<String>,
    #[serde(rename = "recordingID", default)]
    pub recording_id: Option<String>,
    #[serde(default)]
    pub text: Option<String>,
    #[serde(default)]
    pub content_type: Option<String>,
    #[serde(default)]
    pub export: Option<serde_json::Value>,
    #[serde(default)]
    pub doctor: Option<serde_json::Value>,
    #[serde(default)]
    pub grants: Option<Vec<serde_json::Value>>,
    #[serde(default)]
    pub grant: Option<serde_json::Value>,
    #[serde(default)]
    pub pairing: Option<PairingCredential>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PairingCredential {
    #[serde(rename = "clientID")]
    pub client_id: Uuid,
    pub secret: String,
    pub app_version: String,
    pub protocol_version: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ErrorPayload {
    pub code: String,
    pub message: String,
    #[serde(default)]
    pub recovery_command: Option<String>,
}
