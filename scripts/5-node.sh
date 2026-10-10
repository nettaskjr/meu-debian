#!/bin/bash
set -e

appNome="Nodejs"
appNomeLower=$(echo "$appNome" | tr '[:upper:]' '[:lower:]')

echo "=== ➡️ Instalando $appNome ==="

echo "=== ➡️ Atualizando o sistema ==="
sudo apt update -y
sudo apt upgrade -y

echo "=== ➡️ Instalando $appNome ==="
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo bash -
sudo apt install -y $appNomeLower

echo
echo "=============================================="
echo "node:" $(node -v)
echo "npm.:" $(npm -v)
echo
echo "✅ $appNome instalado com sucesso!"
echo "=============================================="