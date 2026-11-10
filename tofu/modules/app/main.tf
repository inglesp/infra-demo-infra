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

# An app without a domain (one only other apps on its droplet talk to) gets no
# zone
resource "digitalocean_domain" "this" {
  count = var.domain == null ? 0 : 1
  name  = var.domain
}

resource "digitalocean_record" "a" {
  count  = var.domain == null ? 0 : 1
  domain = digitalocean_domain.this[0].id
  type   = "A"
  name   = "@"
  value  = var.droplet.ipv4_address
}

resource "digitalocean_record" "aaaa" {
  count  = var.domain == null ? 0 : 1
  domain = digitalocean_domain.this[0].id
  type   = "AAAA"
  name   = "@"
  value  = var.droplet.ipv6_address
}

# From when every app had a domain
moved {
  from = digitalocean_domain.this
  to   = digitalocean_domain.this[0]
}

moved {
  from = digitalocean_record.a
  to   = digitalocean_record.a[0]
}

moved {
  from = digitalocean_record.aaaa
  to   = digitalocean_record.aaaa[0]
}
