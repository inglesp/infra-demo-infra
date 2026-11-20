locals {
  # TODO: the GCP project's ID
  project = "TODO-project-id"
  region  = "europe-west2"

  # TODO: the SSH public key that can log in as root (the contents of
  # ~/.ssh/id_ed25519.pub). Changing it replaces the droplets.
  ssh_public_key = "TODO ssh-ed25519 ..."

  # Where droplets fetch their configuration from
  repo_url    = "https://github.com/inglesp/infra-demo-infra.git"
  repo_branch = "gcp"

  # The droplets and their apps, which Ansible also reads
  droplets = yamldecode(file("${path.root}/../droplets.yml")).droplets

  # Every app, on every droplet, with its droplet's name and zone
  apps = merge([
    for droplet_name, droplet in local.droplets : {
      for app_name, app in droplet.apps : app_name => merge(app, { droplet = droplet_name, zone = droplet.zone })
    }
  ]...)
}

module "droplet" {
  source   = "./modules/droplet"
  for_each = local.droplets

  name           = each.key
  zone           = each.value.zone
  size           = each.value.size
  ssh_public_key = local.ssh_public_key
  subnetwork     = google_compute_subnetwork.web.id
  network_tag    = local.network_tag
  repo_url       = local.repo_url
  repo_branch    = local.repo_branch
}

module "app" {
  source   = "./modules/app"
  for_each = local.apps

  name        = each.key
  volume_size = each.value.volume_size
  domain      = each.value.domain
  droplet = {
    id           = module.droplet[each.value.droplet].id
    zone         = each.value.zone
    ipv4_address = module.droplet[each.value.droplet].ipv4_address
  }
}

output "ips" {
  description = "Each droplet's public IPv4 address"
  value       = { for name, droplet in module.droplet : name => droplet.ipv4_address }
}

output "name_servers" {
  description = "Each app's zone's name servers, to delegate the zone to"
  value       = { for name, app in module.app : name => app.name_servers }
}
