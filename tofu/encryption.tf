variable "state_passphrase" {
  description = "Passphrase for encrypting OpenTofu state (at least 16 characters)"
  type        = string
  sensitive   = true
}

terraform {
  encryption {
    key_provider "pbkdf2" "main" {
      passphrase = var.state_passphrase
    }

    method "aes_gcm" "main" {
      keys = key_provider.pbkdf2.main
    }

    state {
      method = method.aes_gcm.main
    }
  }
}
