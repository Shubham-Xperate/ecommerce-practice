output "id" {
  value = azurerm_kubernetes_cluster.main.id
}

output "name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

# AKS auto-creates a separate "kubelet identity" (distinct from both the
# cluster's own control-plane identity and the workload identity) -- THIS
# is the one that actually pulls container images.
output "kubelet_object_id" {
  value = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

output "node_resource_group" {
  value = azurerm_kubernetes_cluster.main.node_resource_group
}
