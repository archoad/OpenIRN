#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mode='deploy'
if [[ ${1:-} == '--render' ]]; then
	mode='render'
	shift
fi

definition=${1:-"${script_dir}/openirn-alerting-rules.json"}
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

rendered_definition="${tmp_dir}/openirn-alerting-rules.rendered.json"
jq --arg monitored_host "${monitored_host}" \
	'walk(if type == "string" then gsub("__OPENIRN_MONITORED_HOST__"; $monitored_host) else . end)' \
	"${definition}" > "${rendered_definition}"

if grep -Eq '__OPENIRN_[A-Z0-9_]+__' "${rendered_definition}"; then
	echo 'La définition rendue contient encore un paramètre non remplacé.' >&2
	exit 1
fi

if [[ ${mode} == 'render' ]]; then
	jq . "${rendered_definition}"
	exit 0
fi

if [[ -z ${KIBANA_API_KEY:-} || ! ${KIBANA_API_KEY} =~ ^[A-Za-z0-9_+/=-]+$ ]]; then
	echo 'KIBANA_API_KEY doit contenir une clé API Kibana valide.' >&2
	exit 1
fi

kibana_request() {
	local method=$1
	local path=$2
	local body=${3:-}
	local -a args=(
		--fail-with-body --silent --show-error
		--config <(printf 'header = "Authorization: ApiKey %s"\n' "${KIBANA_API_KEY}")
		-X "${method}"
		-H 'Accept: application/json'
		-H 'kbn-xsrf: openirn-alerting'
	)
	if [[ -n ${body} ]]; then
		args+=(
			-H 'Content-Type: application/json'
			--data-binary "@${body}"
		)
	fi
	curl "${args[@]}" "${kibana_url}${path}"
}

kibana_status() {
	local path=$1
	local output=$2
	curl --silent --show-error \
		--config <(printf 'header = "Authorization: ApiKey %s"\n' "${KIBANA_API_KEY}") \
		-H 'Accept: application/json' \
		-H 'kbn-xsrf: openirn-alerting' \
		-o "${output}" \
		-w '%{http_code}' \
		"${kibana_url}${path}"
}

connector_type=$(jq -er '.connector.type' "${rendered_definition}")
connector_name=${OPENIRN_SERVER_LOG_CONNECTOR_NAME:-$(jq -er '.connector.name' "${rendered_definition}")}
create_connector=${OPENIRN_CREATE_SERVER_LOG_CONNECTOR:-$(jq -er '.connector.createIfMissing' "${rendered_definition}")}
if [[ ${create_connector} != true && ${create_connector} != false ]]; then
	echo 'OPENIRN_CREATE_SERVER_LOG_CONNECTOR doit valoir true ou false.' >&2
	exit 1
fi
connectors_file="${tmp_dir}/connectors.json"
kibana_request GET '/api/actions/connectors' > "${connectors_file}"

connector_id=${KIBANA_CONNECTOR_ID:-}
if [[ -n ${connector_id} ]]; then
	connector_count=$(jq --arg id "${connector_id}" --arg type "${connector_type}" \
		'[.[] | select(.id == $id and .connector_type_id == $type)] | length' \
		"${connectors_file}")
	if [[ ${connector_count} -ne 1 ]]; then
		echo "KIBANA_CONNECTOR_ID ne désigne pas un connecteur ${connector_type} accessible." >&2
		exit 1
	fi
