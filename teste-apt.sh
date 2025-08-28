#!/bin/bash
apt update && apt upgrade -y
local a_csv_file="apt_apps.csv"
echo -e "${AMARELO}--- INICIANDO INSTALAÇÕES VIA APT ---${NC}"
tail -n +2 "$a_csv_file" | while IFS=, read -r app_name installer_name description; do
    echo -e "${VERDE}Instalando ${app_name} (${description})..."
    apt-get install -y "$installer_name"
    echo -e "${VERDE}${app_name} instalado com sucesso.${NC}"
done
echo -e "${VERDE}--- INSTALAÇÕES VIA APT CONCLUÍDAS ---${NC}\n"