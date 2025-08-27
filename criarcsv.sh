#!/bin/bash

# --- VARIÁVEIS DE COR ---
VERDE='\033[0;32m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
NC='\033[0m' # Sem Cor

# Função para criar os arquivos CSV de exemplo
criar_arquivos_csv() {
    echo -e "${AMARELO}Criando arquivos CSV de exemplo para gerenciamento de aplicativos...${NC}"

    # Arquivo para APT
    cat << EOF > apt_apps.csv
nome_do_aplicativo,nome_do_instalador,descricao
VLC,vlc,"Reprodutor de mídia open-source e multiplataforma"
GIMP,gimp,"Editor de imagens avançado, alternativa ao Photoshop"
Flameshot,flameshot,"Ferramenta de captura de tela poderosa e fácil de usar"
EOF

    # Arquivo para pacotes .DEB
    # Nota: A URL pode variar com a arquitetura
    cat << EOF > deb_apps.csv
nome_do_aplicativo,url_do_pacote,descricao
Google Chrome,https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb,"Navegador de internet do Google (somente para amd64)"
EOF

    # Arquivo para Flatpak
    cat << EOF > flatpak_apps.csv
nome_do_aplicativo,id_do_flatpak,descricao
Spotify,com.spotify.Client,"Serviço de streaming de música"
Discord,com.discordapp.Discord,"Plataforma de comunicação por voz, vídeo e texto"
EOF

    # Arquivo para AppImage
    cat << EOF > appimage_apps.csv
nome_do_aplicativo,url_do_appimage,descricao
Kdenlive,https://download.kde.org/stable/kdenlive/24.05/kdenlive-24.05.2-x86_64.AppImage,"Editor de vídeo não-linear profissional"
EOF

    echo -e "${VERDE}Arquivos CSV criados com sucesso: apt_apps.csv, deb_apps.csv, flatpak_apps.csv, appimage_apps.csv${NC}\n"
}

# ===================================================================================
# --- FUNÇÃO PRINCIPAL ---
# ===================================================================================
main() {
    clear
    echo -e "${VERDE}====================================================${NC}"
    echo -e "${VERDE}  Iniciando Script para criacao de arquivos CSV     ${NC}"
    echo -e "${VERDE}====================================================${NC}\n"

    # Etapas de verificação e preparação
    criar_arquivo_csv

    echo -e "${VERDE}====================================================${NC}"
    echo -e "${VERDE}   Script concluído com sucesso!                    ${NC}"
    echo -e "${VERDE}====================================================${NC}"
}

# --- PONTO DE ENTRADA DO SCRIPT ---
main

