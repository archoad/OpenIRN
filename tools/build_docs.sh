#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="${project_root}/docs/pdf"
document_version="${DOC_VERSION:-développement}"
logo_path="${project_root}/flutter/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"
header_path="${project_root}/docs/pdf/openirn-header.tex"

cd "${project_root}"

documents=(
	"installation-serveur-api"
	"deploiement-applications"
	"guide-utilisateur"
	"administration-instance"
)

for command_name in pandoc xelatex; do
	if ! command -v "${command_name}" >/dev/null 2>&1; then
		echo "Commande requise absente : ${command_name}" >&2
		exit 1
	fi
done

test -f "${logo_path}"
test -f "${header_path}"
mkdir -p "${output_dir}"

for document_name in "${documents[@]}"; do
	source_path="${project_root}/docs/${document_name}.md"
	output_path="${output_dir}/openirn-${document_name}.pdf"
	test -f "${source_path}"
	pandoc "${source_path}" \
		--from=gfm+yaml_metadata_block \
		--pdf-engine=xelatex \
		--standalone \
		--toc \
		--toc-depth=3 \
		--number-sections \
		--resource-path="${project_root}" \
		--include-in-header="${header_path}" \
		--metadata="date:Version ${document_version}" \
		--variable="lang:fr-FR" \
		--variable="papersize:a4" \
		--variable="geometry:margin=22mm" \
		--output="${output_path}"
	echo "PDF créé : ${output_path}"
done
