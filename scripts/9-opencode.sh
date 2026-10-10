#!/bin/bash
set -e

appNome="Nodejs"
appNomeLower=$(echo "$appNome" | tr '[:upper:]' '[:lower:]')

echo "=== ➡️ Instalando $appNome ==="

echo "=== ➡️ Atualizando o sistema ==="
sudo apt update -y
sudo apt upgrade -y

echo "=== ➡️ Instalando $appNome ==="
curl -fsSL https://opencode.ai/install | bash

echo
echo "=============================================="
$appNomeLower --version
echo
echo "✅ $appNome instalado com sucesso!"
echo "=============================================="