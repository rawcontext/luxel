#!/usr/bin/env bash
set -euo pipefail

swift_files=()

while IFS= read -r -d "" file; do
	if [[ -f "${file}" ]]; then
		swift_files+=("${file}")
	fi
done < <(git diff --cached --name-only -z --diff-filter=ACMR -- "*.swift")

if [[ "${#swift_files[@]}" -eq 0 ]]; then
	for file in "$@"; do
		if [[ -f "${file}" && "${file}" == *.swift ]]; then
			swift_files+=("${file}")
		fi
	done
fi

if [[ "${#swift_files[@]}" -eq 0 ]]; then
	exit 0
fi

swift format -i --parallel "${swift_files[@]}"
swiftlint lint --fix --format --quiet --config .swiftlint.yml "${swift_files[@]}"
git add -- "${swift_files[@]}"
swiftlint lint --quiet --config .swiftlint.yml "${swift_files[@]}"
