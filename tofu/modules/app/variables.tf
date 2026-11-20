variable "name" {
  description = "The app's name, unique across all droplets"
  type        = string
}

variable "volume_size" {
  description = "Size of the data disk in GB, at least 10"
  type        = number
}

variable "domain" {
  description = "The DNS zone for the app, delegated to Cloud DNS; records go at its apex"
  type        = string
}

variable "droplet" {
  description = "The droplet the app runs on"
  type = object({
    id           = string
    zone         = string
    ipv4_address = string
  })
}
