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

echo "Escolha o ambiente de desktop:"
echo "  1) GNOME"
echo "  2) XFCE  (leve, recomendado para servidor)"
echo
read -r -p "Opcao [1-2]: " DESKTOP_OPCAO

case "$DESKTOP_OPCAO" in
    1) DESKTOP="gnome" ;;
    2) DESKTOP="xfce" ;;
    *)
        echo "❌ Opcao invalida."
        exit 1
        ;;
esac

echo
echo "=== ➡️ Atualizando o sistema ==="
sudo apt update -y
sudo apt upgrade -y

echo "=== ➡️ Instalando xRDP ==="
sudo apt install -y xrdp

# --- Configurar desktop escolhido ---
if [ "$DESKTOP" = "gnome" ]; then
    echo "=== ➡️ Verificando ambiente GNOME ==="
    if ! dpkg -l gnome-shell &>/dev/null; then
        echo "   GNOME nao encontrado. Instalando..."
        sudo apt install -y gnome-session gnome-shell
    fi
    echo "   GNOME disponivel."

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
    echo "   startwm.sh configurado para GNOME."

elif [ "$DESKTOP" = "xfce" ]; then
    echo "=== ➡️ Instalando ambiente XFCE ==="
    sudo apt install -y xfce4 xfce4-goodies

    echo "=== ➡️ Configurando sessao XFCE para xRDP ==="
    cat > /etc/xrdp/startwm.sh <<'XEOF'
#!/bin/sh
if [ -r /etc/default/locale ]; then
    . /etc/default/locale
    export LANG LANGUAGE
fi

startxfce4
XEOF
    chmod +x /etc/xrdp/startwm.sh
    echo "   startwm.sh configurado para XFCE."
fi

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
echo "   Desktop   : $(echo "$DESKTOP" | tr '[:lower:]' '[:upper:]')"
echo
echo "   📌 Acesse via Remote Desktop (RDP):"
echo "      IP: $IP"
echo "      Porta: 3389"
echo
echo "   ⚠️  Certifique-se de ter um usuario nao-root criado."
echo "=============================================="
