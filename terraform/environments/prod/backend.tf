# Same pattern as environments/dev/backend.tf -- deliberately empty, filled
# in at init time via `terraform init -backend-config=backend.hcl`. The
# `key` in prod's backend.hcl MUST differ from dev's (e.g. "prod/ecommerce.tfstate"
# vs "dev/ecommerce.tfstate") even if both point at the same storage
# account -- that key is the only thing keeping the two environments'
# state files from overwriting each other.
terraform {
  backend "azurerm" {}
}
