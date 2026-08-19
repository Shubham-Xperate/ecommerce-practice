variable "location" {
  type    = string
  default = "swedencentral"
}

variable "resource_group_name" {
  type    = string
  default = "rg-poc-prod"
}

variable "tags" {
  type = map(string)
  default = {
    project     = "ecommerce-practice"
    environment = "prod"
    managed_by  = "terraform"
  }
}

# Deliberately a DIFFERENT range than dev's 10.10.0.0/16 -- not required
# for correctness (they're in separate VNets in separate resource groups
# either way), but it avoids any confusion if the two ever get peered
# together later.
variable "vnet_address_space" {
  type    = list(string)
  default = ["10.20.0.0/16"]
}

variable "aks_subnet_prefix" {
  type    = list(string)
  default = ["10.20.1.0/24"]
}

variable "apiserver_subnet_prefix" {
  type    = list(string)
  default = ["10.20.2.0/24"]
}

variable "acr_name" {
  description = "Globally-unique ACR name (letters/numbers only, no hyphens) -- must differ from dev's"
  type        = string
  default     = "acrecommercepocprod"
}

variable "key_vault_name" {
  description = "Globally-unique Key Vault name -- must differ from dev's"
  type        = string
  default     = "kv-ecommercepoc-prod"
}

variable "workload_identity_name" {
  type    = string
  default = "id-ecommerce-api-prod"
}

variable "aks_cluster_name" {
  type    = string
  default = "pocprodcluster"
}

variable "aks_node_count" {
  type    = number
  default = 3
}

variable "aks_node_vm_size" {
  type    = string
  default = "Standard_D4s_v5"
}

variable "aks_sku_tier" {
  description = "Standard gives an uptime SLA, unlike Free -- worth paying for once real users depend on this"
  type        = string
  default     = "Standard"
}

variable "k8s_namespace" {
  type    = string
  default = "ecommerce"
}

variable "k8s_service_account_name" {
  type    = string
  default = "ecommerce-workload-sa"
}
