#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
INFRA_DIR="$ROOT_DIR/infra"
DEFAULT_ENV_FILE="$ROOT_DIR/config/cyclecloud.env"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

resolve_env_file() {
  local candidate="${1:-${DEPLOY_ENV_FILE:-$DEFAULT_ENV_FILE}}"

  if [[ ! -f "$candidate" ]]; then
    echo "Environment file not found: $candidate" >&2
    echo "Copy config/cyclecloud.env.example.org to config/cyclecloud.env and edit it first." >&2
    exit 1
  fi

  printf '%s\n' "$candidate"
}

export_if_unset() {
  local target_name="$1"
  local source_name="$2"

  if [[ -z "${!target_name:-}" && -n "${!source_name:-}" ]]; then
    export "$target_name=${!source_name}"
  fi
}

require_env_value() {
  local name="$1"

  if [[ -z "${!name:-}" ]]; then
    echo "Missing required value: $name" >&2
    exit 1
  fi
}

load_env_file() {
  local env_file="$1"

  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a

  export_if_unset TF_VAR_subscription_id SUBS_ID
  export_if_unset TF_VAR_location REGION
  export_if_unset TF_VAR_resource_group_name RESOURCE_GROUP
  export_if_unset TF_VAR_managed_identity_name MANAGED_ID
  export_if_unset TF_VAR_vnet_name VNET_NAME
  export_if_unset TF_VAR_vnet_cidr VNET_RANGE
  export_if_unset TF_VAR_subnet_mngt_name SUBNET_MNGT_NAME
  export_if_unset TF_VAR_subnet_mngt_cidr SUBNET_MNGT_RANGE
  export_if_unset TF_VAR_nsg_mngt_name NSG_MNGT_NAME
  export_if_unset TF_VAR_subnet_cluster_name SUBNET_CLUSTER_NAME
  export_if_unset TF_VAR_subnet_cluster_cidr SUBNET_CLUSTER_RANGE
  export_if_unset TF_VAR_nsg_cluster_name NSG_CLUSTER_NAME
  export_if_unset TF_VAR_subnet_anf_name SUBNET_ANF_NAME
  export_if_unset TF_VAR_subnet_anf_cidr SUBNET_ANF_RANGE
  export_if_unset TF_VAR_nsg_anf_name NSG_ANF_NAME
  export_if_unset TF_VAR_subnet_amlfs_name SUBNET_AMLFS_NAME
  export_if_unset TF_VAR_subnet_amlfs_cidr SUBNET_AMLFS_RANGE
  export_if_unset TF_VAR_nsg_amlfs_name NSG_AMLFS_NAME
  export_if_unset TF_VAR_nat_gateway_name NATGW_NAME
  export_if_unset TF_VAR_nat_public_ip_name NATGW_PIP
  export_if_unset TF_VAR_storage_account_name STGACCT_CC
  export_if_unset TF_VAR_private_endpoint_name PEP_STGACC_CC
  export_if_unset TF_VAR_private_endpoint_connection_name PEP_CONN_NAME
  export_if_unset TF_VAR_private_dns_zone_name PRIVATE_DNSZONE_NAME
  export_if_unset TF_VAR_private_dns_zone_link_name PRIVATE_DNSZONE_LINKNAME
  export_if_unset TF_VAR_anf_account_name ANF_ACCOUNT
  export_if_unset TF_VAR_anf_pool_name ANF_POOL
  export_if_unset TF_VAR_anf_volume_name ANF_VOLUME
  export_if_unset TF_VAR_anf_service_level ANF_TIER
  export_if_unset TF_VAR_anf_pool_size_tb ANF_POOL_SIZE
  export_if_unset TF_VAR_anf_pool_throughput_mibps ANF_POOL_THPT
  export_if_unset TF_VAR_anf_volume_size_gib ANF_VOLUME_SIZE
  export_if_unset TF_VAR_anf_volume_throughput_mibps ANF_VOLUME_THPT
  export_if_unset TF_VAR_cyclecloud_vm_name CC_VM_NAME
  export_if_unset TF_VAR_cyclecloud_nic_name NIC_CC
  export_if_unset TF_VAR_cyclecloud_vm_size VM_SIZE_CC
  export_if_unset TF_VAR_cyclecloud_image_urn IMAGE_CC
  export_if_unset TF_VAR_cyclecloud_admin_username CC_ADMIN
  export_if_unset TF_VAR_cyclecloud_private_ip_host CC_PRIVATE_IP_HOST
  export_if_unset TF_VAR_management_source_cidrs_csv MANAGEMENT_SOURCE_CIDRS

  if [[ -z "${TF_VAR_cc_admin_ssh_public_key:-}" && -n "${CC_ADMIN_SSH_PUBKEY:-}" ]]; then
    export TF_VAR_cc_admin_ssh_public_key="$CC_ADMIN_SSH_PUBKEY"
  fi

  if [[ -z "${TF_VAR_cc_admin_ssh_public_key:-}" && -n "${CC_ADMIN_SSH_PUBKEY_FILE:-}" ]]; then
    if [[ ! -f "$CC_ADMIN_SSH_PUBKEY_FILE" ]]; then
      echo "SSH public key file not found: $CC_ADMIN_SSH_PUBKEY_FILE" >&2
      exit 1
    fi

    export TF_VAR_cc_admin_ssh_public_key
    TF_VAR_cc_admin_ssh_public_key=$(tr -d '\r\n' < "$CC_ADMIN_SSH_PUBKEY_FILE")
  fi

  require_env_value TF_VAR_subscription_id
  require_env_value TF_VAR_location
  require_env_value TF_VAR_resource_group_name
  require_env_value TF_VAR_managed_identity_name
  require_env_value TF_VAR_vnet_name
  require_env_value TF_VAR_vnet_cidr
  require_env_value TF_VAR_subnet_mngt_name
  require_env_value TF_VAR_subnet_mngt_cidr
  require_env_value TF_VAR_nsg_mngt_name
  require_env_value TF_VAR_subnet_cluster_name
  require_env_value TF_VAR_subnet_cluster_cidr
  require_env_value TF_VAR_nsg_cluster_name
  require_env_value TF_VAR_subnet_anf_name
  require_env_value TF_VAR_subnet_anf_cidr
  require_env_value TF_VAR_nsg_anf_name
  require_env_value TF_VAR_subnet_amlfs_name
  require_env_value TF_VAR_subnet_amlfs_cidr
  require_env_value TF_VAR_nsg_amlfs_name
  require_env_value TF_VAR_nat_gateway_name
  require_env_value TF_VAR_nat_public_ip_name
  require_env_value TF_VAR_storage_account_name
  require_env_value TF_VAR_private_endpoint_name
  require_env_value TF_VAR_private_endpoint_connection_name
  require_env_value TF_VAR_private_dns_zone_name
  require_env_value TF_VAR_private_dns_zone_link_name
  require_env_value TF_VAR_anf_account_name
  require_env_value TF_VAR_anf_pool_name
  require_env_value TF_VAR_anf_volume_name
  require_env_value TF_VAR_cyclecloud_vm_name
  require_env_value TF_VAR_cyclecloud_nic_name
  require_env_value TF_VAR_cyclecloud_vm_size
  require_env_value TF_VAR_cyclecloud_image_urn
  require_env_value TF_VAR_cyclecloud_admin_username
  require_env_value TF_VAR_cc_admin_ssh_public_key
}

prepare_context() {
  local env_file

  env_file=$(resolve_env_file "${1:-}")
  load_env_file "$env_file"

  require_command az
  require_command terraform

  az account show >/dev/null
  az account set --subscription "$TF_VAR_subscription_id" >/dev/null

  if [[ -z "${ARM_TENANT_ID:-}" ]]; then
    export ARM_TENANT_ID
    ARM_TENANT_ID=$(az account show --query tenantId -o tsv)
  fi
}