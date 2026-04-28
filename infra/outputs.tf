output "resource_group_name" {
  description = "Resource group containing the CycleCloud deployment."
  value       = azurerm_resource_group.this.name
}

output "cyclecloud_vm_id" {
  description = "Resource ID of the CycleCloud VM."
  value       = format("%s/providers/Microsoft.Compute/virtualMachines/%s", azurerm_resource_group.this.id, var.cyclecloud_vm_name)
}

output "cyclecloud_private_ip" {
  description = "Private IP address of the CycleCloud VM."
  value       = azurerm_network_interface.cyclecloud.private_ip_address
}

output "cyclecloud_portal_url" {
  description = "CycleCloud portal URL reachable from a private network path or Bastion tunnel."
  value       = "https://${azurerm_network_interface.cyclecloud.private_ip_address}:9443"
}

output "managed_identity_client_id" {
  description = "Client ID used in the CycleCloud initial setup wizard."
  value       = azurerm_user_assigned_identity.cyclecloud.client_id
}

output "managed_identity_principal_id" {
  description = "Principal ID of the user assigned managed identity."
  value       = azurerm_user_assigned_identity.cyclecloud.principal_id
}

output "storage_account_name" {
  description = "CycleCloud locker storage account name."
  value       = azurerm_storage_account.cyclecloud.name
}

output "storage_blob_private_fqdn" {
  description = "FQDN resolved through the private endpoint for blob access."
  value       = "${azurerm_storage_account.cyclecloud.name}.blob.core.windows.net"
}

output "anf_mount_ip" {
  description = "IP address used to mount the Azure NetApp Files volume."
  value       = azurerm_netapp_volume.this.mount_ip_addresses[0]
}

output "anf_export_path" {
  description = "NFS export path for the Azure NetApp Files volume."
  value       = "/${azurerm_netapp_volume.this.volume_path}"
}