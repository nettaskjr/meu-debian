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
  sudo curl -fsSL https://freellmapi.co/install.sh | bash

  echo
  read -rp "Informe a API key para cadastrar no Claude Code: " api_key

  echo
  echo "=== ➡️ Testando a API key ==="
  if curl -fsS http://localhost:3001/v1/chat/completions \
    -H "Authorization: Bearer $api_key" \
    -H "Content-Type: application/json" \
    -d '{"model":"auto","messages":[{"role":"user","content":"Hello"}]}' > /dev/null; then
    echo "✅ API key válida!"
  else
    echo "❌ API key inválida. Abortando o cadastro."
    exit 1
  fi

  echo "=== ➡️ Configurando o Claude Code ==="
  npx freellmapi setup-claude --url http://localhost:3001 --api-key "$api_key"
fi

echo
echo "=============================================="
echo "$appNome versão: $($appNomeLower --version)"
echo
echo "✅ $appNome instalado com sucesso!"
echo "=============================================="
