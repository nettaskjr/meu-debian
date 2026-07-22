#!/bin/bash
set -e

appNome="IP Fixo (Debian)"

echo "=============================================="
echo "  🔧 Configuracao de $appNome"
echo "=============================================="
echo

INTERFACES_FILE="/etc/network/interfaces"
BACKUP_FILE="/etc/network/interfaces.bkp-$(date +%Y%m%d-%H%M%S)"

if [ "$EUID" -ne 0 ]; then
    echo "❌ Execute como root: sudo bash $0"
    exit 1
fi

echo "=== ➡️ Interfaces de rede disponiveis ==="
ip -br link show | grep -v "lo" | awk '{print "   "$1, $2, $3}'
echo

read -r -p "Nome da interface (ex: enp0s3): " IFACE
if [ -z "$IFACE" ]; then
    echo "❌ Interface nao informada."
    exit 1
fi

if ! ip link show "$IFACE" &>/dev/null; then
    echo "❌ Interface '$IFACE' nao encontrada."
    exit 1
fi

read -r -p "IP estatico (ex: 192.168.0.10): " IP
read -r -p "Prefixo CIDR (ex: 24 para /24): " CIDR
read -r -p "Gateway (ex: 192.168.0.1): " GATEWAY
read -r -p "DNS primario (ex: 8.8.8.8): " DNS1
read -r -p "DNS secundario (ex: 8.8.4.4) [opcional]: " DNS2

if [ -z "$IP" ] || [ -z "$CIDR" ] || [ -z "$GATEWAY" ] || [ -z "$DNS1" ]; then
    echo "❌ Todos os campos obrigatorios devem ser preenchidos."
    exit 1
fi

# Converte CIDR para netmask
prefix_to_netmask() {
    local prefix=$1
    local mask=""
    for i in $(seq 1 4); do
        if [ "$prefix" -ge 8 ]; then
            mask="${mask}255"
            prefix=$((prefix - 8))
        elif [ "$prefix" -gt 0 ]; then
            mask="${mask}$(( 256 - (1 << (8 - prefix)) ))"
            prefix=0
        else
            mask="${mask}0"
        fi
        [ "$i" -lt 4 ] && mask="${mask}."
    done
    echo "$mask"
}

NETMASK=$(prefix_to_netmask "$CIDR")

echo
echo "=============================================="
echo "  📋 Resumo da configuracao:"
echo "  Interface : $IFACE"
echo "  IP        : $IP/$CIDR ($NETMASK)"
echo "  Gateway   : $GATEWAY"
echo "  DNS       : $DNS1 $DNS2"
echo "=============================================="
echo
read -r -p "Aplicar esta configuracao? [s/N]: " CONFIRM

if [ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ]; then
    echo "Cancelado."
    exit 0
fi

echo
echo "=== ➡️ Criando backup: $BACKUP_FILE ==="
cp "$INTERFACES_FILE" "$BACKUP_FILE"

echo "=== ➡️ Escrevendo nova configuracao de rede ==="
cat > "$INTERFACES_FILE" <<EOF
# Configuracao de IP fixo gerada por ip-fixo.sh
# Backup em: $BACKUP_FILE

auto lo
iface lo inet loopback

auto $IFACE
iface $IFACE inet static
    address $IP
    netmask $NETMASK
    gateway $GATEWAY
    dns-nameservers $DNS1 $DNS2
EOF

echo
echo "=== ➡️ Aplicando nova configuracao de rede ==="
systemctl restart networking || {
    echo
    echo "❌ Falha ao reiniciar o servico networking."
    echo "Restaurando backup..."
    cp "$BACKUP_FILE" "$INTERFACES_FILE"
    systemctl restart networking
    echo "✅ Backup restaurado."
    exit 1
}

echo
echo "=============================================="
echo "✅ IP fixo configurado com sucesso!"
echo "   Interface : $IFACE"
echo "   IP        : $IP/$CIDR"
echo "   Gateway   : $GATEWAY"
echo "   DNS       : $DNS1 ${DNS2:-}"
echo "   Backup    : $BACKUP_FILE"
echo
echo "⚠️  Se o sistema usar NetworkManager, execute:"
echo "   sudo nmcli device set $IFACE managed no"
echo "=============================================="
