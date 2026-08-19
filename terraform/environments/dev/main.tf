resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

module "network" {
  source = "../../modules/network"

  resource_group_name     = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  vnet_name               = "vnet-shared-services"
  address_space           = var.vnet_address_space
  aks_subnet_prefix       = var.aks_subnet_prefix
  apiserver_subnet_prefix = var.apiserver_subnet_prefix
  tags                    = var.tags
}

module "acr" {
  source = "../../modules/acr"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  name                = var.acr_name
  tags                = var.tags
}

module "key_vault" {
  source = "../../modules/key_vault"

  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  name                     = var.key_vault_name
  tenant_id                = data.azurerm_client_config.current.tenant_id
  current_user_object_id   = data.azurerm_client_config.current.object_id
  purge_protection_enabled = false # dev: allow full destroy/recreate cycles
  tags                     = var.tags
}

module "aks" {
  source = "../../modules/aks"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  name                = var.aks_cluster_name
  sku_tier            = var.aks_sku_tier
  node_count          = var.aks_node_count
  vm_size             = var.aks_node_vm_size
  aks_subnet_id       = module.network.aks_subnet_id
  apiserver_subnet_id = module.network.apiserver_subnet_id
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = var.tags
}

module "identity" {
  source = "../../modules/identity"

  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  name                     = var.workload_identity_name
  oidc_issuer_url          = module.aks.oidc_issuer_url
  key_vault_id             = module.key_vault.id
  k8s_namespace            = var.k8s_namespace
  k8s_service_account_name = var.k8s_service_account_name
  tags                     = var.tags
}

# Cross-cutting (spans acr + aks modules' resources) -- kept here at the
# environment root rather than inside either module, so neither module
# has to know about the other's resource types.
resource "azurerm_role_assignment" "kubelet_acr_pull" {
  scope                = module.acr.id
  role_definition_name = "AcrPull"
  principal_id         = module.aks.kubelet_object_id
}
