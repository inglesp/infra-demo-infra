variable "name" {
  description = "The droplet's name, which is also its Ansible inventory host"
  type        = string
}

variable "zone" {
  description = "The GCE zone, e.g. europe-west2-a"
  type        = string
}

variable "size" {
  description = "The GCE machine type, e.g. e2-small"
  type        = string
}

variable "ssh_public_key" {
  description = "The SSH public key that can log in as root"
  type        = string
}

variable "subnetwork" {
  description = "The ID of the subnetwork the droplet is on"
  type        = string
}

variable "network_tag" {
  description = "The network tag that the firewall rules target"
  type        = string
}

variable "repo_url" {
  description = "The git repo the droplet fetches its configuration from"
  type        = string
}

variable "repo_branch" {
  description = "The branch of repo_url the droplet fetches its configuration from"
  type        = string
}
