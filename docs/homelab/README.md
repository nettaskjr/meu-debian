# Homelab — Guia de instalação completo (Debian)

---

## Arquitetura

```
                         ┌───────────────────────────────┐
  Internet               │         Homelab (Debian)      │
                         │                               │
  🌐 Navegador ──────────┤  🔒 Cloudflare Tunnel        │
     (HTTPS direto)      │     ↓ localhost               │
                         │  ┌─────────────────────────┐  │
  💻 SSH/RDP ────────────┤  │ Serviços                │  │
     (cloudflared)       │  │  :22  SSH               │  │
                         │  │  :53  DNS (Bind9)       │  │
                         │  │  :443 Apps (Docker)     │  │
                         │  │  :3389 RDP (xRDP)       │  │
                         │  └─────────────────────────┘  │
                         │                               │
                         │  🌐 Rede local: 192.168.x.x   │
                         └───────────────────────────────┘
```

---

## Pré-requisitos

- [X] Servidor Debian 12+ (Bookworm ou Trixie) instalado
- [X] Acesso root ou usuário com `sudo`
- [X] Conexão com a internet
- [X] Domínio configurado no Cloudflare (para túnel)
- [ ] apt install git ufw
- [ ] API Token do Cloudflare (para Access/Zero Trust) — [criar aqui](https://dash.cloudflare.com/profile/api-tokens)
  - Permissões: `Account:Cloudflare Tunnel:Edit`, `Zone:DNS:Edit`

---

## Sumário

| Passo                    | Script                                     | Tempo estimado |
| ------------------------ | ------------------------------------------ | -------------- |
| 1. Criar usuário sudo   | `sudouser.sh`                            | 2 min          |
| 2. Configurar IP fixo    | `ip-fixo.sh`                             | 5 min          |
| 3. Instalar SSH          | `ssh.sh`                                 | 3 min          |
| 4. Instalar Docker       | `docker.sh`                              | 5 min          |
| 5. Servidor DNS (Bind9)  | `dns/dns.sh` + `dns/dns-setup.sh`      | 5 min          |
| 6. Cloudflare Tunnel     | `cloudflare-tunnel/cloudflare-tunnel.sh` | 10 min         |
| 7. Remote Desktop (xRDP) | `xrdp.sh`                                | 5 min          |
| 8. Hardening             | Manual                                     | 10 min         |

---

## Passo a passo

---

### 1. Criar usuário sudo

Cria um usuário com privilégios `sudo` para administração.

```bash
sudo bash scripts/sudouser.sh
```

**O script pergunta:**

- Escolha `1` (usuário específico) ou `2` (todos os usuários)
- Se escolher `1`, digite o nome do usuário

**Verificação:**

```bash
groups <usuario>
# Deve incluir: sudo
```

---

### 2. Configurar IP fixo

Define um IP estático no servidor para que serviços como DNS tenham endereço fixo.

```bash
sudo bash scripts/ip-fixo.sh
```

**O script pergunta:**

- Interface de rede (ex: `enp0s3`)
- IP estático (ex: `192.168.1.10`)
- Prefixo CIDR (ex: `24` para máscara /24)
- Gateway (ex: `192.168.1.1`)
- DNS primário (ex: `8.8.8.8`)
- DNS secundário (ex: `8.8.4.4` — opcional)
- Hostname (Enter mantém o atual)

**O script faz:**

- Detecta se usa NetworkManager (padrão Debian 13) ou `/etc/network/interfaces`
- Configura via `nmcli` ou via interfaces, conforme o caso
- Define o hostname com `hostnamectl`
- Atualiza `/etc/hosts` com o IP estático
- Faz backup automático em caso de falha

**Verificação:**

```bash
ip a | grep <interface>
ping -c 3 8.8.8.8
hostname
cat /etc/hosts | grep <ip>
```

---

### 3. Instalar SSH

Instala o servidor OpenSSH para acesso remoto.

```bash
sudo bash scripts/ssh.sh
```

**O script faz:**

- `apt update && apt upgrade`
- Instala `openssh-server`
- Habilita e inicia o serviço

**Verificação:**

```bash
sudo systemctl status ssh
```

---

### 4. Instalar Docker

Instala Docker Engine e Docker Compose para rodar aplicações em containers.

```bash
sudo bash scripts/docker.sh
```

**O script faz:**

- Remove versões antigas do Docker
- Instala dependências (`ca-certificates`, `curl`, `gnupg`, `lsb-release`)
- Adiciona repositório oficial Docker
- Instala Docker Engine, CLI, Containerd e Docker Compose Plugin
- Habilita Docker na inicialização
- Adiciona usuário atual ao grupo `docker`

**Verificação:**

```bash
docker --version
docker compose version
docker run hello-world
```

**Pós-instalação:** saia e entre novamente no terminal (ou `newgrp docker`) para ativar o grupo docker.

---

### 5. Servidor DNS (Bind9)

Instala e configura um servidor DNS local para resolver nomes da rede interna.

#### 5.1 Instalar o Bind9

```bash
sudo bash scripts/dns/dns.sh
```

**O script faz:**

- Instala `bind9`, `bind9utils`, `bind9-doc`
- Detecta nome do serviço (`bind9` ou `named`)
- Habilita e inicia o serviço

#### 5.2 Configurar o domínio

```bash
sudo bash scripts/dns/dns-setup.sh
```

**O script faz:**

- Backup automático em `/etc/bind/backup-YYYYMMDD-HHMMSS/`
- Configura forwarders (`8.8.8.8`, `8.8.4.4`), `listen-on { any; }`, `allow-query { any; }`
- Adiciona zona ao `named.conf.local`
- Cria arquivo de zona com registros `@`, `ns` e `www`
- Valida com `named-checkconf` e `named-checkzone`
- Recarrega o serviço e testa com `dig`

**O script pergunta:**

- Nome do domínio (ex: `casa.local`)
- IP do servidor DNS (ex: `192.168.1.10`)

**Verificação:**

```bash
dig @127.0.0.1 www.casa.local
nslookup www.casa.local 127.0.0.1
```

---

### 6. Cloudflare Tunnel (acesso externo via Terraform)

Cria um túnel criptografado outbound para a Cloudflare, permitindo acesso externo sem abrir portas no roteador. Os recursos Cloudflare (túnel, DNS, Access) são gerenciados por **Terraform** — com estado, idempotência e `destroy` garantido.

```bash
sudo bash scripts/cloudflare-tunnel/cloudflare-tunnel.sh
```

**O script faz:**
1. Instala **Terraform** (se não estiver instalado)
2. Instala o **cloudflared** (com fallback `bookworm` se Debian 13)
3. Autentica no Cloudflare (abre navegador)
4. Cria `terraform.tfvars` interativamente
5. Executa `terraform init` → `terraform plan` → `terraform apply`
6. Configura `cloudflared` local
7. Instala como serviço systemd

**O script pergunta:**
- API Token Cloudflare
- Account ID (URL do dashboard)
- Domínio
- Nome do túnel

**Após o script, edite `terraform.tfvars` para configurar os serviços:**

```bash
sudo nano scripts/cloudflare-tunnel/terraform/terraform.tfvars
```

```hcl
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

Depois execute novamente para aplicar:

```bash
sudo bash scripts/cloudflare-tunnel/cloudflare-tunnel.sh
```

#### Comandos Terraform

```bash
cd scripts/cloudflare-tunnel/terraform
terraform plan              # Ver mudanças
terraform apply             # Aplicar
terraform destroy           # Excluir tudo (túnel, DNS, Access)
terraform output            # Ver URLs e IDs
```

#### Configurar clientes

##### HTTP/HTTPS — acesso direto pelo navegador:

```
https://app.seuhomelab.com.br
```

##### SSH — instalar `cloudflared` na máquina cliente:

```bash
# Instalação automatizada
sudo bash scripts/cloudflare-tunnel/cloudflared-client.sh

# Acesso:
cloudflared access ssh --hostname ssh.seuhomelab.com.br

# Ou via ~/.ssh/config:
Host ssh.seuhomelab.com.br
    ProxyCommand cloudflared access ssh --hostname %h
```

##### RDP — instalar `cloudflared` na máquina cliente:

```bash
cloudflared access rdp --hostname rdp.seuhomelab.com.br --url localhost:3389
# Conecte o cliente RDP em: localhost:3389
```

**Verificação:**

```bash
sudo journalctl -u cloudflared -n 20
terraform -chdir=scripts/cloudflare-tunnel/terraform output
```

---

### 7. Remote Desktop (xRDP)

Acesso remoto via RDP ao ambiente gráfico do servidor (útil para administração visual).

```bash
sudo bash scripts/xrdp.sh
```

**O script pergunta:**

- Qual ambiente desktop: `1` (GNOME) ou `2` (XFCE — recomendado para servidor)

**O script faz:**

- Instala o ambiente escolhido (se GNOME não estiver presente)
- Instala e configura o `xrdp`
- Configura o `startwm.sh` para a sessão correta
- Libera porta `3389` no firewall
- Habilita e inicia o serviço

**Verificação:**

```bash
sudo systemctl status xrdp
```

**Acesso:**

- Via túnel Cloudflare: `cloudflared access rdp --hostname rdp.seuhomelab.com.br --url localhost:3389`
- Via rede local (se porta aberta): cliente RDP em `<ip-do-servidor>:3389`

---

### 8. Hardening (segurança)

Após todos os serviços instalados, reforce a segurança.

#### 8.1 Serviços devem escutar apenas localhost (se acessados via túnel)

```bash
# Verificar quais serviços escutam em todas as interfaces
ss -tlnp

# SSH: editar /etc/ssh/sshd_config
ListenAddress 127.0.0.1
```

```bash
sudo systemctl restart sshd
```

#### 8.2 NÃO usar `ufw deny` nas portas dos serviços

O `ufw deny` bloqueia também o `cloudflared`, que precisa acessar os serviços via `localhost`. O bind em `127.0.0.1` já é suficiente.

#### 8.3 Manter o sistema atualizado

```bash
sudo apt update && sudo apt upgrade -y
```

#### 8.4 Monitorar logs

```bash
# Cloudflared
sudo journalctl -u cloudflared -f

# SSH
sudo journalctl -u ssh -f

# DNS
sudo journalctl -u bind9 -f
```

---

## Estrutura de diretórios

```
scripts/
├── sudouser.sh                  # Criar usuário sudo
├── ip-fixo.sh                   # Configurar IP estático
├── ssh.sh                       # Instalar OpenSSH
├── docker.sh                    # Instalar Docker + Compose
├── xrdp.sh                      # Instalar xRDP (Remote Desktop)
├── dns/
│   ├── dns.sh                   # Instalar Bind9
│   ├── dns-setup.sh             # Configurar domínio DNS
│   └── README.md                # Guia detalhado do DNS
└── cloudflare-tunnel/
    ├── cloudflare-tunnel.sh            # Instalar + executar Terraform
    ├── cloudflared-client.sh           # Instalar cloudflared no cliente
    ├── terraform/
    │   ├── providers.tf               # Provider Cloudflare
    │   ├── variables.tf               # Variáveis
    │   ├── main.tf                    # Resources (túnel, DNS, Access)
    │   ├── outputs.tf                 # URLs e IDs
    │   └── terraform.tfvars.example   # Exemplo de config
    └── README.md                       # Guia detalhado do Túnel (Terraform)
```

---

## Troubleshooting rápido

| Sintoma                          | Causa provável                   | Solução                                                        |
| -------------------------------- | --------------------------------- | ---------------------------------------------------------------- |
| Tunnel DOWN                      | `ufw deny` nas portas ou serviço parado | `sudo journalctl -u cloudflared -n 20`                     |
| SSH via túnel:`bad handshake` | DNS não proxied ou serviço errado | `terraform -chdir=scripts/cloudflare-tunnel/terraform apply` |
| `terraform apply` falha        | Token ou permissões erradas        | Verifique `TF_VAR_api_token` e Account ID                      |
| `cloudflared access ssh` falha | Serviço escuta em`0.0.0.0`     | Configurar`ListenAddress 127.0.0.1` no sshd                    |
| DNS não resolve                 | Serviço`bind9` off             | `sudo systemctl restart bind9`                                 |
| Docker: permission denied        | Usuário não no grupo docker     | `sudo usermod -aG docker $USER` + re-login                     |
| IP fixo não aplica              | NetworkManager conflitando        | Executar`ip-fixo.sh` novamente (detecta NM)                    |
| Acesso negado (403)              | Cloudflare Access bloqueando       | Verifique `access_emails` no `terraform.tfvars`                |

---

## Ordem completa (checklist)

```
[ ] 1. Criar usuário sudo
[ ] 2. Configurar IP fixo
[ ] 3. Instalar e configurar SSH
[ ] 4. Instalar Docker
[ ] 5. Instalar e configurar DNS (Bind9)
[ ] 6. Criar túnel Cloudflare
[ ] 7. Instalar xRDP (opcional)
[ ] 8. Hardening — bind serviços em 127.0.0.1
[ ] 9. Configurar clientes (cloudflared + SSH config)
[ ] 10. Testar todos os acessos
```
