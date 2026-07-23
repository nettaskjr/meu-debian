# Cloudflare Tunnel — Acesso externo seguro ao Homelab

---

## Como funciona

```
Internet → Cloudflare Edge → Tunnel criptografado → Servidor Homelab
          (HTTPS/WAF/CDN)   (porta 7844 outbound)   (apenas localhost)
```

Nenhuma porta é aberta no roteador. O túnel é uma conexão **outbound** do servidor para a Cloudflare.

---

## Pré-requisitos

- [x] Conta no Cloudflare
- [x] Domínio configurado no Cloudflare
- [x] Servidor Debian com acesso à internet
- [ ] API Token do Cloudflare (para Access/Zero Trust) — [criar aqui](https://dash.cloudflare.com/profile/api-tokens)
  - Permissões: `Account:Cloudflare Tunnel:Edit`, `Zone:DNS:Edit`, `Account:Access:Edit`

---

## Início rápido

```bash
sudo bash scripts/cloudflare-tunnel/cloudflare-tunnel.sh
```

O script é **totalmente interativo** e guia por todas as etapas.

---

## O script faz

| Etapa | Descrição |
|---|---|
| 1. Pré-requisitos | Verifica `curl` e conexão |
| 2. Instalação | Adiciona repositório Cloudflare e instala `cloudflared` |
| 3. Autenticação | Abre navegador para login no Cloudflare |
| 4. Criação do túnel | `cloudflared tunnel create` |
| 5. Serviços | Menu interativo para adicionar serviços expostos |
| 6. Configuração | Gera `~/.cloudflared/config.yml` |
| 7. DNS | Cria registros DNS automaticamente |
| 8. Systemd | Instala como serviço (inicia com o sistema) |
| 9. Firewall | Bloqueia portas expostas externamente |
| 10. Access | Configura autenticação Zero Trust (opcional) |
| 11. Verificação | Testa o túnel |

---

## Serviços suportados

| Protocolo | Exemplo |
|---|---|
| `ssh` | `ssh.seudominio.com` → `ssh://localhost:22` |
| `rdp` | `rdp.seudominio.com` → `rdp://localhost:3389` |
| `http` | `app.seudominio.com` → `http://localhost:8080` |
| `https` | `secure.seudominio.com` → `https://localhost:8443` |
| `tcp` | Qualquer porta TCP genérica |

---

## Cloudflare Access (Zero Trust)

Se você fornecer o API Token, o script configura autenticação obrigatória para cada subdomínio:

- **One-time PIN** — código enviado por email a cada acesso
- **Google OAuth** — login com conta Google

Sem autenticação, ninguém consegue acessar os serviços, mesmo conhecendo a URL.

---

## Reforço de segurança local

Após o script, configure cada serviço para escutar **apenas localhost**:

### SSH

Edite `/etc/ssh/sshd_config`:

```
ListenAddress 127.0.0.1
```

```bash
sudo systemctl restart sshd
```

### Aplicações web

Configure o `bind`/`host` para `127.0.0.1` em vez de `0.0.0.0`.

---

## Comandos úteis

| Comando | Descrição |
|---|---|
| `cloudflared tunnel list` | Listar todos os túneis |
| `cloudflared tunnel info <nome>` | Detalhes do túnel |
| `cloudflared tunnel route list` | Listar rotas DNS |
| `systemctl status cloudflared` | Status do serviço |
| `journalctl -u cloudflared -f` | Logs em tempo real |
| `systemctl restart cloudflared` | Reiniciar o túnel |

---

## Estrutura de arquivos

```
~/.cloudflared/
├── cert.pem          # Certificado de autenticação
├── <uuid>.json       # Credenciais do túnel
└── config.yml        # Configuração de ingress
```

---

## Troubleshooting

### O túnel está DOWN

```bash
systemctl status cloudflared
journalctl -u cloudflared -n 50
sudo systemctl restart cloudflared
```

### Erro de DNS

Verifique se o subdomínio está em **orange cloud** (proxied) no dashboard do Cloudflare.

```bash
cloudflared tunnel route list
```

### Acesso negado (Access)

Verifique as políticas em: https://one.dash.cloudflare.com/

---

## Segurança

- **Sem portas abertas** — túnel outbound pela porta 7844
- **HTTPS automático** — Cloudflare provisiona certificado SSL
- **DDoS/WAF** — proteção da Cloudflare na frente
- **Zero Trust** — autenticação antes do acesso (se Access configurado)
- **Isolamento de rede** — serviços escutam apenas `127.0.0.1`
