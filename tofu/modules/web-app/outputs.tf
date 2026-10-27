output "ipv4_address" {
  description = "The droplet's public IPv4 address"
  value       = digitalocean_droplet.this.ipv4_address
}

output "vault_password" {
  description = "The password for the app's secrets, encrypted with ansible-vault"
  value       = random_password.vault_password.result
  sensitive   = true
}
