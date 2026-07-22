# Servidor DNS com Bind9

---

## 1. Configurar IP fixo no servidor

### Via script (recomendado)

```bash
sudo bash ../ip-fixo.sh
```

O script faz backup automatico, configura a interface e reinicia o servico `networking`.

---

### Manualmente via /etc/network/interfaces

Caso prefira configurar manualmente, edite `/etc/network/interfaces`:

```
auto enp0s3
iface enp0s3 inet static
    address 192.168.1.10
    netmask 255.255.255.0
    gateway 192.168.1.1
    dns-nameservers 8.8.8.8 8.8.4.4
```

Reinicie o servico de rede:

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

## 2. Configurar o Bind9

### Arquivos principais

| Arquivo | Funcao |
|---|---|
| `/etc/bind/named.conf.options` | Opcoes globais (forwarders, interfaces, etc.) |
| `/etc/bind/named.conf.local` | Declaracao das zonas de dominio |
| `/etc/bind/named.conf.default-zones` | Zonas padrao (localhost, etc.) |

---

### 2.1. Forwarders e escuta

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

---

### 2.2. Criar uma zona de dominio

Edite `/etc/bind/named.conf.local` e adicione:

```
zone "meudominio.local" {
    type master;
    file "/etc/bind/db.meudominio.local";
};
```

---

### 2.3. Criar o arquivo de zona

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

---

### 2.4. Testar e aplicar

```bash
# Verificar sintaxe da configuracao
sudo named-checkconf

# Verificar sintaxe da zona
sudo named-checkzone meudominio.local /etc/bind/db.meudominio.local

# Recarregar o servico
sudo systemctl reload bind9    # ou 'named'
```

---

### 2.5. Testar resolucao

```bash
dig @127.0.0.1 www.meudominio.local
nslookup www.meudominio.local 127.0.0.1
```

---

## 3. Configurar clientes

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

## 4. Firewall

Libere a porta 53 se houver firewall ativo:

```bash
sudo ufw allow 53/udp
sudo ufw allow 53/tcp
sudo ufw reload
```

---

## 5. Comandos uteis

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

## 6. Logs

Os logs do Bind9 ficam em:

```bash
sudo journalctl -u bind9     # systemd
/var/log/syslog              # syslog
```
