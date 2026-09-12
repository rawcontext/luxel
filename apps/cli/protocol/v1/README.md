# Luxel command protocol v1

The `luxel` binary is a controller. The Luxel Mac app is the only process that
records or reads, converts, exports, and transcribes media.

## Invocation flow

1. The CLI binds a short-lived HTTP listener to `127.0.0.1` on an ephemeral port.
2. It creates an unguessable `/session/<128-bit-token>` route.
3. It opens either `luxel://cli/pair` or `luxel://cli/run`.
4. For an authenticated run, Luxel fetches the request document with `GET`.
5. Luxel posts ordered events to the same route until it sends `result`, `error`,
   or `canceled`.
6. The listener closes.

The listener never binds to a wildcard or LAN address. Luxel accepts only plain
HTTP endpoints on `127.0.0.1` or `::1`, with an explicit port and an unguessable
session route. Redirects are disabled and request bodies are limited to 4 MiB.

## Pairing

`luxel://cli/pair` includes `protocolVersion`, `requestID`, `clientName`, and
`endpoint`. Luxel always shows an approval prompt. On approval, the app returns a
client ID and random shared secret through the session route. Luxel and the CLI
store separate Keychain items; the secret is never placed in the URL.

## Authenticated runs

`luxel://cli/run` includes:

- `protocolVersion`
- `requestID`
- `clientID`
- `endpoint`
- `requestDigest`, the lowercase SHA-256 of the exact request body
- `timestamp`, Unix seconds
- `nonce`, a random hexadecimal value
- `signature`, a lowercase HMAC-SHA-256

The HMAC input is the UTF-8 encoding of these values joined by a newline, in this
order:

```text
protocolVersion
requestID
clientID
endpoint
requestDigest
timestamp
nonce
```

UUIDs are lowercase in the canonical input. Luxel rejects invalid signatures,
stale timestamps, repeated nonces, modified request bodies, revoked clients, and
unsupported protocol versions before executing a command.

## Request and event documents

Requests contain `protocolVersion`, `requestID`, `command`, `arguments`, and
`output`. Version 1 commands are `record`, `stop`, `toggle`, `clip`, `latest`,
`preferences`, `editor`, `convert`, `export`, `transcribe`, `accessAdd`,
`accessCheck`, `accessList`, `accessRevoke`, `doctor`, and `cancel`.

Events contain `protocolVersion`, `requestID`, a zero-based monotonically increasing
`sequence`, and `kind`. `accepted` and `progress` are nonterminal. `result`, `error`,
and `canceled` are terminal. Every event must match the invocation request ID.

The fixtures in `fixtures/` are the canonical cross-language compatibility vectors
consumed by both the Rust and Swift test suites.
