# Cloudflare Tunnel

resource "cloudflare_tunnel" "main" {
  account_id = var.account_id
  name       = var.tunnel_name
  secret     = base64sha256(var.tunnel_secret)
}

# Ingress rules (config.yml remoto)
resource "cloudflare_tunnel_config" "main" {
  account_id = var.account_id
  tunnel_id  = cloudflare_tunnel.main.id

  config {
    dynamic "ingress_rule" {
      for_each = var.services
      content {
        hostname = "${ingress_rule.value.hostname}.${var.domain}"
        service  = "${ingress_rule.value.proto}://localhost:${ingress_rule.value.port}"
      }
    }

    ingress_rule {
      service = "http_status:404"
    }
  }
}

# Registros DNS (CNAME para o tunel)
resource "cloudflare_tunnel_route" "main" {
  for_each   = var.services
  account_id = var.account_id
  tunnel_id  = cloudflare_tunnel.main.id
  network    = "${each.value.hostname}.${var.domain}"
  comment    = "Tunnel: ${var.tunnel_name}"
}

# Cloudflare Access (Zero Trust)
resource "cloudflare_access_application" "main" {
  for_each          = var.access_enabled ? var.services : {}
  account_id        = var.account_id
  name              = "${each.value.hostname}.${var.domain}"
  domain            = "${each.value.hostname}.${var.domain}"
  type              = "self_hosted"
  session_duration  = "24h"
}

resource "cloudflare_access_policy" "main" {
  for_each     = var.access_enabled ? var.services : {}
  account_id   = var.account_id
  application_id = cloudflare_access_application.main[each.key].id
  name         = "${each.value.hostname}.${var.domain} - Email"
  precedence   = 1
  decision     = "allow"

  include {
    email = var.access_emails
  }
}
