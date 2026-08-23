#!/usr/bin/env bash

set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOSITORY_ROOT="$(cd "${PACKAGE_ROOT}/../.." && pwd)"
FIXTURE_DIR="${PACKAGE_ROOT}/Tests/LuxelCoreTests/Fixtures/VoiceDetection"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

PYTHON="${PYTHON:-python3}"
FFMPEG="${FFMPEG:-ffmpeg}"
EXPECTED_FFMPEG_VERSION="8.1.2"
DATASET_REPOSITORY="hf-internal-testing/librispeech_asr_dummy"
DATASET_REVISION="5be91486e11a2d616f4ec5db8d3fd248585ac07a"
SOURCE_RECORDING_ID="1272-128104-0000"
SOURCE_SPEAKER_ID="1272"
SOURCE_CHAPTER_ID="128104"
SOURCE_TRANSCRIPT="MISTER QUILTER IS THE APOSTLE OF THE MIDDLE CLASSES AND WE ARE GLAD TO WELCOME HIS GOSPEL"
SOURCE_AUDIO_BYTE_COUNT="120041"
SOURCE_AUDIO_SHA256="4e25e22555cd16e90edb0a3b49fdcf1fe652b2a1250ab643634db33895c75b41"
SOURCE_ASSET_PATH="/cached-assets/${DATASET_REPOSITORY}/--/${DATASET_REVISION}/--/clean/validation/0/audio/audio.flac"
ROWS_URL="https://datasets-server.huggingface.co/rows?dataset=hf-internal-testing%2Flibrispeech_asr_dummy&config=clean&split=validation&offset=0&length=1&revision=${DATASET_REVISION}"

EXPECTED_PYTHON_VERSION="$(awk '$1 == "python" { print $2 }' "${REPOSITORY_ROOT}/.tool-versions")"
if [[ -z "${EXPECTED_PYTHON_VERSION}" ]]; then
  echo "Voice detection fixture generation requires a Python pin in .tool-versions." >&2
  exit 1
fi

ACTUAL_PYTHON_VERSION="$("${PYTHON}" -c 'import platform; print(platform.python_version())')"
if [[ "${ACTUAL_PYTHON_VERSION}" != "${EXPECTED_PYTHON_VERSION}" ]]; then
  echo "Voice detection fixture generation requires Python ${EXPECTED_PYTHON_VERSION}; found ${ACTUAL_PYTHON_VERSION}." >&2
  exit 1
fi

ACTUAL_FFMPEG_VERSION="$("${FFMPEG}" -version | awk 'NR == 1 { print $3 }')"
if [[ "${ACTUAL_FFMPEG_VERSION}" != "${EXPECTED_FFMPEG_VERSION}" ]]; then
  echo "Voice detection fixture generation requires FFmpeg ${EXPECTED_FFMPEG_VERSION}; found ${ACTUAL_FFMPEG_VERSION}." >&2
  exit 1
fi

mkdir -p "${FIXTURE_DIR}"

curl -fsSL "${ROWS_URL}" -o "${TEMP_DIR}/rows.json"
SPEECH_URL="$("${PYTHON}" - \
  "${TEMP_DIR}/rows.json" \
  "${DATASET_REVISION}" \
  "${SOURCE_ASSET_PATH}" \
  "${SOURCE_RECORDING_ID}" \
  "${SOURCE_SPEAKER_ID}" \
  "${SOURCE_CHAPTER_ID}" \
  "${SOURCE_TRANSCRIPT}" <<'PY'
import json
import pathlib
import sys
import urllib.parse

rows_path = pathlib.Path(sys.argv[1])
dataset_revision = sys.argv[2]
expected_asset_path = sys.argv[3]
expected_recording_id = sys.argv[4]
expected_speaker_id = int(sys.argv[5])
expected_chapter_id = int(sys.argv[6])
expected_transcript = sys.argv[7]

payload = json.loads(rows_path.read_text(encoding="utf-8"))
rows = payload.get("rows", [])
if len(rows) != 1 or rows[0].get("row_idx") != 0:
    raise SystemExit("Hugging Face returned an unexpected fixture row set.")

row = rows[0].get("row", {})
if row.get("id") != expected_recording_id:
    raise SystemExit("Hugging Face fixture recording identity changed.")
if row.get("speaker_id") != expected_speaker_id or row.get("chapter_id") != expected_chapter_id:
    raise SystemExit("Hugging Face fixture speaker or chapter identity changed.")
if row.get("text") != expected_transcript:
    raise SystemExit("Hugging Face fixture transcript changed.")

audio = row.get("audio", [])
if len(audio) != 1 or audio[0].get("type") != "audio/flac":
    raise SystemExit("Hugging Face fixture audio metadata changed.")

