#!/bin/bash
set -e

appNome="xRDP (Remote Desktop)"

echo "=============================================="
echo "  🔧 Instalacao de $appNome"
echo "=============================================="
echo

if [ "$EUID" -ne 0 ]; then
    echo "❌ Execute como root: sudo bash $0"
    exit 1
fi

echo "=== ➡️ Atualizando o sistema ==="
sudo apt update -y
sudo apt upgrade -y

echo "=== ➡️ Verificando ambiente GNOME ==="
if ! dpkg -l gnome-shell &>/dev/null; then
    echo "   GNOME nao encontrado. Instalando..."
    sudo apt install -y gnome-session gnome-shell
fi
echo "   GNOME disponivel."

echo "=== ➡️ Instalando xRDP ==="
sudo apt install -y xrdp

echo "=== ➡️ Configurando sessao GNOME para xRDP ==="
cat > /etc/xrdp/startwm.sh <<'XEOF'
#!/bin/sh
if [ -r /etc/default/locale ]; then
    . /etc/default/locale
    export LANG LANGUAGE
fi

export GNOME_SHELL_SESSION_MODE=ubuntu
export XDG_CURRENT_DESKTOP=ubuntu:GNOME
export XDG_SESSION_TYPE=x11

gnome-session
XEOF
chmod +x /etc/xrdp/startwm.sh
echo "   GNOME definido como sessao padrao do xRDP."

echo "=== ➡️ Ajustando firewall (porta 3389) ==="
sudo ufw allow 3389/tcp 2>/dev/null || echo "   ufw nao encontrado, pulando."

echo "=== ➡️ Habilitando e iniciando xRDP ==="
sudo systemctl enable xrdp
sudo systemctl restart xrdp

echo
echo "=============================================="
echo "Status do xRDP:"
sudo systemctl status xrdp --no-pager || true
echo
IP=$(hostname -I | awk '{print $1}')
echo "✅ $appNome instalado com sucesso!"
echo
echo "   📌 Acesse via Remote Desktop (RDP):"
echo "      IP: $IP"
echo "      Porta: 3389"
echo
echo "   ⚠️  Certifique-se de ter um usuario nao-root criado."
echo "=============================================="
