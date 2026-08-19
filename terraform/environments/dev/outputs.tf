output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "aks_cluster_name" {
  value = module.aks.name
}

output "acr_login_server" {
  value = module.acr.login_server
}

output "key_vault_name" {
  value = module.key_vault.name
}

# Copy this into helm/ecommerce-chart/values.yaml's
# serviceAccount.workloadIdentityClientId after every fresh apply -- it's
# a brand new identity each time, so the client ID WILL be different from
# any value already in that file.
output "workload_identity_client_id" {
  value = module.identity.client_id
}

output "get_credentials_command" {
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${module.aks.name} --overwrite-existing"
}
