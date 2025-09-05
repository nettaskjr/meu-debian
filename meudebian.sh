#!/bin/bash

# ===================================================================================
#
#   SCRIPT DE PÓS-INSTALAÇÃO E GERENCIAMENTO DE APLICATIVOS PARA DEBIAN
#
#   Descrição: Este script  automatiza a configuração inicial de um sistema Debian,
#              habilitação de repositórios instalação de aplicativos gerenciada por
#              arquivos CSV.
#
#   Autor: netTask and Geminin
#   Versão: 1.0
#   Data: 2025-08-23
#
# ===================================================================================

# --- VARIÁVEIS DE COR ---
VERDE='\033[0;32m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
NC='\033[0m' # Sem Cor

# --- VARIÁVEIS GLOBAIS ---
ARQUITETURA=""

# ===================================================================================
# --- FUNÇÕES AUXILIARES ---
# ===================================================================================

# Função para verificar se o script está sendo executado como root
verificar_root() {
    echo -e "${AMARELO}Verificando permissões de superusuário...${NC}"
    if [[ "$(id -u)" -ne 0 ]]; then
        echo -e "${VERMELHO}ERRO: Este script precisa ser executado como root.${NC}"
        echo "Use: sudo ./setup_debian.sh"
        exit 1
    fi
    echo -e "${VERDE}Verificação de root concluída com sucesso.${NC}\n"
}

# Função para verificar a conexão com a internet
verificar_internet() {
    echo -e "${AMARELO}Verificando conexão com a internet...${NC}"
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        echo -e "${VERMELHO}ERRO: Não foi possível conectar à internet. Verifique sua conexão e tente novamente.${NC}"
        exit 1
    fi
    echo -e "${VERDE}Conexão com a internet funcionando.${NC}\n"
}

# Função para detectar a arquitetura do sistema
detectar_arquitetura() {
    echo -e "${AMARELO}Detectando a arquitetura do sistema...${NC}"
    ARQUITETURA=$(dpkg --print-architecture)
    if [[ -z "$ARQUITETURA" ]]; then
        echo -e "${VERMELHO}ERRO: Não foi possível determinar a arquitetura do sistema.${NC}"
        exit 1
    fi
    echo -e "${VERDE}Arquitetura detectada: ${ARQUITETURA}${NC}\n"
}

# Função para instalar as atualizações do sistema
instalar_atualiacoes() {
    echo -e "${AMARELO}Corrigindo o gerenciador de pacotes e atualizando o sistema...${NC}"
    dpkg --configure -a
    apt-get update
    apt-get dist-upgrade -y
    apt-get install -f -y # Tenta corrigir dependências quebradas
    apt-get autoremove -y --purge # Remove pacotes órfãos e suas configurações
    echo -e "${VERDE}Sistema atualizado com sucesso.${NC}\n"
}

# Função para habilitar repositórios contrib e non-free
habilitar_repositorios_extras() {
    echo -e "${AMARELO}Habilitando repositórios 'contrib' e 'non-free'...${NC}"
    # Faz um backup do sources.list original
    cp /etc/apt/sources.list /etc/apt/sources.list.bak

    # Desabilita o repositório cdrom, se existir, comentando a linha
    echo -e "${AMARELO}Desabilitando o repositório CD-ROM (se estiver ativo)...${NC}"
    sed -i '/^deb cdrom:/s/^/# /' /etc/apt/sources.list

    # Adiciona contrib e non-free às linhas existentes
    sed -i 's/main/main contrib non-free/g' /etc/apt/sources.list
    echo -e "${AMARELO}Atualizando a lista de pacotes após adicionar novos repositórios...${NC}"
    echo -e "${VERDE}Repositórios extras habilitados e lista de pacotes atualizada.${NC}\n"
}

# Funçao para atualizar o PATH do sistema
atualizar_path() {
    echo -e "${AMARELO}Atualizando o PATH do sistema...${NC}"
    # Adiciona /usr/local/sbin:/usr/sbin:/sbin ao PATH se não estiver presente
    if ! grep -q '/usr/local/sbin:/usr/sbin:/sbin' /etc/profile; then
        echo 'export PATH=$PATH:/usr/local/sbin:/usr/sbin:/sbin' >> /etc/profile
        echo -e "${VERDE}/usr/local/sbin:/usr/sbin:/sbin adicionado ao PATH.${NC}"
    else
        echo -e "${VERDE}/usr/local/sbin:/usr/sbin:/sbin já está no PATH.${NC}"
    fi
    source "/etc/profile"
    echo -e "${VERDE}Atualização do PATH concluída.${NC}\n"
}

# ===================================================================================
# --- FUNÇÕES DE INSTALAÇÃO ---
# ===================================================================================

instalar_via_apt() {
    local a_csv_file="apt_apps.csv"
    if [ ! -f "$a_csv_file" ]; then
        echo -e "${AMARELO}Arquivo ${a_csv_file} não encontrado. Pulando instalações via APT.${NC}"
        return
    fi

    echo -e "${AMARELO}--- INICIANDO INSTALAÇÕES VIA APT ---${NC}"
    # Usar substituição de processo (< <(...)) e verificar a variável (|| [[ -n ... ]])
    # para garantir que a última linha do CSV seja lida, mesmo se não tiver uma quebra de linha no final.
    while IFS=, read -r app_name installer_name description || [[ -n "$app_name" ]]; do
        echo -e "${VERDE}Instalando ${app_name} (${description})...${NC}"
        apt-get install -y "$installer_name" < /dev/null
        echo -e "${VERDE}${app_name} instalado com sucesso.${NC}\n"
    done < <(tail -n +2 "$a_csv_file")
    echo -e "${VERDE}--- INSTALAÇÕES VIA APT CONCLUÍDAS ---${NC}\n"
}

