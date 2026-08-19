provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

# Gives us the currently-logged-in `az login` identity's tenant/object ID,
# so we can grant ourselves Key Vault access without hardcoding an object ID.
data "azurerm_client_config" "current" {}
