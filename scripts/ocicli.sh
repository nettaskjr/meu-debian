#!/bin/bash
set -e

appNome="OCI-CLI"
appNomeLower=oci

echo "=== ➡️ Instalando $appNome ==="

echo "=== ➡️ Atualizando o sistema ==="
sudo apt update -y
sudo apt upgrade -y

echo "=== ➡️ Instalando $appNome ==="
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"

echo
echo "=============================================="
echo "$appNome versão: $($appNomeLower --version)"
echo
echo "✅ $appNome instalado com sucesso!"
echo "=============================================="