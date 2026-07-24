terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
  required_version = ">= 1.0"
}

variable "api_token" {
  description = "Cloudflare API Token"
  type        = string
  sensitive   = true
}

provider "cloudflare" {
  api_token = var.api_token
}
