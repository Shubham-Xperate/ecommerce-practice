variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "name" {
  description = "Globally-unique ACR name (letters/numbers only, no hyphens)"
  type        = string
}

variable "sku" {
  type    = string
  default = "Basic"
}

variable "tags" {
  type    = map(string)
  default = {}
}
