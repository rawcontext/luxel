# Contributing

Open an issue before proposing a command or protocol change. The CLI must remain a
client of Luxel: media access and product behavior belong in the app.

Run formatting, Clippy, and all tests before opening a pull request:

```sh
cargo fmt --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --all-targets --all-features
```

Protocol changes require matching Swift and Rust fixtures and an explicit protocol
version compatibility decision.
