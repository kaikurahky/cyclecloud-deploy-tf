#!/usr/bin/env bash
set -euo pipefail

PAYLOAD_PATH=/tmp/cyclecloud-bootstrap-payload.json
CS_HOME=/opt/cycle_server
CS_CMD="$CS_HOME/cycle_server"
BOOTSTRAP_LOG=/var/log/cyclecloud-bootstrap.log

mkdir -p "$(dirname "$BOOTSTRAP_LOG")"
touch "$BOOTSTRAP_LOG"
exec > >(tee -a "$BOOTSTRAP_LOG") 2>&1

log_step() {
  echo "STEP:$1"
}

mark_pass() {
  echo "CHECK:$1=PASS"
}

mark_fail() {
  echo "CHECK:$1=FAIL"
}

trap 'mark_fail UNHANDLED_ERROR; echo "BOOTSTRAP_RESULT:FAILURE"' ERR

retry() {
  local attempts="$1"
  local delay="$2"
  shift 2

  local attempt=1
  until "$@"; do
    if (( attempt >= attempts )); then
      return 1
    fi
    sleep "$delay"
    attempt=$((attempt + 1))
  done
}

install_package() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" >/dev/null
  else
    yum install -y "$@" >/dev/null
  fi
}

ensure_command() {
  if command -v "$1" >/dev/null 2>&1; then
    return 0
  fi

  case "$1" in
    jq)
      install_package jq
      ;;
    unzip)
      install_package unzip
      ;;
    curl)
      install_package curl
      ;;
    *)
      echo "Unsupported dependency: $1" >&2
      return 1
      ;;
  esac
}

