terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}

# Ansible finds the disk by this name, so the two must match. It starts blank:
# Ansible formats it.
resource "google_compute_disk" "data" {
  name        = "${var.name}-data"
  zone        = var.droplet.zone
  type        = "pd-balanced"
  size        = var.volume_size
  description = "Persistent data for ${var.name}"

  lifecycle {
    # Holds all the app's persistent data, so OpenTofu refuses to destroy it
    prevent_destroy = true
  }
}

# A separate resource, rather than the instance's attached_disk, so that adding
# an app doesn't change the droplet. The device name gives the disk its path,
# /dev/disk/by-id/google-<device_name>, on the droplet.
resource "google_compute_attached_disk" "data" {
  instance    = var.droplet.id
  disk        = google_compute_disk.data.id
  device_name = google_compute_disk.data.name
}

resource "google_dns_managed_zone" "this" {
  name     = replace(var.domain, ".", "-")
  dns_name = "${var.domain}."
}

resource "google_dns_record_set" "a" {
  managed_zone = google_dns_managed_zone.this.name
  name         = google_dns_managed_zone.this.dns_name
  type         = "A"
  ttl          = 300
  rrdatas      = [var.droplet.ipv4_address]
}
