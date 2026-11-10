# Central logging. Every droplet will forward its logs with rsyslog, over
# mutual TLS, to a log server. Both ends have certs signed by the CA below:
# each droplet checks that it's talking to the log server, and the log server
# only accepts droplets.
#
# The CA and certs are made here, and `just sync-log-tls` copies each
# droplet's into its host_vars, encrypted with its vault password. There's no
# revocation list: certs expire after a year, and apply renews them in their
# last 30 days. None of this is in user_data, so it doesn't replace any
# droplets.

locals {
  # Each droplet's TLS files, which `just sync-log-tls` reads with console
  # (rather than from the output, which a targeted apply doesn't update)
  log_tls = {
    for name, _ in local.droplets : name => {
      log_tls_ca   = tls_self_signed_cert.log_ca.cert_pem
      log_tls_cert = tls_locally_signed_cert.log_client[name].cert_pem
      log_tls_key  = tls_private_key.log_client[name].private_key_pem
    }
  }
}

resource "tls_private_key" "log_ca" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "log_ca" {
  private_key_pem       = tls_private_key.log_ca.private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 24 * 365 * 5
  allowed_uses          = ["cert_signing", "crl_signing"]

  subject {
    common_name = "infra-demo logging CA"
  }
}

# One client cert per droplet, named after it
resource "tls_private_key" "log_client" {
  for_each    = local.droplets
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "log_client" {
  for_each        = local.droplets
  private_key_pem = tls_private_key.log_client[each.key].private_key_pem

  subject {
    common_name = each.key
  }
}

resource "tls_locally_signed_cert" "log_client" {
  for_each              = local.droplets
  cert_request_pem      = tls_cert_request.log_client[each.key].cert_request_pem
  ca_private_key_pem    = tls_private_key.log_ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.log_ca.cert_pem
  validity_period_hours = 24 * 365
  early_renewal_hours   = 24 * 30
  allowed_uses          = ["digital_signature", "key_encipherment", "client_auth"]
}

output "log_tls" {
  description = "Each droplet's logging TLS files"
  value       = local.log_tls
  sensitive   = true
}
