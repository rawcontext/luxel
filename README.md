# luxel

`luxel` is the open-source command-line controller for the Luxel macOS app. The
binary does not record, inspect, convert, export, or transcribe media itself. It
authenticates a request, opens Luxel, and waits on a loopback-only callback while
Luxel performs the work with the permissions and settings you approved in the app.

The repository is private during development. The planned public release is MIT
licensed.

## Requirements

- macOS 26 or later
- Luxel installed and launched at least once
- Rust 1.97 or later when building from source

## Build from source

```sh
cargo build --release
install -m 755 target/release/luxel ~/.local/bin/luxel
```

## First use

```sh
luxel pair
luxel doctor
```

Pairing opens a visible approval prompt in Luxel. Luxel and the CLI store their
copies of the generated secret in macOS Keychain. Disable command-line control or
revoke a paired client at any time in Luxel Settings > Command Line.

## Folder access

The App Store build can use your Movies folder, Luxel's configured recording
folder, and folders you explicitly add. The command suggests a folder, but the
system picker in Luxel is the authority:

```sh
luxel access add ~/Desktop/Exports
luxel access check ~/Desktop/Exports/demo.mp4
luxel access list
luxel access revoke GRANT_ID
```

## Commands

```text
luxel pair [--name NAME]
luxel record (--display [ID|main] | --active-window | --last-area)
luxel stop
luxel toggle [--display [ID|main] | --active-window | --last-area]
luxel clip [--seconds N]
luxel latest [--reveal]
luxel preferences [--pane PANE]
luxel editor FILE
luxel convert INPUT OUTPUT [OPTIONS]
luxel export REQUEST_JSON OUTPUT [--overwrite]
luxel transcribe FILE [OPTIONS]
luxel access add|check|list|revoke
luxel doctor
luxel cancel JOB_ID
```

All commands accept `--json`, `--quiet`, and `--timeout SECONDS`.

Recording accepts `--preset`, `--fps 1...120`, `--fps display`, `--countdown
0...60`, and `--save-to FOLDER`. `toggle` without a target stops an active
recording; when starting, target-specific options require a target.

Conversion accepts `--format`, `--width` plus `--height`, `-s WIDTHxHEIGHT`,
`--fps`/`-r`, `--start`/`--ss`, `--end`/`--to`, `--duration`/`--t`, `--speed`,
`--mute`/`-an`, `--crop-to-fill`, `--crop x,y,width,height`, `--quality`, and
`--overwrite`/`-y`. Supported formats are `gif`, `hevc`, `mp4`, `av1`, `webm`,
`apng`, `prores422`, `prores4444`, `m4a`, `alac`, `wav`, `caf`, and `flac`.

Transcription accepts `--locale`, `--output`, `--semantic-turns`, `--diarize`,
`--format text|json`, and `--overwrite`. For clean source separation, use
headphones or AirPods while recording system audio and microphone audio. Playing
system audio through speakers can let the microphone capture the same speech a
second time, producing duplicate text under different sources.

The full command and option reference is also available at
[luxel.media/docs#cli](https://luxel.media/docs#cli).

## Exit status

- `0`: success
- `2`: invalid command or option combination
- `3`: pairing is required
- `4`: Luxel could not be opened
- `5`: the Keychain credential could not be used
- `6`: Luxel permission or folder access is required
- `7`: app, protocol, I/O, or JSON failure
- `8`: timeout
- `130`: canceled

## Security model

- The callback listener binds only to `127.0.0.1` on a random port.
- Every request body is SHA-256 hashed and included in an HMAC-SHA-256 signature.
- Signed metadata includes the protocol version, request ID, client ID, callback
  endpoint, timestamp, and random nonce.
- Luxel rejects stale, replayed, unpaired, modified, or remote-endpoint requests.
- The CLI never receives Luxel's sandbox extensions or security-scoped bookmarks.

## Development

```sh
cargo fmt --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --all-targets --all-features
```

The fixtures under `protocol/v1/fixtures` are byte-for-schema peers of Luxel's Swift
protocol fixtures.
