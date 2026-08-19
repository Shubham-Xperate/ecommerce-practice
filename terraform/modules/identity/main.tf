# The identity pods actually use at runtime, via Workload Identity Federation
# -- no secrets, no stored credentials, just OIDC token exchange.
resource "azurerm_user_assigned_identity" "main" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# This is the actual trust relationship: "if a token comes from THIS AKS
# cluster's OIDC issuer, claiming to be THIS specific Kubernetes
# ServiceAccount, trust it as being this managed identity." No secret ever
# gets stored anywhere -- Azure AD verifies the token's signature against
# the cluster's own OIDC issuer.
resource "azurerm_federated_identity_credential" "main" {
  name      = "${var.name}-federated-credential"
  audience  = ["api://AzureADTokenExchange"]
  issuer    = var.oidc_issuer_url
  parent_id = azurerm_user_assigned_identity.main.id
  subject   = "system:serviceaccount:${var.k8s_namespace}:${var.k8s_service_account_name}"
}

# Lets the workload identity actually read secrets via the Secrets Store
# CSI Driver's SecretProviderClass -- without this, the federated trust
# above proves WHO the pod is, but Azure would still say "and you're not
# allowed to read anything here."
resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}
