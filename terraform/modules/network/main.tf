resource "azurerm_virtual_network" "main" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space
  tags                = var.tags
}

# Nodes only need IPs here -- with Azure CNI Overlay, pod IPs are allocated
# from a separate internal overlay CIDR that never touches this subnet, so
# this can stay small even as pod count scales up.
resource "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.aks_subnet_prefix
}

# AKS API Server VNet Integration requires its own DELEGATED subnet -- the
# delegation tells Azure "only the AKS service is allowed to provision
# resources into this subnet," which is how the API server's private
# endpoint gets placed directly inside our VNet instead of a
# Microsoft-managed one.
resource "azurerm_subnet" "apiserver" {
  name                 = "snet-aks-apiserver"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.apiserver_subnet_prefix

  delegation {
    name = "aks-apiserver-delegation"

    service_delegation {
      name    = "Microsoft.ContainerService/managedClusters"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}
