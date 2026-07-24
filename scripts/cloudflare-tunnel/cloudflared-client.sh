#!/bin/bash
set -e

echo "=== ➡️ Instalando cloudflared (cliente) ==="

if command -v cloudflared &>/dev/null; then
    echo "✅ cloudflared ja instalado: $(cloudflared version 2>/dev/null | head -1)"
    exit 0
fi

CODENAME=$(lsb_release -cs 2>/dev/null || echo "bookworm")
SUPPORTED="bookworm bullseye jammy noble"
if echo "$SUPPORTED" | grep -qw "$CODENAME"; then
    REPO="$CODENAME"
else
    REPO="bookworm"
    echo "   Codename '$CODENAME' nao suportado. Usando repositorio: $REPO"
fi

curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | \
    sudo gpg --dearmor -o /usr/share/keyrings/cloudflare-main.gpg

echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $REPO main" | \
    sudo tee /etc/apt/sources.list.d/cloudflared.list > /dev/null

sudo apt update -y
sudo apt install -y cloudflared

echo
echo "✅ cloudflared instalado: $(cloudflared version 2>/dev/null | head -1)"
echo
echo "   Para acessar o servidor via SSH:"
echo "   cloudflared access ssh --hostname ssh.seudominio.com"
echo
echo "   Ou adicione ao ~/.ssh/config:"
echo "   Host ssh.seudominio.com"
echo "       ProxyCommand cloudflared access ssh --hostname %h"
