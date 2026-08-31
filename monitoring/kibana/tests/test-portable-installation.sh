#!/usr/bin/env bash
set -euo pipefail

test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
kibana_dir=$(CDPATH= cd -- "${test_dir}/.." && pwd)
tmp_dir=$(mktemp -d)

cleanup() {
	rm -rf -- "${tmp_dir}"
}
trap cleanup EXIT

export PATH="${test_dir}/bin:${PATH}"
export FAKE_CURL_LOG="${tmp_dir}/curl.log"
export KIBANA_URL='https://kibana.other-infra.example/'
export KIBANA_API_KEY='placeholder'
export OPENIRN_MONITORED_HOST='api-node.other-infra.example'

"${kibana_dir}/install-monitoring.sh" > "${tmp_dir}/install.log"

grep -Fq $'PUT\thttps://kibana.other-infra.example/api/dashboards/openirn-api-health-security' "${FAKE_CURL_LOG}"
grep -Fq $'POST\thttps://kibana.other-infra.example/api/actions/connector' "${FAKE_CURL_LOG}"

rule_gets=$(grep -Fc $'GET\thttps://kibana.other-infra.example/api/alerting/rule/' "${FAKE_CURL_LOG}")
rule_creates=$(grep -Fc $'POST\thttps://kibana.other-infra.example/api/alerting/rule/' "${FAKE_CURL_LOG}")
if [[ ${rule_gets} -ne 19 || ${rule_creates} -ne 19 ]]; then
	echo "Cycle de règles incomplet : GET=${rule_gets}, POST=${rule_creates}" >&2
	exit 1
fi

grep -Fq 'Installation du monitoring OpenIRN terminée.' "${tmp_dir}/install.log"
echo 'Installation portable simulée : dashboard, connecteur local et 19 règles créés.'
