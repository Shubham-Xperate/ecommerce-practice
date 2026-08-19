provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false # prod: don't let a stray `destroy` silently purge secrets forever
      recover_soft_deleted_key_vaults = true
    }
  }
}

data "azurerm_client_config" "current" {}
