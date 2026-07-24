output "tunnel_id" {
  value = cloudflare_tunnel.main.id
}

output "tunnel_name" {
  value = cloudflare_tunnel.main.name
}

output "tunnel_cname" {
  value = "${cloudflare_tunnel.main.id}.cfargotunnel.com"
}

output "services" {
  value = {
    for k, v in var.services : k => "https://${v.hostname}.${var.domain}"
  }
}

output "access_enabled" {
  value = var.access_enabled
}
