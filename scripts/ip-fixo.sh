#!/bin/bash
set -e

appNome="IP Fixo (Debian)"

echo "=============================================="
echo "  🔧 Configuracao de $appNome"
echo "=============================================="
echo

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

DNS_LIST="$DNS1"
[ -n "$DNS2" ] && DNS_LIST="$DNS1,$DNS2"

echo
echo "=============================================="
echo "  📋 Resumo da configuracao:"
echo "  Interface : $IFACE"
echo "  IP        : $IP/$CIDR"
echo "  Gateway   : $GATEWAY"
echo "  DNS       : $DNS_LIST"
echo "=============================================="
echo
read -r -p "Aplicar esta configuracao? [s/N]: " CONFIRM

if [ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ]; then
    echo "Cancelado."
    exit 0
fi

USAR_NM=false
if systemctl is-active NetworkManager &>/dev/null; then
    USAR_NM=true
    echo
    echo "=== ➡️ NetworkManager detectado ==="

    CONN_NAME=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep ":$IFACE$" | head -1 | cut -d: -f1)
    if [ -z "$CONN_NAME" ]; then
        echo "=== ➡️ Conexoes disponiveis no NetworkManager ==="
        nmcli -t -f NAME,DEVICE connection show 2>/dev/null | awk -F: '{print "   "$1"  (dispositivo: "$2")"}'
        echo
        read -r -p "Nome da conexao para '$IFACE': " CONN_NAME
    fi

    if [ -z "$CONN_NAME" ]; then
        echo "❌ Nome da conexao nao informado."
        exit 1
    fi

    echo "=== ➡️ Configurando IP fixo via NetworkManager ==="
    nmcli connection modify "$CONN_NAME" \
        ipv4.method manual \
        ipv4.addresses "$IP/$CIDR" \
        ipv4.gateway "$GATEWAY" \
        ipv4.dns "$DNS_LIST" \
        ipv4.ignore-auto-dns yes

    echo "=== ➡️ Aplicando a nova configuracao ==="
    nmcli connection down "$CONN_NAME" 2>/dev/null || true
    nmcli connection up "$CONN_NAME"
else
    echo
    echo "=== ➡️ NetworkManager nao detectado, usando /etc/network/interfaces ==="

    # Converte CIDR para netmask
    prefix_to_netmask() {
        local prefix=$1
        local mask=""
        for i in 1 2 3 4; do
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

    INTERFACES_FILE="/etc/network/interfaces"
    BACKUP_FILE="/etc/network/interfaces.bkp-$(date +%Y%m%d-%H%M%S)"

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
    dns-nameservers $DNS_LIST
EOF

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
fi

echo
echo "=============================================="
echo "✅ IP fixo configurado com sucesso!"
echo "   Interface : $IFACE"
echo "   IP        : $IP/$CIDR"
echo "   Gateway   : $GATEWAY"
echo "   DNS       : $DNS_LIST"
echo "=============================================="
