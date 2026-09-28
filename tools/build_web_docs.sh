#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/.." && pwd)"
docs_root="${project_root}/docs"
output_root="${project_root}/web/openirn/docs"
template="${script_dir}/templates/openirn-web-document.html"
filter="${script_dir}/pandoc_web.lua"

if ! command -v pandoc >/dev/null 2>&1; then
	printf 'Erreur : pandoc est requis pour générer la documentation Web.\n' >&2
	exit 1
fi

for required_file in "${template}" "${filter}"; do
	if [[ ! -f "${required_file}" ]]; then
		printf 'Erreur : fichier requis absent : %s\n' "${required_file}" >&2
		exit 1
	fi
done

mkdir -p "${output_root}"
source_count=0
output_count=0

while IFS= read -r -d '' source_file; do
	relative_path="${source_file#"${docs_root}/"}"
	output_file="${output_root}/${relative_path%.md}.html"
	output_directory="$(dirname "${output_file}")"
	asset_prefix="../"
	lang="fr"
	pandoc_metadata=()

	if [[ "${relative_path}" == */* ]]; then
		relative_directory="${relative_path%/*}"
		remaining_path="${relative_directory}"
		while [[ -n "${remaining_path}" ]]; do
			asset_prefix="../${asset_prefix}"
			if [[ "${remaining_path}" == */* ]]; then
				remaining_path="${remaining_path#*/}"
			else
				remaining_path=""
			fi
		done
	fi

	if [[ "${relative_path}" == en/* ]]; then
		lang="en"
		pandoc_metadata+=(--metadata="is_english:true")
	fi

	mkdir -p "${output_directory}"
	pandoc "${source_file}" \
		--from=gfm+yaml_metadata_block \
		--to=html5 \
		--standalone \
		--section-divs \
		--toc \
		--toc-depth=3 \
		--template="${template}" \
		--lua-filter="${filter}" \
		--metadata="lang:${lang}" \
		--metadata="asset_prefix:${asset_prefix}" \
		--metadata="source_url:https://github.com/archoad/OpenIRN/blob/main/docs/${relative_path}" \
		"${pandoc_metadata[@]}" \
		--output="${output_file}"

	printf 'Généré : web/openirn/docs/%s\n' "${relative_path%.md}.html"
	source_count=$((source_count + 1))
done < <(find "${docs_root}" -type f -name '*.md' -print0)

while IFS= read -r -d '' generated_file; do
	output_count=$((output_count + 1))
done < <(find "${output_root}" -type f -name '*.html' -print0)

if [[ "${source_count}" -ne "${output_count}" ]]; then
	printf 'Erreur : %d source(s) Markdown, mais %d page(s) HTML.\n' "${source_count}" "${output_count}" >&2
	exit 1
fi

printf 'Documentation Web générée : %d page(s).\n' "${output_count}"
