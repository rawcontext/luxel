#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPOSITORY_ROOT"

BAZEL_COMMAND=(bazel)
if ! command -v bazel >/dev/null 2>&1; then
  BAZEL_COMMAND=(npx --yes --package=@bazel/bazelisk@1.28.1 bazelisk)
fi

BUILD_FLAGS=(
  "--//apps/web:site_url=${LUXEL_SITE_URL:-https://luxel.media}"
  "--//apps/web:turnstile_site_key=${PUBLIC_TURNSTILE_SITE_KEY:-}"
)
if [[ "${VERCEL:-}" == "1" ]]; then
  CACHE_ROOT="$REPOSITORY_ROOT/apps/web/.vercel/cache/bazel"
  export BAZELISK_HOME="$CACHE_ROOT/bazelisk"
  BUILD_FLAGS+=("--disk_cache=$CACHE_ROOT/actions" "--repository_cache=$CACHE_ROOT/repository" "--repo_contents_cache=")
fi

"${BAZEL_COMMAND[@]}" build "${BUILD_FLAGS[@]}" //apps/web:build
OUTPUT="$REPOSITORY_ROOT/$("${BAZEL_COMMAND[@]}" cquery "${BUILD_FLAGS[@]}" --output=files //apps/web:vercel_output)"
DESTINATION="$REPOSITORY_ROOT/apps/web/.vercel/output"
mkdir -p "$(dirname "$DESTINATION")"
if [[ -d "$DESTINATION" ]]; then
  chmod -R u+w "$DESTINATION"
fi
rm -rf "$DESTINATION"
cp -R "$OUTPUT" "$DESTINATION"
chmod -R u+w "$DESTINATION"
