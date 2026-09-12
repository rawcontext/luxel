#!/usr/bin/env bash
set -euo pipefail

test -x target/universal-apple-darwin/release/luxel
mkdir -p dist
tar -czf dist/luxel-macos-universal.tar.gz \
  -C target/universal-apple-darwin/release luxel
(
  cd dist
  shasum -a 256 luxel-macos-universal.tar.gz > luxel-macos-universal.tar.gz.sha256
)
