terraform {
  required_version = ">= 1.14.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.70"
    }
  }
}

provider "azurerm" {
  subscription_id     = var.subscription_id
  storage_use_azuread = true

  features {
    netapp {
      # This sample is intended for lab-style creation and teardown.
      prevent_volume_destruction             = false
      delete_backups_on_backup_vault_destroy = false
    }
  }
}

data "azurerm_client_config" "current" {}