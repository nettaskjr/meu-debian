# Servidor DNS com Bind9

---

## Inicio rapido

Execute os scripts na ordem abaixo:

```bash
# 1. Configurar IP fixo no servidor (ex: 192.168.1.10)
sudo bash ../ip-fixo.sh

# 2. Instalar o Bind9
sudo bash dns.sh

# 3. Configurar o dominio DNS
sudo bash dns-setup.sh
```

O script `dns-setup.sh` e interativo e faz backup automatico de todas as configuracoes.

---

## 1. Configurar IP fixo no servidor

### Via script (recomendado)

```bash
sudo bash ../ip-fixo.sh
```

O script detecta automaticamente se o sistema usa **NetworkManager** (padrao Debian 13) ou `/etc/network/interfaces` (Debian antigo) e configura o IP fixo de acordo.

---

### Manualmente via NetworkManager (nmcli)

```bash
# Listar conexoes
nmcli connection show

# Configurar IP fixo (ex: "Wired connection 1")
nmcli connection modify "Wired connection 1" \
    ipv4.method manual \
    ipv4.addresses "192.168.1.10/24" \
    ipv4.gateway "192.168.1.1" \
    ipv4.dns "8.8.8.8,8.8.4.4" \
    ipv4.ignore-auto-dns yes

# Aplicar
nmcli connection down "Wired connection 1"
nmcli connection up "Wired connection 1"
```

---

### Manualmente via /etc/network/interfaces

```
auto enp0s3
iface enp0s3 inet static
    address 192.168.1.10
    netmask 255.255.255.0
    gateway 192.168.1.1
    dns-nameservers 8.8.8.8 8.8.4.4
```

```bash
sudo systemctl restart networking
```

---

### Via Netplan (alternativa -- requer instalacao manual)

```bash
sudo apt install -y netplan.io
```

Edite `/etc/netplan/00-installer-config.yaml`:

```yaml
network:
  version: 2
  ethernets:
    enp0s3:
      dhcp4: false
      addresses:
        - 192.168.1.10/24
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
```

```bash
sudo netplan apply
```

---

### Testar

```bash
ip a | grep enp0s3
ping -c 3 8.8.8.8
```

---

## 2. Instalar o Bind9

```bash
sudo bash dns.sh
```

O script instala `bind9`, `bind9utils` e `bind9-doc`, detecta o nome correto do servico (`bind9` ou `named`) e habilita a inicializacao automatica.

---

## 3. Configurar o dominio DNS

### Via script (recomendado)

```bash
sudo bash dns-setup.sh
```

O script faz:

- **Backup** dos arquivos em `/etc/bind/backup-YYYYMMDD-HHMMSS/`
- **Configura** `named.conf.options` com forwarders (`8.8.8.8`), `listen-on { any; }` e `allow-query { any; }`
- **Adiciona** a zona ao `named.conf.local`
- **Cria** o arquivo de zona com registros `@`, `ns` e `www`
- **Valida** com `named-checkconf` e `named-checkzone`
- **Recarrega** o servico e **testa** com `dig`

---

### Manualmente (passo a passo)

#### Arquivos principais

| Arquivo | Funcao |
|---|---|
| `/etc/bind/named.conf.options` | Opcoes globais (forwarders, interfaces, etc.) |
| `/etc/bind/named.conf.local` | Declaracao das zonas de dominio |
| `/etc/bind/named.conf.default-zones` | Zonas padrao (localhost, etc.) |

#### Forwarders e escuta

Edite `/etc/bind/named.conf.options`:

```
options {
    directory "/var/cache/bind";

    forwarders {
        8.8.8.8;
        8.8.4.4;
    };

    listen-on { any; };
    listen-on-v6 { any; };

    allow-query { any; };
};
```

#### Criar uma zona de dominio

Edite `/etc/bind/named.conf.local` e adicione:

```
zone "meudominio.local" {
    type master;
    file "/etc/bind/db.meudominio.local";
};
```

#### Criar o arquivo de zona

Crie `/etc/bind/db.meudominio.local`:

```
$TTL    604800
@       IN      SOA     ns.meudominio.local. admin.meudominio.local. (
                        2024072101   ; Serial (AAAAMMDDNN)
                        604800       ; Refresh
                        86400        ; Retry
                        2419200      ; Expire
                        604800       ; Negative Cache TTL
)

@       IN      NS      ns.meudominio.local.
@       IN      A       192.168.1.10
ns      IN      A       192.168.1.10
www     IN      A       192.168.1.10
```

#### Testar e aplicar

```bash
sudo named-checkconf
sudo named-checkzone meudominio.local /etc/bind/db.meudominio.local
sudo systemctl reload bind9    # ou 'named'

dig @127.0.0.1 www.meudominio.local
nslookup www.meudominio.local 127.0.0.1
```

---

## 4. Configurar clientes

Nos clientes da rede, aponte o DNS para o IP do servidor (`192.168.1.10`).

### Via /etc/resolv.conf (temporario)

```
nameserver 192.168.1.10
```

### Via NetworkManager (permanente)

```bash
# Listar conexoes
nmcli connection show

# Definir DNS na conexao ativa (ex: "Wired connection 1")
nmcli connection modify "Wired connection 1" ipv4.dns "192.168.1.10"
nmcli connection modify "Wired connection 1" ipv4.ignore-auto-dns yes
nmcli connection down "Wired connection 1"
nmcli connection up "Wired connection 1"
```

---

## 5. Firewall

Libere a porta 53 se houver firewall ativo:

```bash
sudo ufw allow 53/udp
sudo ufw allow 53/tcp
sudo ufw reload
```

---

## 6. Comandos uteis

| Comando | Descricao |
|---|---|
| `sudo systemctl status bind9` | Status do servico (ou `named`) |
| `sudo systemctl restart bind9` | Reiniciar |
| `sudo systemctl reload bind9` | Recarregar configuracao |
| `sudo named-checkconf` | Validar sintaxe dos arquivos de configuracao |
| `sudo named-checkzone meudominio.local /etc/bind/db.meudominio.local` | Validar sintaxe de uma zona |
| `sudo journalctl -u bind9 -f` | Logs em tempo real |
| `dig @127.0.0.1 dominio.local` | Testar resolucao local |
| `nslookup dominio.local` | Testar resolucao |

---

## 7. Logs

Os logs do Bind9 ficam em:

```bash
sudo journalctl -u bind9     # systemd
/var/log/syslog              # syslog
```

---

## 8. Restaurar backup

Em caso de erro, os backups ficam em:

```bash
ls /etc/bind/backup-*/
sudo cp /etc/bind/backup-*/* /etc/bind/
sudo systemctl restart bind9
```
