#!/bin/bash
set -e


# TERRAFORM_VERSION="1.15.5"

# echo "➡️ Garantindo que 'curl' e 'unzip' estão instalados..."
# sudo apt-get update
# sudo apt-get install -y curl unzip

# echo "➡️ Baixando o Terraform versão ${TERRAFORM_VERSION}..."
# curl -LO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"

# echo "➡️ Extraindo o arquivo..."
# unzip -o "terraform_${TERRAFORM_VERSION}_linux_amd64.zip"

# echo "➡️ Movendo o executável para o PATH (/usr/local/bin)..."
# sudo mv terraform /usr/local/bin/

# echo "➡️ Limpando os arquivos baixados..."
# rm "terraform_${TERRAFORM_VERSION}_linux_amd64.zip"

# echo "✅ Instalação do Terraform concluída com sucesso!"
# echo "➡️ Versão instalada:"
# terraform -v




wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform