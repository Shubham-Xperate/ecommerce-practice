variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "vnet_name" {
  type = string
}

variable "address_space" {
  description = "Address space for the VNet"
  type        = list(string)
}

variable "aks_subnet_prefix" {
  description = "Subnet CIDR for AKS nodes (pod IPs come from a separate overlay CIDR, not this one, since we use Azure CNI Overlay)"
  type        = list(string)
}

variable "apiserver_subnet_prefix" {
  description = "Delegated subnet CIDR for AKS API Server VNet Integration"
  type        = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}
