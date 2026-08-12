#!/bin/sh
set -eu

asset="luxel-macos-universal.tar.gz"
release_base_url="${LUXEL_RELEASE_BASE_URL:-https://github.com/rawcontext/luxel-cli/releases/latest/download}"
default_install_dir="${HOME}/.local/bin"
install_dir="${LUXEL_INSTALL_DIR:-$default_install_dir}"

fail() {
  printf 'luxel installer: %s\n' "$1" >&2
  exit 1
}

[ "$(uname -s)" = "Darwin" ] || fail "macOS is required"
case "$(uname -m)" in
  arm64 | x86_64) ;;
  *) fail "Apple Silicon or Intel hardware is required" ;;
esac

for command in curl install shasum tar; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is required"
done

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/luxel-install.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

archive="$work_dir/$asset"
checksum="$archive.sha256"

curl -fsSL --retry 3 "$release_base_url/$asset" -o "$archive"
curl -fsSL --retry 3 "$release_base_url/$asset.sha256" -o "$checksum"

expected_checksum="$(awk 'NR == 1 { print $1 }' "$checksum")"
case "$expected_checksum" in
  *[!0-9a-fA-F]* | "") fail "the release checksum is invalid" ;;
esac
[ "${#expected_checksum}" -eq 64 ] || fail "the release checksum is invalid"

actual_checksum="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
[ "$actual_checksum" = "$expected_checksum" ] || fail "the release checksum did not match"

[ "$(tar -tzf "$archive")" = "luxel" ] || fail "the release archive is invalid"
mkdir -p "$work_dir/extracted" "$install_dir"
tar -xzf "$archive" -C "$work_dir/extracted"
[ -f "$work_dir/extracted/luxel" ] || fail "the release archive does not contain luxel"

install -m 755 "$work_dir/extracted/luxel" "$install_dir/luxel"
printf 'Installed luxel to %s/luxel\n' "$install_dir"

case ":${PATH:-}:" in
  *":$install_dir:"*) printf 'Run luxel --version to verify the installation.\n' ;;
  *)
    config_file=""
    path_entry='export PATH="$HOME/.local/bin:$PATH"'

    if [ "$install_dir" = "$default_install_dir" ] && [ "${LUXEL_NO_PATH_UPDATE:-0}" != "1" ]; then
      user_shell="${SHELL:-}"
      case "${user_shell##*/}" in
        zsh) config_file="${ZDOTDIR:-$HOME}/.zshrc" ;;
        bash) config_file="$HOME/.bash_profile" ;;
        fish)
          config_file="$HOME/.config/fish/config.fish"
          path_entry='fish_add_path "$HOME/.local/bin"'
          ;;
      esac
    fi

    if [ -n "$config_file" ]; then
      mkdir -p "$(dirname "$config_file")"
      if ! grep -Fqs "$path_entry" "$config_file" 2>/dev/null; then
        printf '\n# >>> luxel installer >>>\n%s\n# <<< luxel installer <<<\n' "$path_entry" >> "$config_file"
        printf 'Added %s to PATH in %s.\n' "$install_dir" "$config_file"
      fi
      printf 'Open a new terminal, then run luxel --version.\n'
    else
      printf 'Add %s to your PATH.\n' "$install_dir"
    fi
    ;;
esac
