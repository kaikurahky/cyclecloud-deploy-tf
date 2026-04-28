#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

prepare_context "${1:-}"

require_command jq
require_command python3
require_command base64

OUTPUT_JSON=$(mktemp)
PAYLOAD_JSON=$(mktemp)
RUN_COMMAND_JSON=$(mktemp)
cleanup() {
  rm -f "$OUTPUT_JSON" "$PAYLOAD_JSON" "$RUN_COMMAND_JSON"
}
trap cleanup EXIT

LOG_DIR="$ROOT_DIR/logs"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MESSAGE_LOG="$LOG_DIR/bootstrap_cyclecloud_${TIMESTAMP}.log"
RESULT_LOG="$LOG_DIR/bootstrap_cyclecloud_${TIMESTAMP}.json"

terraform -chdir="$INFRA_DIR" output -json >"$OUTPUT_JSON"
python3 "$SCRIPT_DIR/render_cyclecloud_payload.py" "$OUTPUT_JSON" >"$PAYLOAD_JSON"

PAYLOAD_BASE64=$(base64 -w0 <"$PAYLOAD_JSON")
RUN_COMMAND_SCRIPT=$(cat <<EOF
cat > /tmp/cyclecloud-bootstrap-payload.b64 <<'PAYLOAD_EOF'
$PAYLOAD_BASE64
PAYLOAD_EOF
base64 -d /tmp/cyclecloud-bootstrap-payload.b64 > /tmp/cyclecloud-bootstrap-payload.json
$(cat "$SCRIPT_DIR/bootstrap_cyclecloud_remote.sh")
EOF
)

echo "Running CycleCloud bootstrap on VM $TF_VAR_cyclecloud_vm_name..."
echo "Run Command logs will be saved to: $MESSAGE_LOG"
az vm run-command invoke \
  --command-id RunShellScript \
  --resource-group "$TF_VAR_resource_group_name" \
  --name "$TF_VAR_cyclecloud_vm_name" \
  --scripts "$RUN_COMMAND_SCRIPT" \
  -o json >"$RUN_COMMAND_JSON"

cp "$RUN_COMMAND_JSON" "$RESULT_LOG"
jq -r '.value[0].message // empty' "$RUN_COMMAND_JSON" | tee "$MESSAGE_LOG"

if ! jq -e '.value[0].code == "ProvisioningState/succeeded"' "$RUN_COMMAND_JSON" >/dev/null; then
  echo "CycleCloud bootstrap Run Command failed. See $RESULT_LOG and $MESSAGE_LOG" >&2
  exit 1
fi

if ! grep -q '^BOOTSTRAP_RESULT:SUCCESS$' "$MESSAGE_LOG"; then
  echo "CycleCloud bootstrap did not report success. See $RESULT_LOG and $MESSAGE_LOG" >&2
  exit 1
fi

for marker in \
  'CHECK:INITIAL_USER=PASS' \
  'CHECK:INSTALLATION_COMPLETE=PASS' \
  'CHECK:CYCLECLOUD_CLI_INIT=PASS' \
  'CHECK:ADD_SUBSCRIPTION=PASS' \
  'CHECK:LOCKER_READY=PASS'; do
  if ! grep -q "^${marker}$" "$MESSAGE_LOG"; then
    echo "Missing bootstrap verification marker ${marker}. See $RESULT_LOG and $MESSAGE_LOG" >&2
    exit 1
  fi
done

echo "CycleCloud bootstrap verification passed. Logs: $MESSAGE_LOG"