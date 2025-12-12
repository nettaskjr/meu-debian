#!/bin/bash
set -e

echo "=== Instalando VirtualBox e Extension Pack ==="

echo "=== Atualizando o sistema ==="
sudo apt update -y
sudo apt upgrade -y

echo "=== Instalando dependências necessárias ==="
sudo apt install -y \
    build-essential \
    dkms \
    linux-headers-$(uname -r) \
    curl \
    wget \
    gnupg

echo "=== Criando diretório para chaves GPG ==="
sudo install -m 0755 -d /etc/apt/keyrings

echo "=== Adicionando chave GPG oficial do VirtualBox ==="
curl -fsSL https://www.virtualbox.org/download/oracle_vbox_2016.asc | \
    sudo gpg --dearmor -o /etc/apt/keyrings/oracle-virtualbox.gpg

curl -fsSL https://www.virtualbox.org/download/oracle_vbox.asc | \
    sudo gpg --dearmor -o /etc/apt/keyrings/oracle-virtualbox-2.gpg

sudo chmod a+r /etc/apt/keyrings/oracle-virtualbox.gpg
sudo chmod a+r /etc/apt/keyrings/oracle-virtualbox-2.gpg

echo "=== Adicionando repositório oficial do VirtualBox ==="
sudo tee /etc/apt/sources.list.d/virtualbox.list > /dev/null <<EOF
deb [arch=amd64 signed-by=/etc/apt/keyrings/oracle-virtualbox.gpg] https://download.virtualbox.org/virtualbox/debian $(lsb_release -cs) contrib
EOF

echo "=== Atualizando repositórios ==="
sudo apt update -y

echo "=== Instalando VirtualBox ==="
sudo apt install -y virtualbox-7.2

echo "=== Desabilitando módulos KVM (se estiverem carregados) ==="
if lsmod | grep -q kvm; then
    echo "KVM detectado. Desabilitando módulos KVM..."
    sudo modprobe -r kvm_amd kvm 2>/dev/null || true
    sudo modprobe -r kvm_intel kvm 2>/dev/null || true
    echo "KVM desabilitado"
else
    echo "KVM não está carregado"
fi

echo "=== Obtendo versão instalada do VirtualBox ==="
VB_VERSION=$(vboxmanage --version | cut -d'r' -f1)
echo "Versão do VirtualBox instalada: $VB_VERSION"

echo "=== Baixando Extension Pack ==="
EXT_PACK_URL="https://download.virtualbox.org/virtualbox/${VB_VERSION}/Oracle_VirtualBox_Extension_Pack-${VB_VERSION}.vbox-extpack"
EXT_PACK_FILE="/tmp/Oracle_VirtualBox_Extension_Pack-${VB_VERSION}.vbox-extpack"

if wget -q --spider "$EXT_PACK_URL"; then
    wget -O "$EXT_PACK_FILE" "$EXT_PACK_URL"
    echo "=== Instalando Extension Pack ==="
    sudo vboxmanage extpack install --replace "$EXT_PACK_FILE"
    rm "$EXT_PACK_FILE"
    echo "Extension Pack instalado com sucesso!"
else
    echo "Aviso: Não foi possível encontrar o Extension Pack para a versão $VB_VERSION"
    echo "Você pode instalar manualmente mais tarde usando: VBoxManage extpack install <arquivo>"
fi

echo "=== Habilitando módulo de kernel vboxdrv ==="
sudo modprobe vboxdrv

echo "=== Adicionando usuário atual ao grupo vboxusers ==="
sudo usermod -aG vboxusers $USER

echo "=== Verificando instalação ==="
vboxmanage --version

echo
echo "=== Instalação concluída! ==="
echo "IMPORTANTE: Você deve reiniciar o sistema para aplicar as mudanças nos módulos do kernel"
echo "e as permissões de grupo: sudo reboot"