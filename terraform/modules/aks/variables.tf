variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "name" {
  type = string
}

variable "sku_tier" {
  description = "AKS control plane tier: Free (no SLA), Standard, or Premium"
  type        = string
  default     = "Free"
}

variable "node_count" {
  type = number
}

variable "vm_size" {
  type = string
}

variable "aks_subnet_id" {
  type = string
}

variable "apiserver_subnet_id" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
