#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
dashboard="${script_dir}/openirn-api-health-security.json"
rules="${script_dir}/openirn-alerting-rules.json"
portable_host='openirn-api-node.other-infra.example'
tmp_dir=$(mktemp -d)
audit_files=(
	"${dashboard}"
	"${rules}"
	"${script_dir}/deploy-dashboard.sh"
	"${script_dir}/deploy-alerting-rules.sh"
	"${script_dir}/install-monitoring.sh"
	"${script_dir}/README.md"
	"${script_dir}/RUNBOOK_ALERTES.md"
	"${script_dir}/RUNBOOK_ALERTS.en.md"
)

cleanup() {
	rm -rf -- "${tmp_dir}"
}
trap cleanup EXIT

for command_name in bash grep jq mktemp; do
	if ! command -v "${command_name}" >/dev/null 2>&1; then
		echo "Commande requise absente : ${command_name}" >&2
		exit 1
	fi
done

bash -n \
	"${script_dir}/deploy-dashboard.sh" \
	"${script_dir}/deploy-alerting-rules.sh" \
	"${script_dir}/install-monitoring.sh" \
	"${script_dir}/validate-monitoring.sh" \
	"${script_dir}/tests/bin/curl" \
	"${script_dir}/tests/test-portable-installation.sh"

jq -e '
	.title == "OpenIRN — Santé API et sécurité" and
	(.panels | length == 20) and
	([paths(scalars) as $path | select($path[-1] == "id")] | length == 0)
' "${dashboard}" >/dev/null

jq -e '
	.schemaVersion == 1 and
	(.rules | length == 11) and
	([.rules[].id] | unique | length == 11) and
	(.connector.type == ".server-log") and
	(.connector | has("id") | not)
' "${rules}" >/dev/null

OPENIRN_MONITORED_HOST="${portable_host}" \
	"${script_dir}/deploy-dashboard.sh" --render > "${tmp_dir}/dashboard.json"
OPENIRN_MONITORED_HOST="${portable_host}" \
	"${script_dir}/deploy-alerting-rules.sh" --render > "${tmp_dir}/rules.json"

jq -e --arg host "${portable_host}" \
	'[paths(scalars) as $path | getpath($path) | strings | select(contains($host))] | length == 6' \
	"${tmp_dir}/dashboard.json" >/dev/null
jq -e --arg host "${portable_host}" \
	'[.rules[].query | select(contains($host))] | length == 4' \
	"${tmp_dir}/rules.json" >/dev/null

if grep -ERq '__OPENIRN_[A-Z0-9_]+__' "${tmp_dir}"; then
	echo 'Un paramètre de rendu subsiste dans les définitions portables.' >&2
	exit 1
fi

if grep -Eni \
	-e 'www\.archoad\.io' \
	-e '\[archoad\]' \
	-e 'openirn-api-health-ia' \
	-e 'codex@srv' \
	-e 'ssh[[:space:]]+-p[[:space:]]+42' \
	-e 'host\.name[[:space:]]*==[[:space:]]*\\"srv\\"' \
	-e '\(logs-openirn\.\(api\|security\)\|synthetics-http\|metrics-system\.\(cpu\|memory\|filesystem\)\|metrics-mysql\.status\)-default' \
	"${audit_files[@]}"; then
	echo 'Une référence propre à l’infrastructure de développement subsiste.' >&2
	exit 1
fi

if grep -Eni \
	-e 'BEGIN [A-Z ]*PRIVATE KEY' \
	-e 'AKIA[0-9A-Z]\{16\}' \
	-e 'github_pat_[A-Za-z0-9_]\{20,\}' \
	-e 'ghp_[A-Za-z0-9]\{20,\}' \
	-e 'xox[baprs]-[A-Za-z0-9-]\{10,\}' \
	-e 'Authorization:[[:space:]]*ApiKey[[:space:]]*[A-Za-z0-9_+/=-]\{16,\}' \
	"${audit_files[@]}"; then
	echo 'Une forme usuelle de secret intégré a été détectée.' >&2
	exit 1
fi

for source_pattern in \
	'logs-openirn.api-*' \
	'logs-openirn.security-*' \
	'synthetics-http-*' \
	'metrics-system.cpu-*' \
	'metrics-system.memory-*' \
	'metrics-system.filesystem-*' \
	'metrics-mysql.status-*'; do
	if ! grep -Fq "${source_pattern}" "${tmp_dir}/dashboard.json"; then
		echo "Source portable absente du dashboard : ${source_pattern}" >&2
		exit 1
	fi
done

"${script_dir}/tests/test-portable-installation.sh" >/dev/null

echo 'Monitoring OpenIRN valide : aucun secret détecté et rendu portable réussi.'
