variable "location" {
  type    = string
  default = "swedencentral"
}

variable "resource_group_name" {
  type    = string
  default = "rg-poc-dev"
}

variable "tags" {
  type = map(string)
  default = {
    project     = "ecommerce-practice"
    environment = "dev"
    managed_by  = "terraform"
  }
}

variable "vnet_address_space" {
  type    = list(string)
  default = ["10.10.0.0/16"]
}

variable "aks_subnet_prefix" {
  type    = list(string)
  default = ["10.10.1.0/24"]
}

variable "apiserver_subnet_prefix" {
  type    = list(string)
  default = ["10.10.2.0/24"]
}

variable "acr_name" {
  description = "Globally-unique ACR name (letters/numbers only, no hyphens)"
  type        = string
  default     = "acrecommercepocdev"
}

variable "key_vault_name" {
  description = "Globally-unique Key Vault name"
  type        = string
  default     = "kv-ecommercepoc-dev"
}

variable "workload_identity_name" {
  type    = string
  default = "id-ecommerce-api-dev"
}

variable "aks_cluster_name" {
  type    = string
  default = "pocdevcluster"
}

variable "aks_node_count" {
  type    = number
  default = 2
}

variable "aks_node_vm_size" {
  type    = string
  default = "Standard_D2s_v5"
}

variable "aks_sku_tier" {
  type    = string
  default = "Free"
}

variable "k8s_namespace" {
  description = "Must match helm values.yaml's `namespace`"
  type        = string
  default     = "ecommerce"
}

variable "k8s_service_account_name" {
  description = "Must match helm values.yaml's `serviceAccount.name`"
  type        = string
  default     = "ecommerce-workload-sa"
}
