#!/bin/bash

# Se estiver no Debian 13 (trixie), use bookworm como fallback:
CODENAME=$(lsb_release -cs)
SUPPORTED="bookworm bullseye jammy noble"
if echo "$SUPPORTED" | grep -qw "$CODENAME"; then
    REPO="$CODENAME"
else
    REPO="bookworm"
fi

curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | \
    sudo gpg --dearmor -o /usr/share/keyrings/cloudflare-main.gpg

echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $REPO main" | \
    sudo tee /etc/apt/sources.list.d/cloudflared.list

sudo apt update && sudo apt install -y cloudflared