terraform {
  # State encryption with a variable passphrase needs 1.8
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Credentials come from Application Default Credentials (gcloud auth
# application-default login)
provider "google" {
  project = local.project
  region  = local.region
}
