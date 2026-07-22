#!/bin/bash
set -e
appNome="Bind9 (DNS Server)"

echo "=== ➡️ Instalando $appNome ==="

echo "=== ➡️ Atualizando o sistema ==="
sudo apt update -y
sudo apt upgrade -y

echo "=== ➡️ Instalando $appNome ==="
sudo apt install -y bind9 bind9utils bind9-doc

echo "=== ➡️ Habilitando Bind9 na inicializacão ==="
sudo systemctl enable bind9
sudo systemctl start bind9

echo
echo "=============================================="
echo "Status do Bind9:"
sudo systemctl status bind9 --no-pager || true
echo
echo "✅ $appNome instalado com sucesso!"
echo
echo "🔧 Configuracões principais:"
echo "   /etc/bind/named.conf.options  - opcões globais"
echo "   /etc/bind/named.conf.local    - zonas locais"
echo "   /etc/bind/named.conf.default-zones - zonas padrão"
echo
echo "📁 Diretório de zonas: /etc/bind/"
echo "=============================================="
