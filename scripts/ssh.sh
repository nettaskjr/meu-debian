#!/bin/bash
set -e
appNome="OpenSSH Server"

echo "=== ➡️ Instalando $appNome ==="

echo "=== ➡️ Atualizando o sistema ==="
sudo apt update -y
sudo apt upgrade -y

echo "=== ➡️ Instalando $appNome ==="
sudo apt install -y openssh-server

echo "=== ➡️ Habilitando SSH na inicializacão ==="
sudo systemctl enable ssh
sudo systemctl start ssh

echo
echo "=============================================="
echo "Status do SSH:"
sudo systemctl status ssh --no-pager || true
echo
echo "✅ $appNome instalado com sucesso!"
echo "=============================================="
