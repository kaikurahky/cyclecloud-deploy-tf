locals {
  image_parts = split(":", var.cyclecloud_image_urn)

  cyclecloud_private_ip = cidrhost(var.subnet_mngt_cidr, var.cyclecloud_private_ip_host)

  management_source_cidrs = [
    for cidr in split(",", var.management_source_cidrs_csv) : trimspace(cidr)
    if trimspace(cidr) != ""
  ]

  common_tags = merge(
    {
      workload   = "cyclecloud-slurm"
      managed_by = "terraform"
      source     = "zenn-article-5252f707f38e2f"
    },
    var.tags,
  )
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_user_assigned_identity" "cyclecloud" {
  name                = var.managed_identity_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags
}

resource "azurerm_role_assignment" "cyclecloud_contributor" {
  scope                            = "/subscriptions/${var.subscription_id}"
  role_definition_name             = "Contributor"
  principal_id                     = azurerm_user_assigned_identity.cyclecloud.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "cyclecloud_storage_blob" {
  scope                            = azurerm_resource_group.this.id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = azurerm_user_assigned_identity.cyclecloud.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_cidr]
  tags                = local.common_tags
}

resource "azurerm_network_security_group" "mngt" {
  name                = var.nsg_mngt_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags
}

resource "azurerm_network_security_group" "cluster" {
  name                = var.nsg_cluster_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags
}

resource "azurerm_network_security_group" "anf" {
  name                = var.nsg_anf_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags
}

resource "azurerm_network_security_group" "amlfs" {
  name                = var.nsg_amlfs_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags
}

resource "azurerm_network_security_rule" "mngt_ssh" {
  for_each = {
    for index, cidr in local.management_source_cidrs : tostring(index) => cidr
  }

  name                        = format("allow-ssh-%02d", tonumber(each.key))
  priority                    = 1000 + tonumber(each.key)
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = each.value
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.mngt.name
}

resource "azurerm_network_security_rule" "mngt_https_admin" {
  for_each = {
    for index, cidr in local.management_source_cidrs : tostring(index) => cidr
  }

  name                        = format("allow-cyclecloud-9443-%02d", tonumber(each.key))
  priority                    = 1100 + tonumber(each.key)
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "9443"
  source_address_prefix       = each.value
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.mngt.name
}