source_url = audio[0].get("src", "")
parsed = urllib.parse.urlsplit(source_url)
if parsed.scheme != "https" or parsed.netloc != "datasets-server.huggingface.co":
    raise SystemExit("Hugging Face fixture source host changed.")
if parsed.path != expected_asset_path or f"/--/{dataset_revision}/--/" not in parsed.path:
    raise SystemExit("Hugging Face fixture source is not the pinned dataset revision.")

print(source_url)
PY
)"
curl -fsSL "${SPEECH_URL}" -o "${TEMP_DIR}/speech.flac"

"${PYTHON}" - \
  "${TEMP_DIR}/speech.flac" \
  "${SOURCE_AUDIO_BYTE_COUNT}" \
  "${SOURCE_AUDIO_SHA256}" <<'PY'
import hashlib
import pathlib
import sys

source = pathlib.Path(sys.argv[1])
expected_byte_count = int(sys.argv[2])
expected_sha256 = sys.argv[3]
data = source.read_bytes()
if len(data) != expected_byte_count:
    raise SystemExit("Pinned voice fixture source byte count changed.")
if hashlib.sha256(data).hexdigest() != expected_sha256:
    raise SystemExit("Pinned voice fixture source checksum changed.")
PY

"${FFMPEG}" -nostdin -loglevel error -y -i "${TEMP_DIR}/speech.flac" \
  -ar 16000 -ac 1 -c:a pcm_s16le "${FIXTURE_DIR}/speech-16k-mono.wav"
"${FFMPEG}" -nostdin -loglevel error -y -i "${TEMP_DIR}/speech.flac" -t 0.35 \
  -ar 16000 -ac 1 -c:a pcm_s16le "${FIXTURE_DIR}/short-speech-16k-mono.wav"

"${PYTHON}" - "${FIXTURE_DIR}" <<'PY'
import math
import struct
import sys
import wave
from pathlib import Path

root = Path(sys.argv[1])

def write(name, rate, channels, duration, sample):
    frame_count = round(rate * duration)
    with wave.open(str(root / name), "wb") as output:
        output.setnchannels(channels)
        output.setsampwidth(2)
        output.setframerate(rate)
        frames = bytearray()
        for frame in range(frame_count):
            values = sample(frame, rate, channels)
            for value in values:
                frames.extend(struct.pack("<h", max(-32768, min(32767, round(value * 32767)))))
        output.writeframes(frames)

write("silence-16k-mono.wav", 16000, 1, 3.0, lambda frame, rate, channels: (0.0,))

noise_state = 0x4C555845
def noise():
    global noise_state
    noise_state = (1664525 * noise_state + 1013904223) & 0xFFFFFFFF
    return ((noise_state >> 8) / 0xFFFFFF * 2.0) - 1.0

def room_tone(frame, rate, channels):
    value = noise() * 0.004 + math.sin(2 * math.pi * 60 * frame / rate) * 0.001
    return (value, value * 0.93)
write("room-tone-44100-stereo.wav", 44100, 2, 3.0, room_tone)

def music(frame, rate, channels):
    time = frame / rate
    envelope = min(1.0, time * 5.0, (3.0 - time) * 5.0)
    left = sum(math.sin(2 * math.pi * frequency * time) for frequency in (220, 277.18, 329.63))
    right = sum(math.sin(2 * math.pi * frequency * time + 0.2) for frequency in (220, 277.18, 329.63))
    return (left * 0.025 * envelope, right * 0.025 * envelope)
write("music-48k-stereo.wav", 48000, 2, 3.0, music)

def click(frame, rate, channels):
    offset = frame - rate
    value = 0.0 if offset < 0 or offset >= 160 else 0.8 * math.exp(-offset / 22) * (-1 if offset % 2 else 1)
    return (value,)
write("click-44100-mono.wav", 44100, 1, 3.0, click)

def cough(frame, rate, channels):
    time = frame / rate
    offset = time - 1.0
    if offset < 0 or offset >= 0.28:
        return (0.0,)
    envelope = math.sin(math.pi * offset / 0.28) ** 2
    return ((noise() * 0.32 + math.sin(2 * math.pi * 145 * offset) * 0.08) * envelope,)
write("cough-like-48k-mono.wav", 48000, 1, 3.0, cough)

key_times = (0.55, 0.92, 1.35, 1.78, 2.24)
def keyboard(frame, rate, channels):
    time = frame / rate
    value = 0.0
    for key_time in key_times:
        offset = time - key_time
        if 0 <= offset < 0.018:
            value += noise() * 0.32 * math.exp(-offset * 260)
    return (value, value * 0.88)
