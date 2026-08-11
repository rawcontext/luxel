#!/usr/bin/env bash

find_signing_identity_for_team() {
	local identity_pattern="$1"
	local team_identifier="$2"
	local certificate_subject
	local certificate_team_identifier
	local identity

	while IFS= read -r identity; do
		if ! certificate_subject="$(
			security find-certificate -c "${identity}" -p 2>/dev/null |
				/usr/bin/openssl x509 -noout -subject -nameopt RFC2253 2>/dev/null
		)"; then
			continue
		fi

		certificate_team_identifier="$(
			printf '%s\n' "${certificate_subject}" |
				awk -F ',' '{
					for (field_index = 1; field_index <= NF; field_index++) {
						sub(/^subject=/, "", $field_index)
						if ($field_index ~ /^OU=/) {
							sub(/^OU=/, "", $field_index)
							print $field_index
							exit
						}
					}
				}'
		)"
		if [[ "${certificate_team_identifier}" == "${team_identifier}" ]]; then
			printf '%s\n' "${identity}"
			return 0
		fi
	done < <(
		security find-identity -v 2>/dev/null |
			awk -F '"' -v pattern="${identity_pattern}" '$0 ~ pattern { print $2 }'
	)

	return 0
}
