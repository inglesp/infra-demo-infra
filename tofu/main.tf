locals {
  # The name of an SSH key uploaded to DigitalOcean, which can log in as root
  ssh_key_name = "inglesp"

  # Where droplets fetch their configuration from
  repo_url    = "https://github.com/inglesp/infra-demo-infra.git"
  repo_branch = "main"

  # The droplets and their apps, which Ansible also reads
  droplets = yamldecode(file("${path.root}/../droplets.yml")).droplets

  # Every app, on every droplet, with its droplet's name and region
  apps = merge([
    for droplet_name, droplet in local.droplets : {
      for app_name, app in droplet.apps : app_name => merge(app, { droplet = droplet_name, region = droplet.region })
    }
  ]...)
}

data "digitalocean_ssh_key" "admin" {
  name = local.ssh_key_name
}

module "droplet" {
  source   = "./modules/droplet"
  for_each = local.droplets

  name        = each.key
  region      = each.value.region
  size        = each.value.size
  ssh_key_ids = [data.digitalocean_ssh_key.admin.id]
  repo_url    = local.repo_url
  repo_branch = local.repo_branch
}

module "app" {
  source   = "./modules/app"
  for_each = local.apps

  name        = each.key
  region      = each.value.region
  volume_size = each.value.volume_size
  domain      = each.value.domain
  droplet = {
    id           = module.droplet[each.value.droplet].id
    ipv4_address = module.droplet[each.value.droplet].ipv4_address
    ipv6_address = module.droplet[each.value.droplet].ipv6_address
  }
}

output "ips" {
  description = "Each droplet's public IPv4 address"
  value       = { for name, droplet in module.droplet : name => droplet.ipv4_address }
}
