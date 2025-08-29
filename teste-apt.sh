#!/bin/bash
apt update && apt upgrade -y
a_csv_file="apt_apps.csv"
echo -e "${AMARELO}--- INICIANDO INSTALAÇÕES VIA APT ---${NC}"

while IFS=, read -r app_name installer_name description || [[ -n "$app_name" ]]; do
    echo -e "${VERDE}Instalando ${app_name} (${description})..."
    apt-get install -y "$installer_name" < /dev/null
    echo -e "${VERDE}${app_name} instalado com sucesso.${NC}"
done < <(tail -n +2 "$a_csv_file")
echo -e "${VERDE}--- INSTALAÇÕES VIA APT CONCLUÍDAS ---${NC}\n"