write("keyboard-44100-stereo.wav", 44100, 2, 3.0, keyboard)
PY

"${FFMPEG}" -nostdin -loglevel error -y \
  -i "${FIXTURE_DIR}/speech-16k-mono.wav" \
  -i "${FIXTURE_DIR}/music-48k-stereo.wav" \
  -filter_complex '[0:a]aresample=48000,pan=stereo|c0=c0|c1=c0,volume=0.9[speech];[1:a]volume=0.12[music];[speech][music]amix=inputs=2:duration=first:normalize=0' \
  -ar 48000 -ac 2 -c:a pcm_s16le "${FIXTURE_DIR}/podcast-like-48k-stereo.wav"

"${PYTHON}" - \
  "${FIXTURE_DIR}" \
  "${DATASET_REPOSITORY}" \
  "${DATASET_REVISION}" \
  "${ROWS_URL}" \
  "${SOURCE_ASSET_PATH}" \
  "${SOURCE_AUDIO_BYTE_COUNT}" \
  "${SOURCE_AUDIO_SHA256}" \
  "${EXPECTED_PYTHON_VERSION}" \
  "${EXPECTED_FFMPEG_VERSION}" <<'PY'
import hashlib
import json
import sys
import wave
from pathlib import Path

root = Path(sys.argv[1])
dataset_repository = sys.argv[2]
dataset_revision = sys.argv[3]
source_rows_url = sys.argv[4]
source_asset_path = sys.argv[5]
source_audio_byte_count = int(sys.argv[6])
source_audio_sha256 = sys.argv[7]
python_version = sys.argv[8]
ffmpeg_version = sys.argv[9]
metadata = {
    "speech-16k-mono.wav": ("prompt", "LibriSpeech dev-clean 1272-128104-0000", "CC BY 4.0; LibriVox contribution distributed through LibriSpeech"),
    "short-speech-16k-mono.wav": ("noPrompt", "First 350 ms of LibriSpeech 1272-128104-0000", "CC BY 4.0; LibriVox contribution distributed through LibriSpeech"),
    "podcast-like-48k-stereo.wav": ("prompt", "LibriSpeech 1272-128104-0000 mixed with deterministic synthetic music", "Speech is CC BY 4.0; music is generated by this repository"),
    "silence-16k-mono.wav": ("noPrompt", "Deterministic generated zero samples", "Generated by this repository; no person recorded"),
    "room-tone-44100-stereo.wav": ("noPrompt", "Deterministic generated seeded noise and 60 Hz tone", "Generated by this repository; no person recorded"),
    "music-48k-stereo.wav": ("noPrompt", "Deterministic generated three-note harmonic signal", "Generated by this repository; no person recorded"),
    "click-44100-mono.wav": ("noPrompt", "Deterministic generated decaying impulse", "Generated by this repository; no person recorded"),
    "cough-like-48k-mono.wav": ("noPrompt", "Deterministic generated shaped-noise burst", "Generated by this repository; no person recorded"),
    "keyboard-44100-stereo.wav": ("noPrompt", "Deterministic generated transient sequence", "Generated by this repository; no person recorded"),
}

fixtures = []
for name, (expected, provenance, consent_license) in metadata.items():
    path = root / name
    with wave.open(str(path), "rb") as audio:
        frames = audio.getnframes()
        rate = audio.getframerate()
        fixtures.append({
            "file": name,
            "expected": expected,
            "provenance": provenance,
            "consentLicense": consent_license,
            "durationSeconds": frames / rate,
            "sampleRate": rate,
            "channels": audio.getnchannels(),
            "bitsPerSample": audio.getsampwidth() * 8,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        })

manifest = {
    "schemaVersion": 2,
    "speechSource": {
        "dataset": "LibriSpeech ASR dummy / LibriSpeech dev-clean",
        "datasetRepository": dataset_repository,
        "datasetRevision": dataset_revision,
        "recordingID": "1272-128104-0000",
        "sourceIndex": 0,
        "sourceRowsURL": source_rows_url,
        "sourceAssetPath": source_asset_path,
        "sourceAudioByteCount": source_audio_byte_count,
        "sourceAudioSha256": source_audio_sha256,
        "datasetURL": "https://www.openslr.org/12",
        "license": "CC BY 4.0",
        "transcript": "MISTER QUILTER IS THE APOSTLE OF THE MIDDLE CLASSES AND WE ARE GLAD TO WELCOME HIS GOSPEL",
    },
    "generationToolchain": {
        "python": python_version,
        "ffmpeg": ffmpeg_version,
    },
    "fixtures": fixtures,
}
(root / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
PY

echo "Generated voice detection fixtures in ${FIXTURE_DIR}"
