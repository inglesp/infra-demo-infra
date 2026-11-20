# A network of our own, rather than GCP's default one, which comes with its
# own firewall rules
resource "google_compute_network" "web" {
  name                    = "web"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "web" {
  name          = "web"
  network       = google_compute_network.web.id
  region        = local.region
  ip_cidr_range = "10.0.0.0/24"
}

locals {
  # Droplets have this tag, which the firewall rule targets
  network_tag = "web-app"
}

# Inbound traffic not allowed here is denied, and all outbound traffic is
# allowed, by GCP's implied rules
resource "google_compute_firewall" "web" {
  name          = "web-app-inbound"
  network       = google_compute_network.web.id
  direction     = "INGRESS"
  target_tags   = [local.network_tag]
  source_ranges = ["0.0.0.0/0"]

  # SSH is open to everyone; logins are key-only
  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443"]
  }

  # HTTP/3
  allow {
    protocol = "udp"
    ports    = ["443"]
  }

  # Allows ping
  allow {
    protocol = "icmp"
  }
}
