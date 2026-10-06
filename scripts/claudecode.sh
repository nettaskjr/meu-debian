#!/bin/bash
set -e

appNome="Claude"
appNomeLower=$(echo "$appNome" | tr '[:upper:]' '[:lower:]')

echo "=== ➡️ Instalando $appNome ==="

echo "=== ➡️ Atualizando o sistema ==="
sudo apt update -y
sudo apt upgrade -y

echo "=== ➡️ Instalando $appNome ==="
curl -fsSL https://claude.ai/install.sh | bash

echo
echo "=== ➡️ FreeLLM API ==="
read -rp "Deseja instalar o FreeLLM API? (s/N): " instalar_freellm
if [[ "$instalar_freellm" =~ ^[Ss]$ ]]; then
  curl -fsSL https://freellmapi.co/install.sh | bash

  echo
  read -rp "Informe a API key para cadastrar no Claude Code: " api_key
  npx freellmapi setup-claude --url http://localhost:3001 --api-key "$api_key"
fi

echo
echo "=============================================="
echo "$appNome versão: $($appNomeLower --version)"
echo
echo "✅ $appNome instalado com sucesso!"
echo "=============================================="
