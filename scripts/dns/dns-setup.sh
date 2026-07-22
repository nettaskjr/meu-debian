#!/bin/bash
set -e

appNome="Configurador Bind9"

echo "=============================================="
echo "  🔧 $appNome"
echo "=============================================="
echo

if [ "$EUID" -ne 0 ]; then
    echo "❌ Execute como root: sudo bash $0"
    exit 1
fi

# --- Detectar servico ---
SERVICO="bind9"
if systemctl list-unit-files 2>/dev/null | grep -q "^named.service"; then
    SERVICO="named"
fi

# --- Verificar instalacao ---
if ! dpkg -l bind9 &>/dev/null; then
    echo "❌ Bind9 nao esta instalado."
    echo "   Execute primeiro: sudo bash dns.sh"
    exit 1
fi
echo "✅ Bind9 encontrado (servico: $SERVICO)"

# --- Coletar dados ---
echo
read -r -p "Nome do dominio (ex: meudominio.local): " DOMINIO
if [ -z "$DOMINIO" ]; then
    echo "❌ Dominio nao informado."
    exit 1
fi

read -r -p "IP do servidor DNS (ex: 192.168.1.10): " IP_SERVIDOR
if [ -z "$IP_SERVIDOR" ]; then
    echo "❌ IP nao informado."
    exit 1
fi

echo
echo "=============================================="
echo "  📋 Resumo da configuracao:"
echo "  Dominio   : $DOMINIO"
echo "  IP        : $IP_SERVIDOR"
echo "  Servico   : $SERVICO"
echo "=============================================="
echo
read -r -p "Aplicar esta configuracao? [s/N]: " CONFIRM

if [ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ]; then
    echo "Cancelado."
    exit 0
fi

# --- Backup ---
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/etc/bind/backup-$TIMESTAMP"
mkdir -p "$BACKUP_DIR"

echo
echo "=== ➡️ Criando backup em $BACKUP_DIR ==="
for f in named.conf named.conf.options named.conf.local named.conf.default-zones; do
    [ -f "/etc/bind/$f" ] && cp "/etc/bind/$f" "$BACKUP_DIR/"
done
echo "✅ Backup concluido."

# --- Configurar named.conf.options ---
OPTIONS_FILE="/etc/bind/named.conf.options"

echo
echo "=== ➡️ Configurando $OPTIONS_FILE ==="

# forwarders
if grep -q "forwarders" "$OPTIONS_FILE"; then
    echo "   forwarders: ja configurado"
else
    sed -i '/^options {/a\
\tforwarders {\
\t\t8.8.8.8;\
\t\t8.8.4.4;\
\t};' "$OPTIONS_FILE"
    echo "   forwarders: adicionado (8.8.8.8, 8.8.4.4)"
fi

# listen-on any
if grep -q "listen-on" "$OPTIONS_FILE"; then
    sed -i 's/listen-on\s*{[^}]*}/listen-on { any; }/g' "$OPTIONS_FILE"
    sed -i 's/listen-on-v6\s*{[^}]*}/listen-on-v6 { any; }/g' "$OPTIONS_FILE"
else
    sed -i '/^options {/a\
\tlisten-on { any; };\
\tlisten-on-v6 { any; };' "$OPTIONS_FILE"
fi
echo "   listen-on: { any; }"

# allow-query any
if grep -q "allow-query" "$OPTIONS_FILE"; then
    sed -i 's/allow-query\s*{[^}]*}/allow-query { any; }/g' "$OPTIONS_FILE"
else
    sed -i '/^options {/a\
\tallow-query { any; };' "$OPTIONS_FILE"
fi
echo "   allow-query: { any; }"

# --- Adicionar zona ao named.conf.local ---
LOCAL_FILE="/etc/bind/named.conf.local"
ZONE_NAME="$DOMINIO"
ZONE_FILE="/etc/bind/db.$DOMINIO"

echo
echo "=== ➡️ Adicionando zona: $ZONE_NAME ==="
if grep -q "\"$ZONE_NAME\"" "$LOCAL_FILE" 2>/dev/null; then
    echo "   Zona ja existe em $LOCAL_FILE"
else
    cat >> "$LOCAL_FILE" <<EOF

zone "$ZONE_NAME" {
    type master;
    file "$ZONE_FILE";
};
EOF
    echo "   Zona adicionada."
fi

# --- Criar arquivo de zona ---
echo
echo "=== ➡️ Criando arquivo de zona: $ZONE_FILE ==="
if [ -f "$ZONE_FILE" ]; then
    cp "$ZONE_FILE" "$BACKUP_DIR/db.$DOMINIO"
    echo "   Backup do arquivo existente salvo em $BACKUP_DIR"
fi

SERIAL=$(date +%Y%m%d)01

cat > "$ZONE_FILE" <<EOF
\$TTL    604800
@       IN      SOA     ns.$DOMINIO. admin.$DOMINIO. (
                        $SERIAL   ; Serial
                        604800    ; Refresh
                        86400     ; Retry
                        2419200   ; Expire
                        604800    ; Negative Cache TTL
)

@       IN      NS      ns.$DOMINIO.
@       IN      A       $IP_SERVIDOR
ns      IN      A       $IP_SERVIDOR
www     IN      A       $IP_SERVIDOR
EOF

echo "   Registros: NS, @ (A), ns (A), www (A) -> $IP_SERVIDOR"

# --- Validar ---
echo
echo "=== ➡️ Validando configuracao ==="
if named-checkconf 2>&1; then
    echo "✅ named-checkconf: OK"
else
    echo "❌ Erro na validacao. Restaure o backup em $BACKUP_DIR"
    exit 1
fi

if named-checkzone "$ZONE_NAME" "$ZONE_FILE" 2>&1; then
    echo "✅ named-checkzone: OK"
else
    echo "❌ Erro na zona. Restaure o backup em $BACKUP_DIR"
    exit 1
fi

# --- Recarregar servico ---
echo
echo "=== ➡️ Recarregando $SERVICO ==="
systemctl reload "$SERVICO" || systemctl restart "$SERVICO"
echo "✅ Servico recarregado."

# --- Testar ---
echo
echo "=== ➡️ Testando resolucao local ==="
sleep 1
for registro in "$DOMINIO" "ns.$DOMINIO" "www.$DOMINIO"; do
    if dig +short @"127.0.0.1" "$registro" 2>/dev/null | grep -q "$IP_SERVIDOR"; then
        echo "   ✅ $registro -> $IP_SERVIDOR"
    else
        echo "   ⚠️  $registro -> falhou (pode levar alguns segundos)"
    fi
done

echo
echo "=============================================="
echo "✅ Servidor DNS configurado com sucesso!"
echo
echo "   Dominio     : $DOMINIO"
echo "   IP          : $IP_SERVIDOR"
echo "   Arquivo zona: $ZONE_FILE"
echo "   Backup      : $BACKUP_DIR"
echo
echo "   Para testar nos clientes:"
echo "   nslookup www.$DOMINIO $IP_SERVIDOR"
echo "=============================================="
