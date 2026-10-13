#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mode='deploy'
if [[ ${1:-} == '--render' ]]; then
	mode='render'
	shift
fi

definition=${1:-"${script_dir}/openirn-api-health-security.json"}
kibana_url=${KIBANA_URL:-http://127.0.0.1:5601}
kibana_url=${kibana_url%/}
monitored_host=${OPENIRN_MONITORED_HOST:-}
dashboard_id=${OPENIRN_DASHBOARD_ID:-openirn-api-health-security}

if [[ ! -r ${definition} ]]; then
	echo "Définition introuvable : ${definition}" >&2
	exit 1
fi
if [[ -z ${monitored_host} || ! ${monitored_host} =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,252}$ ]]; then
	echo 'OPENIRN_MONITORED_HOST doit contenir la valeur ECS host.name de l’hôte OpenIRN.' >&2
	exit 1
fi
if [[ ! ${dashboard_id} =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]]; then
	echo 'OPENIRN_DASHBOARD_ID contient un identifiant invalide.' >&2
	exit 1
fi

tmp_dir=$(mktemp -d)
cleanup() {
	rm -rf -- "${tmp_dir}"
}
trap cleanup EXIT

rendered_dashboard="${tmp_dir}/openirn-dashboard.rendered.json"
jq --arg monitored_host "${monitored_host}" \
	'walk(if type == "string" then gsub("__OPENIRN_MONITORED_HOST__"; $monitored_host) else . end)' \
	"${definition}" > "${rendered_dashboard}"

if grep -Eq '__OPENIRN_[A-Z0-9_]+__' "${rendered_dashboard}"; then
	echo 'Le dashboard rendu contient encore un paramètre non remplacé.' >&2
	exit 1
fi

if [[ ${mode} == 'render' ]]; then
	jq . "${rendered_dashboard}"
	exit 0
fi

# shellcheck source=kibana-auth.sh
source "${script_dir}/kibana-auth.sh"
auth_config="${tmp_dir}/curl-auth.conf"
kibana_write_auth_config "${auth_config}"

response_file="${tmp_dir}/dashboard-response.json"
curl --fail-with-body --silent --show-error \
	--config "${auth_config}" \
	-X PUT \
	-H 'Accept: application/json' \
	-H 'Content-Type: application/json' \
	-H 'kbn-xsrf: openirn-dashboard' \
	--data-binary "@${rendered_dashboard}" \
	"${kibana_url}/api/dashboards/${dashboard_id}" > "${response_file}"

jq -e 'type == "object"' "${response_file}" >/dev/null
echo "Dashboard OpenIRN déployé : ${dashboard_id} pour host.name=${monitored_host}."
