variable "domain" {
  description = "Dominio configurado no Cloudflare"
  type        = string
}

variable "tunnel_name" {
  description = "Nome do tunel"
  type        = string
  default     = "homelab"
}

variable "tunnel_secret" {
  description = "Secret do tunel (gere com: openssl rand -base64 32)"
  type        = string
  sensitive   = true
}

variable "account_id" {
  description = "Cloudflare Account ID (encontre no dashboard)"
  type        = string
}

variable "services" {
  description = "Servicos a expor via tunel"
  type = map(object({
    hostname = string
    proto    = string
    port     = number
  }))
  default = {}
}

variable "access_enabled" {
  description = "Habilitar Cloudflare Access (Zero Trust)"
  type        = bool
  default     = true
}

variable "access_emails" {
  description = "Emails autorizados para Access Zero Trust"
  type        = list(string)
  default     = []
}
