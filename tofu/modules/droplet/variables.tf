variable "name" {
  description = "The droplet's name, which is also its Ansible inventory host"
  type        = string
}

variable "region" {
  description = "The DigitalOcean region, e.g. lon1"
  type        = string
}

variable "size" {
  description = "The droplet size, e.g. s-1vcpu-1gb"
  type        = string
}

variable "ssh_key_ids" {
  description = "IDs of the DigitalOcean SSH keys that can log in as root"
  type        = list(string)
}

variable "repo_url" {
  description = "The git repo the droplet fetches its configuration from"
  type        = string
}

variable "repo_branch" {
  description = "The branch of repo_url the droplet fetches its configuration from"
  type        = string
}
