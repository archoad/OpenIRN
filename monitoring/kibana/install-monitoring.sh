#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

"${script_dir}/deploy-dashboard.sh"
"${script_dir}/deploy-alerting-rules.sh"

echo 'Installation du monitoring OpenIRN terminée.'
