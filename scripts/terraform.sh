#!/bin/bash
set -e

echo "=== ➡️ Instalando Terraform ==="

echo "=== ➡️ Atualizando o sistema ==="
sudo apt update -y
sudo apt upgrade -y

echo "=== ➡️ Instalando Terraform ==="
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "=== ➡️ Adicionando repositório oficial do Terraform ==="
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

echo "=== ➡️ Atualizando repositórios ==="
sudo apt update -y

echo "=== ➡️ Instalando Terraform ==="
sudo apt install -y terraform

echo
echo "=============================================="
terraform version
echo
echo "✅ Terraform instalado com sucesso!"
echo "=============================================="