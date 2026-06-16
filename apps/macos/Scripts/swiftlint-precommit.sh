#!/usr/bin/env bash
set -euo pipefail

swift_files=()

for file in "$@"; do
	if [[ -f "${file}" && "${file}" == *.swift ]]; then
		swift_files+=("${file}")
	fi
done

if [[ "${#swift_files[@]}" -eq 0 ]]; then
	exit 0
fi

swiftlint lint --fix --format --quiet "${swift_files[@]}"
git add -- "${swift_files[@]}"
swiftlint lint --quiet "${swift_files[@]}"