wait_for_import_queue() {
  local deadline=$((SECONDS + 360))

  while (( SECONDS < deadline )); do
    shopt -s nullglob
    local pending=($CS_HOME/config/data/*.json $CS_HOME/config/data/*.txt)
    shopt -u nullglob
    if (( ${#pending[@]} == 0 )); then
      return 0
    fi
    sleep 5
  done

  echo "Timed out waiting for CycleCloud config imports." >&2
  return 1
}

wait_for_https() {
  local port="$1"
  retry 120 5 curl -sk "https://localhost:${port}" >/dev/null
}

ensure_cyclecloud_cli() {
  if command -v cyclecloud >/dev/null 2>&1; then
    return 0
  fi

  ensure_command unzip
  local temp_dir
  temp_dir=$(mktemp -d)
  unzip -q "$CS_HOME/tools/cyclecloud-cli.zip" -d "$temp_dir"
  local installer_dir
  installer_dir=$(find "$temp_dir" -maxdepth 1 -type d -name 'cyclecloud-cli-installer*' | head -n 1)
  "$installer_dir/install.sh" --system >/dev/null
  rm -rf "$temp_dir"
}

run_cs_query() {
  local query="$1"
  "$CS_CMD" execute --format json "$query"
}

account_exists() {
  local account_show_output
  account_show_output=$(mktemp)

  if cyclecloud account show azure >"$account_show_output" 2>&1; then
    echo "ADD_SUBSCRIPTION_OUTPUT_BEGIN"
    cat "$account_show_output"
    echo "ADD_SUBSCRIPTION_OUTPUT_END"

    if grep -qi 'Account not found' "$account_show_output"; then
      rm -f "$account_show_output"
      return 1
    fi
  else
    echo "ADD_SUBSCRIPTION_OUTPUT_BEGIN"
    cat "$account_show_output"
    echo "ADD_SUBSCRIPTION_OUTPUT_END"
    rm -f "$account_show_output"
    return 1
  fi

  rm -f "$account_show_output"
  jq -e 'length > 0' < <(run_cs_query 'SELECT Name FROM Cloud.Account WHERE Name=="azure"') >/dev/null 2>&1
}

dump_cyclecloud_diagnostics() {
  echo "DIAGNOSTIC:BEGIN"
  echo "DIAGNOSTIC:CLOUD_ACCOUNT"
  run_cs_query 'SELECT Name, Provider, DefaultAccount, Location, AzureRMSubscriptionId, AzureResourceGroup FROM Cloud.Account WHERE Name=="azure"' || true
  echo "DIAGNOSTIC:CLOUD_LOCKER"
  run_cs_query 'SELECT Name, State, LockerType, Account, Location, Endpoint, Container FROM Cloud.Locker' || true
  echo "DIAGNOSTIC:IMPORT_QUEUE"
  ls -1 "$CS_HOME"/config/data 2>/dev/null || true
  echo "DIAGNOSTIC:END"
}

ensure_command jq
ensure_command curl
ensure_cyclecloud_cli

if [[ ! -x "$CS_CMD" ]]; then
  echo "CycleCloud server command not found at $CS_CMD" >&2
  exit 1
fi

"$CS_CMD" start --wait >/dev/null 2>&1 || true

ADMIN_USER=$(jq -r '.cyclecloud.admin_username' "$PAYLOAD_PATH")
ADMIN_PASSWORD=$(jq -r '.cyclecloud.admin_password' "$PAYLOAD_PATH")
PORTAL_PORT=$(jq -r '.cyclecloud.ssl_port' "$PAYLOAD_PATH")
RESOURCE_GROUP=$(jq -r '.cyclecloud.resource_group' "$PAYLOAD_PATH")
LOCATION=$(jq -r '.cyclecloud.location' "$PAYLOAD_PATH")
STORAGE_ACCOUNT=$(jq -r '.cyclecloud.storage_account' "$PAYLOAD_PATH")
SUBSCRIPTION_ID=$(jq -r '.cyclecloud.subscription_id' "$PAYLOAD_PATH")
TENANT_ID=$(jq -r '.cyclecloud.tenant_id' "$PAYLOAD_PATH")
MANAGED_IDENTITY_ID=$(jq -r '.cyclecloud.storage_managed_identity' "$PAYLOAD_PATH")
ACCEPT_MP_TERMS=$(jq -r '.cyclecloud.accept_marketplace_terms' "$PAYLOAD_PATH")
CLUSTER_NAME=$(jq -r '.slurm.cluster_name' "$PAYLOAD_PATH")
START_CLUSTER=$(jq -r '.slurm.start_cluster' "$PAYLOAD_PATH")

log_step WAIT_FOR_PORTAL
wait_for_https "$PORTAL_PORT"

if ! jq -e 'length > 0' < <(run_cs_query "SELECT Name FROM AuthenticatedUser WHERE Name==\"${ADMIN_USER}\"") >/dev/null 2>&1; then
  log_step CREATE_INITIAL_USER
  temp_dir=$(mktemp -d)
  jq -n \
    --arg admin_user "$ADMIN_USER" \
    --arg admin_password "$ADMIN_PASSWORD" \
    '[
      {
        "AdType": "Application.Setting",
        "Name": "cycleserver.installation.initial_user",
        "Value": $admin_user
      },
      {
        "Category": "system",
        "Status": "internal",
        "AdType": "Application.Setting",
        "Description": "CycleCloud distribution method.",
        "Value": "marketplace",
        "Name": "distribution_method"
      },
      {
        "AdType": "Application.Setting",
        "Name": "cycleserver.installation.complete",
        "Value": true
      },
      {
        "AdType": "AuthenticatedUser",
        "Name": $admin_user,
        "RawPassword": $admin_password,
        "Superuser": true,
        "ForcePasswordReset": false
      }
    ]' >"$temp_dir/account_data.json"
  chown cycle_server:cycle_server "$temp_dir/account_data.json"
  mv "$temp_dir/account_data.json" "$CS_HOME/config/data/account_data.json"
  wait_for_import_queue
  rm -rf "$temp_dir"
fi

if jq -e 'length > 0' < <(run_cs_query "SELECT Name FROM AuthenticatedUser WHERE Name==\"${ADMIN_USER}\"") >/dev/null 2>&1; then
  mark_pass INITIAL_USER
else
  mark_fail INITIAL_USER
  echo "BOOTSTRAP_RESULT:FAILURE"
  exit 1
fi

if jq -e '.[0].Value == true' < <(run_cs_query 'SELECT Value FROM Application.Setting WHERE Name=="cycleserver.installation.complete"') >/dev/null 2>&1; then
  mark_pass INSTALLATION_COMPLETE
else
  mark_fail INSTALLATION_COMPLETE
  echo "BOOTSTRAP_RESULT:FAILURE"
  exit 1
fi

log_step INITIALIZE_CYCLECLOUD_CLI
retry 10 5 cyclecloud initialize --batch --force --url="https://localhost:${PORTAL_PORT}" --verify-ssl=false --username="$ADMIN_USER" --password="$ADMIN_PASSWORD" >/dev/null
mark_pass CYCLECLOUD_CLI_INIT

if ! account_exists; then
  log_step ADD_SUBSCRIPTION
  temp_dir=$(mktemp -d)
  jq -n \
    --arg env "public" \
    --arg resource_group "$RESOURCE_GROUP" \
    --arg subscription_id "$SUBSCRIPTION_ID" \
    --arg tenant_id "$TENANT_ID" \
    --arg location "$LOCATION" \
    --arg storage_account "$STORAGE_ACCOUNT" \
    --argjson accept_terms "$ACCEPT_MP_TERMS" \
    '{
      "Environment": $env,
      "AzureRMUseManagedIdentity": true,
      "AzureResourceGroup": $resource_group,
      "AzureRMSubscriptionId": $subscription_id,
      "AzureRMTenantId": $tenant_id,
      "DefaultAccount": true,
      "Location": $location,
      "Name": "azure",
      "Provider": "azure",
      "ProviderId": $subscription_id,
      "RMStorageAccount": $storage_account,
      "RMStorageContainer": "cyclecloud",
      "AcceptMarketplaceTerms": $accept_terms
    }' >"$temp_dir/azure_data.json"
  echo "ADD_SUBSCRIPTION_REQUEST_BEGIN"
  cat "$temp_dir/azure_data.json"
  echo "ADD_SUBSCRIPTION_REQUEST_END"
  retry 30 10 cyclecloud account create -f "$temp_dir/azure_data.json" >/dev/null
  wait_for_import_queue
  rm -rf "$temp_dir"
fi

if account_exists; then
  mark_pass ADD_SUBSCRIPTION
else
  mark_fail ADD_SUBSCRIPTION
  dump_cyclecloud_diagnostics
  echo "BOOTSTRAP_RESULT:FAILURE"
  exit 1
fi

locker_ready=false
log_step WAIT_FOR_LOCKER
for _ in $(seq 1 12); do
  if "$CS_CMD" execute 'select * from Cloud.Locker Where State=="Created" && Name=="azure-storage"' | grep -q azure-storage; then
    locker_ready=true
    break
  fi
  "$CS_CMD" run_action 'Retry:Cloud.Locker' -f 'Name=="azure-storage"' >/dev/null 2>&1 || true
  sleep 10
done

if [[ "$locker_ready" != true ]]; then
  mark_fail LOCKER_READY
  dump_cyclecloud_diagnostics
  echo "CycleCloud locker azure-storage was not created in time." >&2
  echo "BOOTSTRAP_RESULT:FAILURE"
  exit 1
fi
mark_pass LOCKER_READY

SLURM_VERSION=$(run_cs_query 'SELECT Version FROM Cloud.Project WHERE Name=="Slurm"' | jq -r '.[0].Version')
if [[ -z "$SLURM_VERSION" || "$SLURM_VERSION" == "null" ]]; then
  echo "Unable to resolve the bundled Slurm template version." >&2
  echo "BOOTSTRAP_RESULT:FAILURE"
  exit 1
fi

temp_dir=$(mktemp -d)
jq '.slurm.parameters' "$PAYLOAD_PATH" >"$temp_dir/slurm_params.json"

if ! cyclecloud show_cluster "$CLUSTER_NAME" >/dev/null 2>&1; then
  log_step CREATE_SLURM_CLUSTER
  cyclecloud create_cluster "slurm_template_${SLURM_VERSION}" "$CLUSTER_NAME" -p "$temp_dir/slurm_params.json" >/dev/null
fi

if [[ "$START_CLUSTER" == "true" ]]; then
  log_step START_SLURM_CLUSTER
  cyclecloud start_cluster "$CLUSTER_NAME" >/dev/null
fi

if id "$ADMIN_USER" >/dev/null 2>&1; then
  install -d -o "$ADMIN_USER" -g "$ADMIN_USER" "/home/${ADMIN_USER}/${CLUSTER_NAME}"
  install -o "$ADMIN_USER" -g "$ADMIN_USER" "$temp_dir/slurm_params.json" "/home/${ADMIN_USER}/${CLUSTER_NAME}/slurm_params.json"
fi

rm -rf "$temp_dir"

echo "CycleCloud bootstrap completed for cluster ${CLUSTER_NAME}."
echo "BOOTSTRAP_RESULT:SUCCESS"