#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

prepare_context "${1:-}"

IMAGE_PUBLISHER=${TF_VAR_cyclecloud_image_urn%%:*}
IMAGE_REMAINDER=${TF_VAR_cyclecloud_image_urn#*:}
IMAGE_OFFER=${IMAGE_REMAINDER%%:*}
IMAGE_PLAN_VERSION=${IMAGE_REMAINDER#*:}
IMAGE_PLAN=${IMAGE_PLAN_VERSION%%:*}
MARKETPLACE_AGREEMENT_ID="/subscriptions/${TF_VAR_subscription_id}/providers/Microsoft.MarketplaceOrdering/agreements/${IMAGE_PUBLISHER}/offers/${IMAGE_OFFER}/plans/${IMAGE_PLAN}"

echo "Registering Microsoft.NetApp provider if needed..."
az provider register --namespace Microsoft.NetApp --wait >/dev/null

cd "$INFRA_DIR"

terraform init -upgrade

if ! terraform state show azurerm_marketplace_agreement.cyclecloud >/dev/null 2>&1; then
	if az rest --method get --url "https://management.azure.com${MARKETPLACE_AGREEMENT_ID}?api-version=2015-06-01" >/dev/null 2>&1; then
		echo "Importing existing Marketplace agreement into Terraform state..."
		terraform import azurerm_marketplace_agreement.cyclecloud "$MARKETPLACE_AGREEMENT_ID"
	fi
fi

terraform validate
terraform plan -out=tfplan
terraform apply -auto-approve tfplan

echo
echo "Deployment outputs"
terraform output

echo
echo "Terraform deployment finished before CycleCloud portal initialization."
echo 'Proceed to "Configuration" section in https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/service-principals?view=cyclecloud-8'