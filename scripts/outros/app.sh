#!/bin/bash
set -e

appNome="Firefox-esr"
appNomeLower=$(echo "$appNome" | tr '[:upper:]' '[:lower:]')

echo "=== ➡️ Instalando $appNome ==="

echo "=== ➡️ Atualizando o sistema ==="
sudo apt update -y
sudo apt upgrade -y

echo "=== ➡️ Instalando $appNome ==="
sudo apt install -y $appNomeLower

echo
echo "=============================================="
echo "$appNome versão: $($appNomeLower --version)"
echo
echo "✅ $appNome instalado com sucesso!"
echo "=============================================="