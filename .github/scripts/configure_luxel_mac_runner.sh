#!/usr/bin/env bash

set -euo pipefail

runner_root="${1:?usage: $0 /absolute/path/actions-runner-luxel RUNNER_NAME}"
runner_name="${2:?usage: $0 /absolute/path/actions-runner-luxel RUNNER_NAME}"
repository="ccheney/luxel"
repository_url="https://github.com/$repository"
runner_version="2.337.0"
runner_asset="actions-runner-osx-arm64-${runner_version}.tar.gz"
runner_url="https://github.com/actions/runner/releases/download/v${runner_version}/${runner_asset}"
runner_sha256="5a2cd92908a93d7276a194e1de6008099f3e7946f3f8e14aa7a1a7b4a31fdec2"

case "$runner_root" in
	/*/actions-runner-luxel) ;;
	*)
		echo "Runner path must be absolute and end in actions-runner-luxel." >&2
		exit 64
		;;
esac

case "$(pwd -P)/" in
	"$runner_root"/*)
		echo "Run this script from a Luxel checkout outside $runner_root." >&2
		exit 64
		;;
esac

for required_command in curl gh shasum tar; do
	command -v "$required_command" >/dev/null || {
		echo "$required_command is required." >&2
		exit 69
	}
done

gh auth status >/dev/null

if [[ -e "$runner_root" && ! -d "$runner_root" ]]; then
	echo "$runner_root exists and is not a directory." >&2
	exit 73
fi

if [[ -e "$runner_root/.runner" ]]; then
	remove_token=$(gh api --method POST "repos/$repository/actions/runners/remove-token" --jq .token)
	(
		cd "$runner_root"
		./svc.sh stop || true
		./svc.sh uninstall || true
		./config.sh remove --token "$remove_token" || true
	)
fi

if [[ -d "$runner_root" ]]; then
	stale_root="${runner_root}.stale.$(date -u +%Y%m%dT%H%M%SZ)"
	mv "$runner_root" "$stale_root"
	echo "Preserved the previous runner installation at $stale_root."
fi

runner_tmp=$(mktemp -d)
cleanup() {
	rm -rf -- "$runner_tmp"
}
trap cleanup EXIT

runner_archive="$runner_tmp/$runner_asset"
curl --fail --location --show-error "$runner_url" --output "$runner_archive"
printf '%s  %s\n' "$runner_sha256" "$runner_archive" | shasum -a 256 --check

mkdir -p "$runner_root"
tar -xzf "$runner_archive" -C "$runner_root"

registration_token=$(gh api --method POST "repos/$repository/actions/runners/registration-token" --jq .token)
(
	cd "$runner_root"
	./config.sh \
		--unattended \
		--replace \
		--url "$repository_url" \
		--token "$registration_token" \
		--name "$runner_name" \
		--labels luxel-desktop \
		--work _work
	./svc.sh install
	./svc.sh start
	./svc.sh status
)
