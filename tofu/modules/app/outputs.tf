output "name_servers" {
  description = "The name servers of the app's zone, to delegate the zone to"
  value       = google_dns_managed_zone.this.name_servers
}
