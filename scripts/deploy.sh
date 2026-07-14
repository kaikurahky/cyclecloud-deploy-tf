#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

prepare_context "${1:-}"

archive_stale_state() {
	local state_file="$INFRA_DIR/terraform.tfstate"
	local backup_file="$INFRA_DIR/terraform.tfstate.backup"
	local plan_file="$INFRA_DIR/tfplan"
	local stale_subscription_ids
	local archive_dir

	if [[ ! -f "$state_file" ]]; then
		return
	fi

	stale_subscription_ids=$(
		{
			grep -Eoh '/subscriptions/[0-9a-fA-F-]{36}' "$state_file" 2>/dev/null | sed 's#.*/subscriptions/##' || true
			grep -Eoh '"subscription_id"[[:space:]]*:[[:space:]]*"[0-9a-fA-F-]{36}"' "$state_file" 2>/dev/null | sed -E 's/.*"([0-9a-fA-F-]{36})"/\1/' || true
		} | sort -u | grep -Fvx "$TF_VAR_subscription_id" || true
	)

	if [[ -z "$stale_subscription_ids" ]]; then
		return
	fi

	archive_dir="$INFRA_DIR/state-backup-$(date +%Y%m%d-%H%M%S)"
	mkdir -p "$archive_dir"

	echo "Detected Terraform state for a different subscription:"
	printf '  %s\n' $stale_subscription_ids
	echo "Current subscription: $TF_VAR_subscription_id"
	echo "Archiving stale Terraform state to: $archive_dir"

	mv "$state_file" "$archive_dir/"
	if [[ -f "$backup_file" ]]; then
		mv "$backup_file" "$archive_dir/"
	fi
	if [[ -f "$plan_file" ]]; then
		mv "$plan_file" "$archive_dir/"
	fi
}

archive_stale_state

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