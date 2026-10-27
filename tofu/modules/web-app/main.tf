terraform {
  required_providers {
    digitalocean = {
      source = "digitalocean/digitalocean"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

# cloud-init runs this at the droplet's first boot. It writes the droplet's
# settings and secrets, installs Ansible, and runs ansible-pull to configure
# the droplet.
locals {
  user_data = "#cloud-config\n${yamlencode({
    package_update = true
    packages       = ["ansible"]
    write_files = [
      {
        path        = "/etc/web-app/vars.json"
        permissions = "0600"
        content = jsonencode({
          app_name    = var.name
          domain      = var.domain
          volume_name = digitalocean_volume.data.name
          secret_key  = random_password.secret_key.result
          repo_url    = var.repo_url
          repo_branch = var.repo_branch
        })
      },
      {
        path        = "/etc/web-app/vault-password"
        permissions = "0600"
        content     = random_password.vault_password.result
      },
    ]
    runcmd = [
      [
        "ansible-pull",
        "--url", var.repo_url,
        "--checkout", var.repo_branch,
        "--directory", "/var/lib/web-app/repo",
        # The droplet's name is the app's name, so this loads its host_vars
        "--inventory", "${var.name},",
        "--connection", "local",
        "--extra-vars", "@/etc/web-app/vars.json",
        "--vault-password-file", "/etc/web-app/vault-password",
        # The whole playbook is tagged, so this does nothing, but removing it
        # would replace the droplet
        "--tags", "ansible_pull",
        "ansible/playbook.yml",
      ],
    ]
  })}"
}

resource "digitalocean_droplet" "this" {
  name       = var.name
  image      = "ubuntu-24-04-x64"
  region     = var.region
  size       = var.size
  ssh_keys   = var.ssh_key_ids
  ipv6       = true
  volume_ids = [digitalocean_volume.data.id]
  # Changing this replaces the droplet
  user_data = local.user_data

  lifecycle {
    # Changing either would replace the droplet, so changes only apply to
    # new droplets
    ignore_changes = [image, ssh_keys]
  }
}

resource "digitalocean_volume" "data" {
  name                     = "${var.name}-data"
  region                   = var.region
  size                     = var.volume_size
  initial_filesystem_type  = "ext4"
  initial_filesystem_label = "data"
  description              = "Persistent data for ${var.name}"

  lifecycle {
    # Holds all persistent data, so OpenTofu refuses to destroy it
    prevent_destroy = true
  }
}

locals {
  anywhere = ["0.0.0.0/0", "::/0"]
}

resource "digitalocean_firewall" "this" {
  name        = var.name
  droplet_ids = [digitalocean_droplet.this.id]

  # Open to everyone until SSH is closed; logins are key-only
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = local.anywhere
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = local.anywhere
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = local.anywhere
  }

  # HTTP/3
  inbound_rule {
    protocol         = "udp"
    port_range       = "443"
    source_addresses = local.anywhere
  }

  # Needed for IPv6 path MTU discovery, and allows ping
  inbound_rule {
    protocol         = "icmp"
    source_addresses = local.anywhere
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = local.anywhere
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = local.anywhere
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = local.anywhere
  }
}

# Django's secret key. It's kept in the (encrypted) state, so it stays the same
# across runs. Alphanumeric, so it never needs quoting.
resource "random_password" "secret_key" {
  length  = 64
  special = false
}

# The password for this app's secrets, encrypted with ansible-vault in
# host_vars/<app>/vault.yml
resource "random_password" "vault_password" {
  length  = 64
  special = false
}

resource "digitalocean_domain" "this" {
  name = var.domain
}

resource "digitalocean_record" "a" {
  domain = digitalocean_domain.this.id
  type   = "A"
  name   = "@"
  value  = digitalocean_droplet.this.ipv4_address
}

resource "digitalocean_record" "aaaa" {
  domain = digitalocean_domain.this.id
  type   = "AAAA"
  name   = "@"
  value  = digitalocean_droplet.this.ipv6_address
}