resource "azurerm_subnet" "mngt" {
  name                              = var.subnet_mngt_name
  resource_group_name               = azurerm_resource_group.this.name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [var.subnet_mngt_cidr]
  default_outbound_access_enabled   = false
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_subnet" "cluster" {
  name                              = var.subnet_cluster_name
  resource_group_name               = azurerm_resource_group.this.name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [var.subnet_cluster_cidr]
  default_outbound_access_enabled   = false
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_subnet" "anf" {
  name                            = var.subnet_anf_name
  resource_group_name             = azurerm_resource_group.this.name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [var.subnet_anf_cidr]
  default_outbound_access_enabled = false

  delegation {
    name = "netapp-delegation"

    service_delegation {
      name = "Microsoft.Netapp/volumes"
      actions = [
        "Microsoft.Network/networkinterfaces/*",
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_subnet" "amlfs" {
  name                            = var.subnet_amlfs_name
  resource_group_name             = azurerm_resource_group.this.name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [var.subnet_amlfs_cidr]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet_network_security_group_association" "mngt" {
  subnet_id                 = azurerm_subnet.mngt.id
  network_security_group_id = azurerm_network_security_group.mngt.id
}

resource "azurerm_subnet_network_security_group_association" "cluster" {
  subnet_id                 = azurerm_subnet.cluster.id
  network_security_group_id = azurerm_network_security_group.cluster.id
}

resource "azurerm_subnet_network_security_group_association" "anf" {
  subnet_id                 = azurerm_subnet.anf.id
  network_security_group_id = azurerm_network_security_group.anf.id
}

resource "azurerm_subnet_network_security_group_association" "amlfs" {
  subnet_id                 = azurerm_subnet.amlfs.id
  network_security_group_id = azurerm_network_security_group.amlfs.id
}

resource "azurerm_public_ip" "nat" {
  name                = var.nat_public_ip_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

resource "azurerm_nat_gateway" "this" {
  name                    = var.nat_gateway_name
  location                = azurerm_resource_group.this.location
  resource_group_name     = azurerm_resource_group.this.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  tags                    = local.common_tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "cluster" {
  subnet_id      = azurerm_subnet.cluster.id
  nat_gateway_id = azurerm_nat_gateway.this.id
}

resource "azurerm_subnet_nat_gateway_association" "mngt" {
  subnet_id      = azurerm_subnet.mngt.id
  nat_gateway_id = azurerm_nat_gateway.this.id
}

resource "azurerm_subnet_nat_gateway_association" "anf" {
  subnet_id      = azurerm_subnet.anf.id
  nat_gateway_id = azurerm_nat_gateway.this.id
}

resource "azurerm_subnet_nat_gateway_association" "amlfs" {
  subnet_id      = azurerm_subnet.amlfs.id
  nat_gateway_id = azurerm_nat_gateway.this.id
}

resource "azurerm_storage_account" "cyclecloud" {
  name                              = var.storage_account_name
  resource_group_name               = azurerm_resource_group.this.name
  location                          = azurerm_resource_group.this.location
  account_tier                      = "Standard"
  account_replication_type          = "LRS"
  account_kind                      = "StorageV2"
  access_tier                       = "Hot"
  allow_nested_items_to_be_public   = false
  default_to_oauth_authentication   = true
  https_traffic_only_enabled        = true
  infrastructure_encryption_enabled = true
  local_user_enabled                = false
  min_tls_version                   = "TLS1_2"
  public_network_access_enabled     = false
  shared_access_key_enabled         = false
  tags                              = local.common_tags
}

resource "azurerm_private_dns_zone" "blob" {
  name                = var.private_dns_zone_name
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = var.private_dns_zone_link_name
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = local.common_tags
}

resource "azurerm_private_endpoint" "storage_blob" {
  name                = var.private_endpoint_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.mngt.id
  tags                = local.common_tags

  private_service_connection {
    name                           = var.private_endpoint_connection_name
    private_connection_resource_id = azurerm_storage_account.cyclecloud.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}

resource "azurerm_netapp_account" "this" {
  name                = var.anf_account_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags
}

resource "azurerm_netapp_pool" "this" {
  name                    = var.anf_pool_name
  location                = azurerm_resource_group.this.location
  resource_group_name     = azurerm_resource_group.this.name
  account_name            = azurerm_netapp_account.this.name
  service_level           = var.anf_service_level
  size_in_tb              = var.anf_pool_size_tb
  qos_type                = "Manual"
  custom_throughput_mibps = var.anf_pool_throughput_mibps
  tags                    = local.common_tags
}

resource "azurerm_netapp_volume" "this" {
  name                       = var.anf_volume_name
  location                   = azurerm_resource_group.this.location
  resource_group_name        = azurerm_resource_group.this.name
  account_name               = azurerm_netapp_account.this.name
  pool_name                  = azurerm_netapp_pool.this.name
  volume_path                = var.anf_volume_name
  service_level              = var.anf_service_level
  subnet_id                  = azurerm_subnet.anf.id
  protocols                  = ["NFSv4.1"]
  security_style             = "unix"
  storage_quota_in_gb        = var.anf_volume_size_gib
  throughput_in_mibps        = var.anf_volume_throughput_mibps
  network_features           = "Standard"
  snapshot_directory_visible = false
  tags                       = local.common_tags

  export_policy_rule {
    rule_index          = 1
    allowed_clients     = [var.subnet_cluster_cidr]
    protocol            = ["NFSv4.1"]
    root_access_enabled = true
    unix_read_only      = false
    unix_read_write     = true
  }
}

resource "azurerm_marketplace_agreement" "cyclecloud" {
  publisher = local.image_parts[0]
  offer     = local.image_parts[1]
  plan      = local.image_parts[2]
}

resource "azurerm_network_interface" "cyclecloud" {
  name                = var.cyclecloud_nic_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.mngt.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.cyclecloud_private_ip
  }
}

resource "azurerm_network_interface_security_group_association" "cyclecloud" {
  network_interface_id      = azurerm_network_interface.cyclecloud.id
  network_security_group_id = azurerm_network_security_group.mngt.id
}

resource "azurerm_resource_group_template_deployment" "cyclecloud_vm" {
  name                = "cyclecloud-vm"
  resource_group_name = azurerm_resource_group.this.name
  deployment_mode     = "Incremental"

  template_content = jsonencode({
    "$schema"      = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
    contentVersion = "1.0.0.0"
    parameters = {
      vmName                 = { type = "string" }
      location               = { type = "string" }
      vmSize                 = { type = "string" }
      adminUsername          = { type = "string" }
      sshPublicKey           = { type = "secureString" }
      nicId                  = { type = "string" }
      userAssignedIdentityId = { type = "string" }
      planPublisher          = { type = "string" }
      planProduct            = { type = "string" }
      planName               = { type = "string" }
      imagePublisher         = { type = "string" }
      imageOffer             = { type = "string" }
      imageSku               = { type = "string" }
      imageVersion           = { type = "string" }
      tags                   = { type = "object" }
    }
    resources = [
      {
        type       = "Microsoft.Compute/virtualMachines"
        apiVersion = "2025-04-01"
        name       = "[parameters('vmName')]"
        location   = "[parameters('location')]"
        tags       = "[parameters('tags')]"
        plan = {
          publisher = "[parameters('planPublisher')]"
          product   = "[parameters('planProduct')]"
          name      = "[parameters('planName')]"
        }
        identity = {
          type = "UserAssigned"
          userAssignedIdentities = {
            "[parameters('userAssignedIdentityId')]" = {}
          }
        }
        properties = {
          hardwareProfile = {
            vmSize = "[parameters('vmSize')]"
          }
          storageProfile = {
            imageReference = {
              publisher = "[parameters('imagePublisher')]"
              offer     = "[parameters('imageOffer')]"
              sku       = "[parameters('imageSku')]"
              version   = "[parameters('imageVersion')]"
            }
            osDisk = {
              name         = "[format('{0}-osdisk', parameters('vmName'))]"
              createOption = "FromImage"
              caching      = "ReadWrite"
              diskSizeGB   = 128
              managedDisk = {
                storageAccountType = "Premium_LRS"
              }
            }
            dataDisks = [
              {
                name         = "[format('{0}-datadisk0', parameters('vmName'))]"
                lun          = 0
                createOption = "FromImage"
                caching      = "ReadWrite"
                managedDisk = {
                  storageAccountType = "Premium_LRS"
                }
              }
            ]
          }
          networkProfile = {
            networkInterfaces = [
              {
                id = "[parameters('nicId')]"
                properties = {
                  primary = true
                }
              }
            ]
          }
          osProfile = {
            computerName  = "[parameters('vmName')]"
            adminUsername = "[parameters('adminUsername')]"
            linuxConfiguration = {
              disablePasswordAuthentication = true
              ssh = {
                publicKeys = [
                  {
                    path    = "[format('/home/{0}/.ssh/authorized_keys', parameters('adminUsername'))]"
                    keyData = "[parameters('sshPublicKey')]"
                  }
                ]
              }
            }
          }
        }
      }
    ]
  })

  parameters_content = jsonencode({
    vmName                 = { value = var.cyclecloud_vm_name }
    location               = { value = azurerm_resource_group.this.location }
    vmSize                 = { value = var.cyclecloud_vm_size }
    adminUsername          = { value = var.cyclecloud_admin_username }
    sshPublicKey           = { value = var.cc_admin_ssh_public_key }
    nicId                  = { value = azurerm_network_interface.cyclecloud.id }
    userAssignedIdentityId = { value = azurerm_user_assigned_identity.cyclecloud.id }
    planPublisher          = { value = local.image_parts[0] }
    planProduct            = { value = local.image_parts[1] }
    planName               = { value = local.image_parts[2] }
    imagePublisher         = { value = local.image_parts[0] }
    imageOffer             = { value = local.image_parts[1] }
    imageSku               = { value = local.image_parts[2] }
    imageVersion           = { value = local.image_parts[3] }
    tags                   = { value = local.common_tags }
  })

  depends_on = [
    azurerm_marketplace_agreement.cyclecloud,
    azurerm_network_interface_security_group_association.cyclecloud,
  ]
}