#!/bin/sh
set -eu

installer_path="${1:-dist/client/cli/install.sh}"
[ -f "$installer_path" ] || {
  printf 'installer not found: %s\n' "$installer_path" >&2
  exit 1
}
cmp -s src/installer/install.sh "$installer_path" || {
  printf 'generated installer differs from its source\n' >&2
  exit 1
}

test_root="$(mktemp -d "${TMPDIR:-/tmp}/luxel-install-test.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

mkdir -p "$test_root/payload" "$test_root/release"
printf '#!/bin/sh\nprintf "luxel installer fixture\\n"\n' > "$test_root/payload/luxel"
chmod 755 "$test_root/payload/luxel"
tar -czf "$test_root/release/luxel-macos-universal.tar.gz" -C "$test_root/payload" luxel
(
  cd "$test_root/release"
  shasum -a 256 luxel-macos-universal.tar.gz > luxel-macos-universal.tar.gz.sha256
)

LUXEL_INSTALL_DIR="$test_root/bin" \
LUXEL_RELEASE_BASE_URL="file://$test_root/release" \
  sh "$installer_path" >/dev/null

[ -x "$test_root/bin/luxel" ]
[ "$("$test_root/bin/luxel")" = "luxel installer fixture" ]

printf '%064d  luxel-macos-universal.tar.gz\n' 0 > \
  "$test_root/release/luxel-macos-universal.tar.gz.sha256"

if LUXEL_INSTALL_DIR="$test_root/rejected" \
  LUXEL_RELEASE_BASE_URL="file://$test_root/release" \
    sh "$installer_path" >/dev/null 2>&1; then
  printf 'installer accepted an invalid checksum\n' >&2
  exit 1
fi
