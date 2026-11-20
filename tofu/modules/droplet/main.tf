terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

# cloud-init runs this at the droplet's first boot. It lets root log in with
# the SSH key, writes the droplet's settings and vault password, installs
# Ansible, and runs ansible-pull to configure the droplet. Nothing here is
# about the droplet's apps, so adding or removing an app doesn't replace the
# droplet.
locals {
  user_data = "#cloud-config\n${yamlencode({
    # Otherwise cloud-init makes root's key print a message and disconnect
    disable_root   = false
    package_update = true
    packages       = ["ansible"]
    write_files = [
      {
        path        = "/root/.ssh/authorized_keys"
        permissions = "0600"
        content     = "${var.ssh_public_key}\n"
      },
      {
        # sshd uses the first value it reads, and reads these files in order,
        # so this comes before any setting from the image
        path        = "/etc/ssh/sshd_config.d/00-root-login.conf"
        permissions = "0644"
        content     = "PermitRootLogin prohibit-password\n"
      },
      {
        path        = "/etc/web-app/vars.json"
        permissions = "0600"
        content = jsonencode({
          droplet_name = var.name
          repo_url     = var.repo_url
          repo_branch  = var.repo_branch
        })
      },
      {
        path        = "/etc/web-app/vault-password"
        permissions = "0600"
        content     = random_password.vault_password.result
      },
    ]
    runcmd = [
      # In case sshd started before the config above was written
      ["systemctl", "try-reload-or-restart", "ssh"],
      [
        "ansible-pull",
        "--url", var.repo_url,
        "--checkout", var.repo_branch,
        "--directory", "/var/lib/web-app/repo",
        # The droplet's name is its inventory host, so this loads its host_vars
        "--inventory", "${var.name},",
        "--connection", "local",
        "--extra-vars", "@/etc/web-app/vars.json",
        "--vault-password-file", "/etc/web-app/vault-password",
        "ansible/playbook.yml",
      ],
    ]
  })}"

  # europe-west2-a is in europe-west2
  region = join("-", slice(split("-", var.zone), 0, 2))
}

# GCE updates an instance's metadata in place, and cloud-init only reads it at
# first boot, so the instance is replaced when this changes
resource "terraform_data" "user_data" {
  input = local.user_data
}

# A static address, so that the droplet keeps its IP address when it's
# stopped, or replaced
resource "google_compute_address" "this" {
  name   = var.name
  region = local.region
}

resource "google_compute_instance" "this" {
  name         = var.name
  zone         = var.zone
  machine_type = var.size
  tags         = [var.network_tag]

  # Changing the machine type needs the instance stopping
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size  = 10
    }
  }

  network_interface {
    subnetwork = var.subnetwork
    access_config {
      nat_ip = google_compute_address.this.address
    }
  }

  # Ubuntu's cloud-init reads its config from user-data
  metadata = {
    user-data = local.user_data
  }

  # No service_account block, so the instance has no service account, and the
  # metadata server has no credentials for anything on it to take

  lifecycle {
    # Changing the image would replace the droplet, so changes only apply to
    # new droplets. Volumes are attached by the app module.
    ignore_changes       = [boot_disk[0].initialize_params[0].image, attached_disk]
    replace_triggered_by = [terraform_data.user_data]
  }
}

# The password for this droplet's secrets, encrypted with ansible-vault in
# host_vars/<droplet>/vault.yml
resource "random_password" "vault_password" {
  length  = 64
  special = false
}
