#!/bin/bash
set -e

echo "=== Atualizando o sistema ==="
sudo apt update -y
sudo apt upgrade -y

echo "=== Removendo versões antigas do Docker (se existirem) ==="
sudo apt remove -y docker docker-engine docker.io containerd runc || true

echo "=== Instalando dependências para usar repositório HTTPS ==="
sudo apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

echo "=== Criando diretório para chave GPG ==="
sudo install -m 0755 -d /etc/apt/keyrings

echo "=== Baixando chave oficial do Docker ==="
curl -fsSL https://download.docker.com/linux/debian/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "=== Adicionando repositório oficial do Docker ==="
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "=== Atualizando repositórios ==="
sudo apt update -y

echo "=== Instalando Docker Engine, CLI, Containerd e Docker Compose ==="
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "=== Habilitando Docker na inicialização ==="
sudo systemctl enable docker
sudo systemctl start docker

echo "=== Adicionando usuário atual ao grupo docker ==="
sudo usermod -aG docker $USER

echo "=== Verificando instalação ==="
docker --version
docker compose version

echo
echo "=============================================="
echo "Docker instalado com sucesso!"
echo "⚠️  Saia e entre novamente no terminal para ativar o grupo docker."
echo "Ou execute: newgrp docker"
echo "=============================================="
