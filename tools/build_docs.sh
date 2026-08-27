#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="${project_root}/docs/pdf"
logo_path="${project_root}/flutter/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"
header_path="${project_root}/docs/pdf/openirn-header.tex"
archive_path="${output_dir}/openirn-documentation-fr-en.zip"

cd "${project_root}"

documents=(
	"docs/installation-serveur-api.md|openirn-installation-serveur-api.pdf|fr-FR"
	"docs/deploiement-applications.md|openirn-deploiement-applications.pdf|fr-FR"
	"docs/guide-utilisateur.md|openirn-guide-utilisateur.pdf|fr-FR"
	"docs/administration-instance.md|openirn-administration-instance.pdf|fr-FR"
	"docs/en/server-api-installation.md|openirn-server-api-installation-en.pdf|en-US"
	"docs/en/application-deployment.md|openirn-application-deployment-en.pdf|en-US"
	"docs/en/user-guide.md|openirn-user-guide-en.pdf|en-US"
	"docs/en/instance-administration.md|openirn-instance-administration-en.pdf|en-US"
)

for command_name in pandoc xelatex kpsewhich zip; do
	if ! command -v "${command_name}" >/dev/null 2>&1; then
		echo "Commande requise absente : ${command_name}" >&2
		exit 1
	fi
done

tex_dependencies=(
	"lmodern.sty|lmodern"
	"pzdr.tfm|texlive-fonts-recommended"
)

for dependency in "${tex_dependencies[@]}"; do
	IFS='|' read -r tex_file ubuntu_package <<< "${dependency}"
	if ! kpsewhich "${tex_file}" >/dev/null 2>&1; then
		echo "Dépendance LaTeX absente : ${tex_file} (paquet Ubuntu : ${ubuntu_package})" >&2
		exit 1
	fi
done

test -f "${logo_path}"
test -f "${header_path}"
mkdir -p "${output_dir}"
generated_pdfs=()

for document in "${documents[@]}"; do
	IFS='|' read -r source_relative output_name document_language <<< "${document}"
	source_path="${project_root}/${source_relative}"
	output_path="${output_dir}/${output_name}"
	if [[ -n "${DOC_VERSION:-}" ]]; then
		version_metadata="Version ${DOC_VERSION}"
	elif [[ "${document_language}" == "fr-FR" ]]; then
		version_metadata="Version développement"
	else
		version_metadata="Development version"
	fi
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
		--metadata="date:${version_metadata}" \
		--variable="lang:${document_language}" \
		--variable="papersize:a4" \
		--variable="geometry:margin=22mm" \
		--output="${output_path}"
	generated_pdfs+=("${output_path}")
	echo "PDF créé : ${output_path}"
done

rm -f "${archive_path}"
zip -j "${archive_path}" "${generated_pdfs[@]}"
zip -T "${archive_path}"
echo "Archive documentaire créée : ${archive_path}"
