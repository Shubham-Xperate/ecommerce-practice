resource "azurerm_kubernetes_cluster" "main" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.name
  sku_tier            = var.sku_tier

  default_node_pool {
    name           = "default"
    node_count     = var.node_count
    vm_size        = var.vm_size
    vnet_subnet_id = var.aks_subnet_id
  }

  # The CONTROL PLANE's own identity (used for things like managing the
  # node resource group, attaching disks, etc) -- distinct from the
  # user-assigned workload identity, which is what your PODS use. Two
  # separate identities, two separate purposes.
  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay" # pod IPs from an internal overlay CIDR, not the VNet subnet
    network_policy      = "cilium"
    network_data_plane  = "cilium" # Cilium as the actual dataplane, not just the policy engine
    load_balancer_sku   = "standard"
  }

  # Enables the cluster's own OIDC issuer endpoint (required for Workload
  # Identity Federation to have something to trust) and the feature that
  # lets pods actually exchange tokens against it.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Azure RBAC for Kubernetes Authorization: `kubectl` actions are
  # authorized through Azure AD role assignments (e.g. "Azure Kubernetes
  # Service RBAC Reader") instead of only Kubernetes-native RBAC objects.
  azure_active_directory_role_based_access_control {
    tenant_id          = var.tenant_id
    azure_rbac_enabled = true
  }

  # AKS's managed ingress controller addon -- no separate ingress-nginx
  # Helm install needed, matches className: webapprouting.kubernetes.azure.com
  # already used in helm/ecommerce-chart/values.yaml.
  web_app_routing {
    dns_zone_ids = []
  }

  # Installs the Azure Policy / Gatekeeper addon pods. NOTE: this alone
  # does not create the actual "deployment safeguards" Gatekeeper policies
  # (topologySpreadConstraints/antiAffinity requirements,
  # uniqueServiceSelectors, etc) this project's Helm chart was built
  # around -- those come from AKS's separate "Deployment Safeguards"
  # feature, which as of this writing isn't yet a stable top-level
  # argument on this resource. If `terraform plan` doesn't show it,
  # enable it after apply with:
  #   az aks update --resource-group <rg> --name <cluster> --safeguards-level Warning
  azure_policy_enabled = true

  api_server_access_profile {
    subnet_id                           = var.apiserver_subnet_id
    virtual_network_integration_enabled = true
  }

  tags = var.tags
}
