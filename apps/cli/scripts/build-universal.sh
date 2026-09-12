#!/usr/bin/env bash
set -euo pipefail

ASDF_RUST_VERSION="${ASDF_RUST_VERSION:-1.97.1}"
export ASDF_RUST_VERSION

rustup target add aarch64-apple-darwin x86_64-apple-darwin
cargo build --release --locked --target aarch64-apple-darwin
cargo build --release --locked --target x86_64-apple-darwin

mkdir -p target/universal-apple-darwin/release
lipo -create \
  target/aarch64-apple-darwin/release/luxel \
  target/x86_64-apple-darwin/release/luxel \
  -output target/universal-apple-darwin/release/luxel

file target/universal-apple-darwin/release/luxel
