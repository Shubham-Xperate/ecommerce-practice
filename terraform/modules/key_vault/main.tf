resource "azurerm_key_vault" "main" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = var.tenant_id
  sku_name            = "standard"

  # RBAC mode (not the legacy access-policy model): access is granted via
  # normal azurerm_role_assignment resources against Azure roles, the same
  # mechanism used for every other resource type -- one consistent
  # permission model instead of two.
  rbac_authorization_enabled = true

  # Soft-delete can't be disabled on Key Vault, but purge protection CAN be,
  # and we want it off here: this is meant to be destroyed/recreated
  # repeatedly, and purge protection would block that (see the root
  # module's providers.tf `purge_soft_delete_on_destroy` for the other
  # half of this).
  purge_protection_enabled   = var.purge_protection_enabled
  soft_delete_retention_days = 7

  tags = var.tags
}

# Under RBAC mode, even the person who CREATED the vault has zero access
# by default -- unlike legacy access-policy mode, which auto-granted the
# creator full rights. Without this, `terraform apply` succeeds fine but
# you get "Forbidden" the moment you try to read/write a secret.
resource "azurerm_role_assignment" "current_user_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = var.current_user_object_id
}
