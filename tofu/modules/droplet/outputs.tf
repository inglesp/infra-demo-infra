output "id" {
  description = "The droplet's ID"
  value       = google_compute_instance.this.id
}

output "ipv4_address" {
  description = "The droplet's public IPv4 address"
  value       = google_compute_address.this.address
}

output "vault_password" {
  description = "The password for the droplet's secrets, encrypted with ansible-vault"
  value       = random_password.vault_password.result
  sensitive   = true
}
