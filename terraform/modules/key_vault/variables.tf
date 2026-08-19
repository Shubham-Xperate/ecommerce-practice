variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "name" {
  description = "Globally-unique Key Vault name"
  type        = string
}

variable "tenant_id" {
  type = string
}

variable "current_user_object_id" {
  description = "Object ID of whoever is running terraform apply -- granted Key Vault Administrator so they aren't locked out of their own vault"
  type        = string
}

variable "purge_protection_enabled" {
  description = "true in prod (prevents a stray destroy from ever fully purging secrets); false in dev (lets you tear down and recreate freely)"
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
