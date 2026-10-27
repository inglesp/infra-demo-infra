locals {
  # The name of an SSH key uploaded to DigitalOcean, which can log in as root
  ssh_key_name = "inglesp"

  # Where droplets fetch their configuration from
  repo_url    = "https://github.com/inglesp/infra-demo-infra.git"
  repo_branch = "main"

  # One droplet per app
  apps = {}
}

data "digitalocean_ssh_key" "admin" {
  name = local.ssh_key_name
}

module "web_app" {
  source   = "./modules/web-app"
  for_each = local.apps

  name        = each.key
  region      = each.value.region
  size        = each.value.size
  volume_size = each.value.volume_size
  domain      = each.value.domain
  ssh_key_ids = [data.digitalocean_ssh_key.admin.id]
  repo_url    = local.repo_url
  repo_branch = local.repo_branch
}

output "ips" {
  description = "Each app's droplet's public IPv4 address"
  value       = { for name, app in module.web_app : name => app.ipv4_address }
}

output "vault_passwords" {
  description = "Each app's password for its secrets, encrypted with ansible-vault"
  value       = { for name, app in module.web_app : name => app.vault_password }
  sensitive   = true
}
