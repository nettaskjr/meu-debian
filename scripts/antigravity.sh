#!/bin/bash
set -e

appNome="Antigravity"
appNomeLower=$(echo "$appNome" | tr '[:upper:]' '[:lower:]')

echo "=== ➡️ Instalando @$appNome ==="

echo "=== ➡️ Atualizando o sistema ==="
sudo apt update -y
sudo apt upgrade -y

echo "=== ➡️ Criando diretório para chaves GPG ==="
sudo mkdir -p /etc/apt/keyrings

echo "=== ➡️ Adicionando chave GPG oficial do @$appNome ==="
curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/antigravity-repo-key.gpg

echo "=== ➡️ Adicionando repositório oficial do @$appNome ==="
echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" | \
  sudo tee /etc/apt/sources.list.d/antigravity.list > /dev/null

echo "=== ➡️ Atualizando repositórios ==="
sudo apt update -y

echo "=== ➡️ Instalando $appNome ==="
sudo apt install -y $appNomeLower

echo
echo "=============================================="
echo "✅ @$appNome instalado com sucesso!"
echo "=============================================="