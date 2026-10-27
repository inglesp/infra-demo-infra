variable "name" {
  description = "The app's name, unique across all droplets"
  type        = string
}

variable "region" {
  description = "The DigitalOcean region, which must be the droplet's"
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

variable "droplet" {
  description = "The droplet the app runs on"
  type = object({
    id           = string
    ipv4_address = string
    ipv6_address = string
  })
}
