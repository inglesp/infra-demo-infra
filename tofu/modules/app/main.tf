terraform {
  required_providers {
    digitalocean = {
      source = "digitalocean/digitalocean"
    }
  }
}

# Ansible finds the volume by this name, so the two must match
resource "digitalocean_volume" "data" {
  name                     = "${var.name}-data"
  region                   = var.region
  size                     = var.volume_size
  initial_filesystem_type  = "ext4"
  initial_filesystem_label = "data"
  description              = "Persistent data for ${var.name}"

  lifecycle {
    # Holds all the app's persistent data, so OpenTofu refuses to destroy it
    prevent_destroy = true
  }
}

# A separate resource, rather than the droplet's volume_ids, so that adding an
# app doesn't change the droplet
resource "digitalocean_volume_attachment" "data" {
  droplet_id = var.droplet.id
  volume_id  = digitalocean_volume.data.id
}

resource "digitalocean_domain" "this" {
  name = var.domain
}

resource "digitalocean_record" "a" {
  domain = digitalocean_domain.this.id
  type   = "A"
  name   = "@"
  value  = var.droplet.ipv4_address
}

resource "digitalocean_record" "aaaa" {
  domain = digitalocean_domain.this.id
  type   = "AAAA"
  name   = "@"
  value  = var.droplet.ipv6_address
}