instalar_via_deb() {
    local d_csv_file="deb_apps.csv"
    if [ ! -f "$d_csv_file" ]; then
        echo -e "${AMARELO}Arquivo ${d_csv_file} não encontrado. Pulando instalações via .deb.${NC}"
        return
    fi
    
    echo -e "${AMARELO}--- INICIANDO INSTALAÇÕES VIA PACOTES .DEB ---${NC}"
    local temp_deb="/tmp/temp_package.deb"
    while IFS=, read -r app_name url description || [[ -n "$app_name" ]]; do
        echo -e "${VERDE}Instalando ${app_name} (${description})...${NC}"
        
        # Adiciona verificação de arquitetura para o exemplo do Chrome
        if [[ "$app_name" == "Google Chrome" && "$ARQUITETURA" != "amd64" ]]; then
            echo -e "${AMARELO}AVISO: Google Chrome está disponível apenas para a arquitetura amd64. Pulando instalação.${NC}"
            continue
        fi

        wget -O "$temp_deb" "$url"
        if [ $? -eq 0 ]; then
            apt-get install -y "$temp_deb" < /dev/null
            rm "$temp_deb"
            echo -e "${VERDE}${app_name} instalado com sucesso.${NC}\n"
        else
            echo -e "${VERMELHO}ERRO: Falha ao baixar o pacote para ${app_name}.${NC}\m"
        fi
    done < <(tail -n +2 "$d_csv_file")
    
    echo -e "${VERDE}--- INSTALAÇÕES VIA .DEB CONCLUÍDAS ---${NC}\n"
}

instalar_via_flatpak() {
    local f_csv_file="flatpak_apps.csv"
    if [ ! -f "$f_csv_file" ]; then
        echo -e "${AMARELO}Arquivo ${f_csv_file} não encontrado. Pulando instalações via Flatpak.${NC}"
        return
    fi

    echo -e "${AMARELO}--- CONFIGURANDO E INICIANDO INSTALAÇÕES VIA FLATPAK ---${NC}"
    # Verifica se o flatpak está instalado
    if ! command -v flatpak &> /dev/null; then
        echo "Flatpak não encontrado. Instalando..."
        apt-get install -y flatpak gnome-software-plugin-flatpak
    fi
    # Adiciona o repositório Flathub
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    
    while IFS=, read -r app_name flatpak_id description || [[ -n "$app_name" ]]; do
        echo -e "${VERDE}Instalando ${app_name} (${description})...${NC}"
        flatpak install -y flathub "$flatpak_id" < /dev/null
        echo -e "${VERDE}${app_name} instalado com sucesso.${NC}\m"
    done < <(tail -n +2 "$f_csv_file")
    echo -e "${VERDE}--- INSTALAÇÕES VIA FLATPAK CONCLUÍDAS ---${NC}\n"
}

instalar_via_appimage() {
    local i_csv_file="appimage_apps.csv"
    if [ ! -f "$i_csv_file" ]; then
        echo -e "${AMARELO}Arquivo ${i_csv_file} não encontrado. Pulando instalações via AppImage.${NC}"
        return
    fi

    echo -e "${AMARELO}--- INICIANDO DOWNLOADS DE APPIMAGES ---${NC}"
    local appimage_dir="/opt/AppImages"
    mkdir -p "$appimage_dir"

    while IFS=, read -r app_name url description || [[ -n "$app_name" ]]; do
        # Remove espaços para um nome de arquivo seguro
        local file_name="${app_name// /_}.AppImage"
        local destination="${appimage_dir}/${file_name}"
        echo -e "${VERDE}Baixando ${app_name} (${description})...${NC}"
        wget -O "$destination" "$url"
        if [ $? -eq 0 ]; then
            chmod +x "$destination"
            echo -e "${VERDE}${app_name} baixado e tornado executável em ${destination}${NC}\n"
        else
            echo -e "${VERMELHO}ERRO: Falha ao baixar o AppImage para ${app_name}.${NC}\n"
        fi
    done < <(tail -n +2 "$i_csv_file")
    echo -e "${VERDE}--- DOWNLOADS DE APPIMAGES CONCLUÍDOS ---${NC}\n"
}


# ===================================================================================
# --- FUNÇÃO PRINCIPAL ---
# ===================================================================================
main() {
    clear
    echo -e "${VERDE}====================================================${NC}"
    echo -e "${VERDE}  Iniciando Script de Configuração para Debian      ${NC}"
    echo -e "${VERDE}====================================================${NC}\n"

    # Etapas de verificação e preparação
    verificar_root
    verificar_internet
    detectar_arquitetura
    habilitar_repositorios_extras
    atualizar_path
    instalar_atualiacoes

    # Etapas de instalação
    instalar_via_deb
    instalar_via_appimage
    instalar_via_apt
    instalar_via_flatpak
    
    echo -e "${VERDE}====================================================${NC}"
    echo -e "${VERDE}   Script concluído com sucesso!                    ${NC}"
    echo -e "${VERDE}====================================================${NC}"
    echo -e "Verifique o log acima para eventuais erros."
    echo -e "Pode ser necessário reiniciar o sistema para que todas as alterações do Flatpak entrem em vigor."
}

# --- PONTO DE ENTRADA DO SCRIPT ---
main