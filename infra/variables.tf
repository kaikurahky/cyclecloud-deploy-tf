variable "subscription_id" {
  type        = string
  description = "Azure subscription ID used by the azurerm provider."
}

variable "location" {
  type        = string
  description = "Azure region where resources are deployed."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name for the CycleCloud lab."
}

variable "managed_identity_name" {
  type        = string
  description = "User assigned managed identity name for CycleCloud."
}

variable "vnet_name" {
  type        = string
  description = "Virtual network name."
}

variable "vnet_cidr" {
  type        = string
  description = "Address space for the virtual network."
}

variable "subnet_cluster_name" {
  type        = string
  description = "Subnet name used by CycleCloud and cluster resources."
}

variable "subnet_cluster_cidr" {
  type        = string
  description = "CIDR block for the cluster subnet."
}

variable "nsg_cluster_name" {
  type        = string
  description = "Network security group name for the cluster subnet."
}

variable "subnet_anf_name" {
  type        = string
  description = "Delegated subnet name for Azure NetApp Files."
}

variable "subnet_anf_cidr" {
  type        = string
  description = "CIDR block for the ANF subnet."
}

variable "nsg_anf_name" {
  type        = string
  description = "Network security group name for the ANF subnet."
}

variable "nat_gateway_name" {
  type        = string
  description = "NAT Gateway name for outbound internet access."
}

variable "nat_public_ip_name" {
  type        = string
  description = "Public IP resource name attached to the NAT Gateway."
}

variable "storage_account_name" {
  type        = string
  description = "Globally unique storage account name for CycleCloud locker storage."

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 lowercase alphanumeric characters."
  }
}

variable "private_endpoint_name" {
  type        = string
  description = "Private endpoint name for the storage account."
}

variable "private_endpoint_connection_name" {
  type        = string
  description = "Private service connection name for the storage account private endpoint."
}

variable "private_dns_zone_name" {
  type        = string
  description = "Private DNS zone for blob private endpoint resolution."
  default     = "privatelink.blob.core.windows.net"
}

variable "private_dns_zone_link_name" {
  type        = string
  description = "VNet link name for the private DNS zone."
}

variable "anf_account_name" {
  type        = string
  description = "Azure NetApp Files account name."
}

variable "anf_pool_name" {
  type        = string
  description = "Azure NetApp Files capacity pool name."
}

variable "anf_volume_name" {
  type        = string
  description = "Azure NetApp Files volume name."
}

variable "anf_service_level" {
  type        = string
  description = "Azure NetApp Files service level."
  default     = "Flexible"

  validation {
    condition     = contains(["Standard", "Premium", "Ultra", "Flexible"], var.anf_service_level)
    error_message = "anf_service_level must be one of Standard, Premium, Ultra, Flexible."
  }
}

variable "anf_pool_size_tb" {
  type        = number
  description = "ANF capacity pool size in TiB."
  default     = 1
}

variable "anf_pool_throughput_mibps" {
  type        = number
  description = "Custom throughput for the ANF Flexible pool in MiB/s."
  default     = 128
}

variable "anf_volume_size_gib" {
  type        = number
  description = "Storage quota for the ANF volume in GiB."
  default     = 1024
}

variable "anf_volume_throughput_mibps" {
  type        = number
  description = "Throughput for the ANF volume in MiB/s."
  default     = 128
}

variable "cyclecloud_vm_name" {
  type        = string
  description = "CycleCloud VM name."
}

variable "cyclecloud_nic_name" {
  type        = string
  description = "CycleCloud NIC name."
}

variable "cyclecloud_vm_size" {
  type        = string
  description = "CycleCloud VM SKU."
}

variable "cyclecloud_image_urn" {
  type        = string
  description = "Marketplace URN in publisher:offer:sku:version format."

  validation {
    condition     = length(split(":", var.cyclecloud_image_urn)) == 4
    error_message = "cyclecloud_image_urn must use publisher:offer:sku:version format."
  }
}

variable "cyclecloud_admin_username" {
  type        = string
  description = "Admin username for the CycleCloud VM."
}

variable "cc_admin_ssh_public_key" {
  type        = string
  description = "SSH public key content for the CycleCloud VM admin user."
  sensitive   = true
}

variable "cyclecloud_private_ip_host" {
  type        = number
  description = "Host number inside the cluster subnet used for the CycleCloud VM private IP."
  default     = 10
}

variable "management_source_cidrs_csv" {
  type        = string
  description = "Optional comma-separated CIDRs allowed to reach ports 22 and 9443 over private connectivity."
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Optional extra tags applied to all resources."
  default     = {}
}