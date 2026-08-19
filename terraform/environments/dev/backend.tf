# Deliberately empty. Real backend values (storage account, container,
# state file key) are NOT hardcoded here -- they get supplied at
# `terraform init` time instead:
#
#   terraform init -backend-config=backend.hcl
#
# See backend.hcl.example for the exact keys it expects. Until you create
# that file (which requires an Azure Storage Account to exist first --
# a one-time bootstrap step, often done by hand or in a tiny separate
# Terraform config of its own, since state can't describe the very
# storage account it's about to live in), running plain `terraform init`
# falls back to local state (terraform.tfstate in this folder). That's
# fine for solo use, but has no locking (two people applying at once can
# corrupt it) and isn't shared with anyone else.
terraform {
  backend "azurerm" {}
}
