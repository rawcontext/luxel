#!/bin/bash
# Local media benchmark: exports + transcription through luxel-cli, compared
# against .bench/baseline.json. Not wired into CI on purpose — timings are
# machine-specific. Run it on your own Mac:
#
#   bun run bench:media                     # compare against saved baseline
#   bun run bench:media -- --update-baseline  # accept current timings as baseline
#   bun run bench:media -- --runs 3           # more runs per case (best-of-N)
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Building luxel-cli (release)…"
swift build -c release --product luxel-cli

LUXEL_CLI="$(swift build -c release --show-bin-path)/luxel-cli" \
BENCH_DIR=".bench" \
exec swift Scripts/bench/media-benchmark.swift "$@"
