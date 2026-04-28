#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

prepare_context "${1:-}"

echo "Registering Microsoft.NetApp provider if needed..."
az provider register --namespace Microsoft.NetApp --wait >/dev/null

cd "$INFRA_DIR"

terraform init -upgrade
terraform validate
terraform plan -out=tfplan

echo
echo "Plan file created: $INFRA_DIR/tfplan"