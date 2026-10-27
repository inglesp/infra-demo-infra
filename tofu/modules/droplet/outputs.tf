output "id" {
  description = "The droplet's ID"
  value       = digitalocean_droplet.this.id
}

output "ipv4_address" {
  description = "The droplet's public IPv4 address"
  value       = digitalocean_droplet.this.ipv4_address
}

output "ipv6_address" {
  description = "The droplet's public IPv6 address"
  value       = digitalocean_droplet.this.ipv6_address
}

output "vault_password" {
  description = "The password for the droplet's secrets, encrypted with ansible-vault"
  value       = random_password.vault_password.result
  sensitive   = true
}
