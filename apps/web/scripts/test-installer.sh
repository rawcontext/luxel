#!/bin/sh
set -eu

installer_path="${1:-dist/client/cli/install.sh}"
[ -f "$installer_path" ] || {
  printf 'installer not found: %s\n' "$installer_path" >&2
  exit 1
}
[ "$(git hash-object src/installer/install.sh)" = "$(git hash-object "$installer_path")" ] || {
  printf 'generated installer differs from its source\n' >&2
  exit 1
}

test_root="$(mktemp -d "${TMPDIR:-/tmp}/luxel-install-test.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

mkdir -p "$test_root/payload" "$test_root/release" "$test_root/tools"
printf '#!/bin/sh\ncase "$1" in\n  -s) printf "Darwin\\n" ;;\n  -m) printf "arm64\\n" ;;\n  *) exit 1 ;;\nesac\n' > "$test_root/tools/uname"
chmod 755 "$test_root/tools/uname"
printf '#!/bin/sh\nprintf "luxel installer fixture\\n"\n' > "$test_root/payload/luxel"
chmod 755 "$test_root/payload/luxel"
printf 'MIT license fixture\n' > "$test_root/payload/LICENSE"
printf 'Third-party notice fixture\n' > "$test_root/payload/THIRD_PARTY_LICENSES.md"
tar -czf "$test_root/release/luxel-macos-universal.tar.gz" -C "$test_root/payload" luxel LICENSE THIRD_PARTY_LICENSES.md
(
  cd "$test_root/release"
  shasum -a 256 luxel-macos-universal.tar.gz > luxel-macos-universal.tar.gz.sha256
)

mkdir -p "$test_root/home"
printf 'export EXISTING_SETTING=1\n' > "$test_root/home/.zshrc"

PATH="$test_root/tools:$PATH" \
HOME="$test_root/home" \
SHELL="/bin/zsh" \
LUXEL_RELEASE_BASE_URL="file://$test_root/release" \
  sh "$installer_path" >/dev/null

[ -x "$test_root/home/.local/bin/luxel" ]
[ "$("$test_root/home/.local/bin/luxel")" = "luxel installer fixture" ]
cmp "$test_root/payload/LICENSE" "$test_root/home/.local/share/licenses/luxel/LICENSE"
cmp "$test_root/payload/THIRD_PARTY_LICENSES.md" "$test_root/home/.local/share/licenses/luxel/THIRD_PARTY_LICENSES.md"
grep -Fq 'export EXISTING_SETTING=1' "$test_root/home/.zshrc"
grep -Fq 'export PATH="$HOME/.local/bin:$PATH"' "$test_root/home/.zshrc"
[ "$(grep -c '# >>> luxel installer >>>' "$test_root/home/.zshrc")" -eq 1 ]

PATH="$test_root/tools:$PATH" \
HOME="$test_root/home" \
SHELL="/bin/zsh" \
LUXEL_RELEASE_BASE_URL="file://$test_root/release" \
  sh "$installer_path" >/dev/null

[ "$(grep -c '# >>> luxel installer >>>' "$test_root/home/.zshrc")" -eq 1 ]

PATH="$test_root/tools:$PATH" \
HOME="$test_root/bash-home" \
SHELL="/bin/bash" \
LUXEL_RELEASE_BASE_URL="file://$test_root/release" \
  sh "$installer_path" >/dev/null

grep -Fq 'export PATH="$HOME/.local/bin:$PATH"' "$test_root/bash-home/.bash_profile"

PATH="$test_root/tools:$PATH" \
HOME="$test_root/fish-home" \
SHELL="/opt/homebrew/bin/fish" \
LUXEL_RELEASE_BASE_URL="file://$test_root/release" \
  sh "$installer_path" >/dev/null

grep -Fq 'fish_add_path "$HOME/.local/bin"' "$test_root/fish-home/.config/fish/config.fish"

PATH="$test_root/tools:$PATH" \
HOME="$test_root/no-path-update" \
SHELL="/bin/zsh" \
LUXEL_NO_PATH_UPDATE=1 \
LUXEL_RELEASE_BASE_URL="file://$test_root/release" \
  sh "$installer_path" >/dev/null

[ ! -e "$test_root/no-path-update/.zshrc" ]

tar -czf "$test_root/release/luxel-macos-universal.tar.gz" -C "$test_root/payload" luxel
(
  cd "$test_root/release"
  shasum -a 256 luxel-macos-universal.tar.gz > luxel-macos-universal.tar.gz.sha256
)
if PATH="$test_root/tools:$PATH" \
  HOME="$test_root/missing-notices" \
  LUXEL_RELEASE_BASE_URL="file://$test_root/release" \
    sh "$installer_path" >/dev/null 2>&1; then
  printf 'installer accepted an archive without license notices\n' >&2
  exit 1
fi
[ ! -e "$test_root/missing-notices/.local/bin/luxel" ]

tar -czf "$test_root/release/luxel-macos-universal.tar.gz" -C "$test_root/payload" luxel LICENSE THIRD_PARTY_LICENSES.md
printf '%064d  luxel-macos-universal.tar.gz\n' 0 > \
  "$test_root/release/luxel-macos-universal.tar.gz.sha256"

if PATH="$test_root/tools:$PATH" \
  HOME="$test_root/rejected" \
  SHELL="/bin/zsh" \
  LUXEL_RELEASE_BASE_URL="file://$test_root/release" \
    sh "$installer_path" >/dev/null 2>&1; then
  printf 'installer accepted an invalid checksum\n' >&2
  exit 1
fi
