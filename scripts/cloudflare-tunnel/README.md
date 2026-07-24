# Cloudflare Tunnel — Acesso externo seguro ao Homelab (Terraform)

---

## Como funciona

```
Internet → Cloudflare Edge → Tunnel criptografado → Servidor Homelab
          (HTTPS/WAF/CDN)   (porta 7844 outbound)   (apenas localhost)
```

Nenhuma porta é aberta no roteador. O túnel é uma conexão **outbound** do servidor para a Cloudflare. Os recursos Cloudflare (túnel, DNS, Access) são gerenciados por **Terraform** — com estado, idempotência e `destroy` garantido.

---

## Pré-requisitos

- [x] Conta no Cloudflare
- [x] Domínio configurado no Cloudflare
- [x] Servidor Debian com acesso à internet
- [ ] API Token do Cloudflare — [criar aqui](https://dash.cloudflare.com/profile/api-tokens)
  - Permissões: `Account:Cloudflare Tunnel:Edit`, `Zone:DNS:Edit`, `Account:Access:Edit`
- [ ] Account ID — visível na URL do dashboard (`https://dash.cloudflare.com/<account-id>`)

---

## Início rápido

```bash
sudo bash scripts/cloudflare-tunnel/cloudflare-tunnel.sh
```

O script instala **Terraform** e **cloudflared**, autentica no Cloudflare, cria `terraform.tfvars` e executa `terraform apply`.

---

## Estrutura

```
scripts/cloudflare-tunnel/
├── cloudflare-tunnel.sh         # Script principal (instala + executa terraform)
├── cloudflared-client.sh        # Instala cloudflared na maquina cliente
├── terraform/
│   ├── providers.tf             # Provider Cloudflare ~> 4.0
│   ├── variables.tf             # Declaracao de variaveis
│   ├── main.tf                  # Resources: tunnel, config, routes, access
│   ├── outputs.tf               # Tunnel ID, CNAME, URLs
│   └── terraform.tfvars.example # Exemplo de configuracao
└── README.md
```

---

## Configuracao (terraform.tfvars)

```hcl
domain       = "nettask.com.br"
tunnel_name  = "homelab"
account_id   = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

services = {
  ssh = {
    hostname = "ssh"
    proto    = "ssh"
    port     = 22
  }
  app = {
    hostname = "app"
    proto    = "http"
    port     = 8080
  }
}

access_enabled = true
access_emails  = ["seu@email.com"]
```

---

## Servicos suportados

| Protocolo | Acesso do cliente |
|---|---|
| `http`/`https` | Navegador (direto) |
| `ssh` | Requer `cloudflared` no cliente |
| `rdp` | Requer `cloudflared` no cliente |
| `tcp` | Requer `cloudflared` no cliente |

---

## Comandos Terraform

```bash
cd scripts/cloudflare-tunnel/terraform

# Ver mudancas
terraform plan

# Aplicar
terraform apply

# Excluir tudo (tunel, DNS, Access)
terraform destroy

# Ver outputs
terraform output
```

---

## Comandos cloudflared

| Comando | Descricao |
|---|---|
| `systemctl status cloudflared` | Status do servico |
| `journalctl -u cloudflared -f` | Logs em tempo real |
| `systemctl restart cloudflared` | Reiniciar o tunel |

---

## Cliente — como acessar

### HTTP/HTTPS

```
https://app.seudominio.com    (direto no navegador)
```

### SSH

Instale o `cloudflared` no cliente:

```bash
sudo bash scripts/cloudflare-tunnel/cloudflared-client.sh
```

Acesse:

```bash
cloudflared access ssh --hostname ssh.seudominio.com
```

Ou via `~/.ssh/config`:

```
Host ssh.seudominio.com
    ProxyCommand cloudflared access ssh --hostname %h
```

### RDP

```bash
cloudflared access rdp --hostname rdp.seudominio.com --url localhost:3389
# Conecte o cliente RDP em: localhost:3389
```

---

## Seguranca

- **Sem portas abertas** — tunel outbound pela porta 7844
- **HTTPS automatico** — Cloudflare provisiona certificado SSL
- **DDoS/WAF** — protecao da Cloudflare na frente
- **Zero Trust** — autenticacao antes do acesso (se Access configurado)
- **Isolamento de rede** — servicos escutam apenas `127.0.0.1`
- **NAO use `ufw deny`** nas portas dos servicos — bloqueia o proprio `cloudflared`

---

## Troubleshooting

| Sintoma | Solucao |
|---|---|
| Tunnel DOWN | `systemctl restart cloudflared` |
| `bad handshake` | Verifique se o DNS esta proxied (laranja) no Cloudflare |
| `terraform apply` falha | Verifique `TF_VAR_api_token` e permissoes do token |
| SSH nao conecta | Servico deve escutar em `127.0.0.1:22`, nao `0.0.0.0` |
| Acesso negado (403) | Verifique `access_emails` no `terraform.tfvars` |
