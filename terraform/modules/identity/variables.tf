variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "name" {
  type = string
}

variable "oidc_issuer_url" {
  description = "The AKS cluster's OIDC issuer URL (module.aks.oidc_issuer_url) -- this is the trust anchor Workload Identity Federation checks tokens against"
  type        = string
}

variable "key_vault_id" {
  type = string
}

variable "k8s_namespace" {
  description = "Kubernetes namespace the app's ServiceAccount lives in (must match helm values.yaml's `namespace`)"
  type        = string
}

variable "k8s_service_account_name" {
  description = "Kubernetes ServiceAccount name used for Workload Identity federation (must match helm values.yaml's `serviceAccount.name`)"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
