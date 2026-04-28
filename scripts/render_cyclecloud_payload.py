#!/usr/bin/env python3

import json
import os
import sys


def require_env(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise SystemExit(f"Missing required value: {name}")
    return value


def env_bool(name: str, default: bool = False) -> bool:
    value = os.getenv(name)
    if value is None or value == "":
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def env_int(name: str, default: int | None = None) -> int:
    value = os.getenv(name)
    if value is None or value == "":
        if default is None:
            raise SystemExit(f"Missing required integer value: {name}")
        return default
    try:
        return int(value)
    except ValueError as exc:
        raise SystemExit(f"Invalid integer value for {name}: {value}") from exc


def env_json(name: str, default):
    value = os.getenv(name)
    if value is None or value == "":
        return default
    try:
        return json.loads(value)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Invalid JSON value for {name}: {exc}") from exc


def tf_output(outputs: dict, name: str):
    try:
        return outputs[name]["value"]
    except KeyError as exc:
        raise SystemExit(f"Terraform output not found: {name}") from exc


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: render_cyclecloud_payload.py <terraform-output-json>")

    with open(sys.argv[1], encoding="utf-8") as handle:
        outputs = json.load(handle)

    subscription_id = require_env("TF_VAR_subscription_id")
    location = require_env("TF_VAR_location")
    resource_group = tf_output(outputs, "resource_group_name")
    managed_identity_name = require_env("TF_VAR_managed_identity_name")
    vnet_name = require_env("TF_VAR_vnet_name")
    subnet_name = require_env("TF_VAR_subnet_cluster_name")
    managed_identity_id = (
        f"/subscriptions/{subscription_id}/resourceGroups/{resource_group}"
        f"/providers/Microsoft.ManagedIdentity/userAssignedIdentities/{managed_identity_name}"
    )

    slurm_parameters = {
        "Autoscale": env_bool("SLURM_AUTOSCALE", True),
        "Credentials": "azure",
        "SubnetId": f"{resource_group}/{vnet_name}/{subnet_name}",
        "Region": location,
        "UsePublicNetwork": env_bool("SLURM_USE_PUBLIC_NETWORK", False),
        "ExecuteNodesPublic": env_bool("SLURM_EXECUTE_NODES_PUBLIC", False),
        "ReturnProxy": env_bool("SLURM_RETURN_PROXY", False),
        "ManagedIdentity": managed_identity_id,
        "BootDiskSize": env_int("SLURM_BOOT_DISK_SIZE", 0),
        "EnableNodeHealthChecks": env_bool("SLURM_ENABLE_NODE_HEALTH_CHECKS", False),
        "configuration_slurm_version": require_env("SLURM_VERSION"),
        "SchedulerMachineType": require_env("SLURM_SCHEDULER_VM_SIZE"),
        "SchedulerImageName": require_env("SLURM_SCHEDULER_IMAGE"),
        "loginMachineType": require_env("SLURM_LOGIN_VM_SIZE"),
        "LoginImageName": require_env("SLURM_LOGIN_IMAGE"),
        "NumberLoginNodes": env_int("SLURM_LOGIN_INITIAL_NODES", 1),
        "MaxLoginNodeCount": env_int("SLURM_LOGIN_MAX_NODES", 1),
        "HTCMachineType": require_env("SLURM_HTC_VM_SIZE"),
        "HTCImageName": require_env("SLURM_HTC_IMAGE"),
        "MaxHTCExecuteNodeCount": env_int("SLURM_HTC_MAX_NODES", 0),
        "HTCUseLowPrio": env_bool("SLURM_HTC_USE_SPOT", False),
        "HPCMachineType": require_env("SLURM_HPC_VM_SIZE"),
        "HPCImageName": require_env("SLURM_HPC_IMAGE"),
        "MaxHPCExecuteNodeCount": env_int("SLURM_HPC_MAX_NODES", 0),
        "HPCUseLowPrio": env_bool("SLURM_HPC_USE_SPOT", False),
        "GPUMachineType": require_env("SLURM_GPU_VM_SIZE"),
        "GPUImageName": require_env("SLURM_GPU_IMAGE"),
        "MaxGPUExecuteNodeCount": env_int("SLURM_GPU_MAX_NODES", 0),
        "GPUUseLowPrio": env_bool("SLURM_GPU_USE_SPOT", False),
        "UseBuiltinSched": env_bool("SLURM_USE_BUILTIN_SCHED", True),
        "UseBuiltinShared": False,
        "NFSType": "nfs",
        "NFSAddress": tf_output(outputs, "anf_mount_ip"),
        "NFSSharedExportPath": tf_output(outputs, "anf_export_path"),
        "NFSSharedMountOptions": os.getenv(
            "SLURM_SHARED_MOUNT_OPTIONS",
            "vers=4.1,sec=sys,_netdev,nconnect=8",
        ),
        "AdditionalNFS": False,
        "configuration_slurm_accounting_enabled": False,
        "NodeTags": env_json("SLURM_NODE_TAGS_JSON", {}),
    }

    additional_slurm_config = os.getenv("SLURM_ADDITIONAL_CONFIG", "")
    if additional_slurm_config:
        slurm_parameters["additional_slurm_config"] = additional_slurm_config

    payload = {
        "cyclecloud": {
            "admin_username": require_env("TF_VAR_cyclecloud_admin_username"),
            "admin_password": require_env("CYCLECLOUD_ADMIN_PASSWORD"),
            "ssl_port": env_int("CYCLECLOUD_PORTAL_PORT", 9443),
            "resource_group": resource_group,
            "location": location,
            "subscription_id": subscription_id,
            "tenant_id": os.getenv("ARM_TENANT_ID", ""),
            "storage_account": tf_output(outputs, "storage_account_name"),
            "storage_managed_identity": managed_identity_id,
            "accept_marketplace_terms": env_bool("CYCLECLOUD_ACCEPT_MARKETPLACE_TERMS", True),
        },
        "slurm": {
            "cluster_name": require_env("SLURM_CLUSTER_NAME"),
            "start_cluster": env_bool("SLURM_START_CLUSTER", True),
            "parameters": slurm_parameters,
        },
    }

    json.dump(payload, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()