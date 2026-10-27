variable "name" {
  description = "The app's name, used as the droplet's name"
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

variable "volume_size" {
  description = "Size of the data volume in GiB"
  type        = number
}

variable "domain" {
  description = "The DNS zone for the app, delegated to DigitalOcean; records go at its apex"
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