else
	connector_count=$(jq --arg type "${connector_type}" --arg name "${connector_name}" \
		'[.[] | select(.connector_type_id == $type and .name == $name)] | length' \
		"${connectors_file}")
	if [[ ${connector_count} -gt 1 ]]; then
		echo "Plusieurs connecteurs correspondent à ${connector_name} (${connector_type})." >&2
		exit 1
	fi
	if [[ ${connector_count} -eq 1 ]]; then
		connector_id=$(jq -er --arg type "${connector_type}" --arg name "${connector_name}" \
			'.[] | select(.connector_type_id == $type and .name == $name) | .id' \
			"${connectors_file}")
	elif [[ ${create_connector} == true ]]; then
		connector_body="${tmp_dir}/connector.json"
		connector_response="${tmp_dir}/connector-response.json"
		jq -n --arg name "${connector_name}" --arg type "${connector_type}" \
			'{name: $name, connector_type_id: $type, config: {}, secrets: {}}' > "${connector_body}"
		kibana_request POST '/api/actions/connector' "${connector_body}" > "${connector_response}"
		connector_id=$(jq -er --arg type "${connector_type}" \
			'select(.connector_type_id == $type) | .id' "${connector_response}")
	else
		echo "Connecteur absent : ${connector_name} (${connector_type})." >&2
		exit 1
	fi
fi

rule_count=$(jq '.rules | length' "${rendered_definition}")

for ((index = 0; index < rule_count; index++)); do
	rule_file="${tmp_dir}/rule-${index}.json"
	create_file="${tmp_dir}/create-${index}.json"
	update_file="${tmp_dir}/update-${index}.json"
	response_file="${tmp_dir}/response-${index}.json"

	jq --argjson index "${index}" '.rules[$index]' "${rendered_definition}" > "${rule_file}"
	rule_id=$(jq -er '.id' "${rule_file}")
	rule_name=$(jq -er '.name' "${rule_file}")

	jq \
		--arg connector_id "${connector_id}" \
		--arg dashboard_id "${dashboard_id}" \
		'{
			actions: [
				{
					frequency: {notify_when: "onActionGroupChange", summary: false},
					group: "query matched",
					id: $connector_id,
					params: {
						level: "warn",
						message: "[OpenIRN][ALERTE] {{rule.name}} — {{context.message}}"
					}
				},
				{
					frequency: {notify_when: "onActionGroupChange", summary: false},
					group: "recovered",
					id: $connector_id,
					params: {
						level: "info",
						message: "[OpenIRN][RÉTABLI] {{rule.name}} — {{context.message}}"
					}
				}
			],
			alert_delay: {active: .alertDelay},
			artifacts: {dashboards: [{id: $dashboard_id}]},
			consumer: "stackAlerts",
			enabled: true,
			name: .name,
			params: {
				esqlQuery: {esql: .query},
				groupBy: "all",
				searchType: "esqlQuery",
				size: 0,
				threshold: [0],
				thresholdComparator: ">",
				timeField: "@timestamp",
				timeWindowSize: .timeWindow.size,
				timeWindowUnit: .timeWindow.unit
			},
			rule_type_id: ".es-query",
			schedule: {interval: .schedule},
			tags: [
				"OpenIRN",
				"managed-by-repository",
				("severity:" + .severity),
				("category:" + .category)
			]
		}' "${rule_file}" > "${create_file}"

	http_status=$(kibana_status "/api/alerting/rule/${rule_id}" "${response_file}")

	case ${http_status} in
		200)
			jq 'del(.consumer, .enabled, .rule_type_id)' "${create_file}" > "${update_file}"
			kibana_request PUT "/api/alerting/rule/${rule_id}" "${update_file}" > "${response_file}"
			action='updated'
			;;
		404)
			kibana_request POST "/api/alerting/rule/${rule_id}" "${create_file}" > "${response_file}"
			action='created'
			;;
		*)
			echo "Lecture impossible pour ${rule_id} : HTTP ${http_status}" >&2
			jq -c '{statusCode, error, message}' "${response_file}" >&2 || true
			exit 1
			;;
	esac

	jq -e --arg id "${rule_id}" '.id == $id and .rule_type_id == ".es-query"' "${response_file}" >/dev/null
	printf '%s\t%s	%s\n' "${action}" "${rule_id}" "${rule_name}"
done

echo "${rule_count} règles OpenIRN déployées pour host.name=${monitored_host}."
