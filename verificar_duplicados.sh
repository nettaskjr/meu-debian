#!/bin/bash

# ===================================================================================
#
#   SCRIPT PARA VERIFICAR APLICATIVOS DUPLICADOS NOS ARQUIVOS CSV
#
#   Autor: netTask and Gemini
#   Versão: 1.0
#
# ===================================================================================

# --- VARIÁVEIS DE COR ---
VERDE='\033[0;32m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
NC='\033[0m' # Sem Cor

echo -e "${AMARELO}Verificando aplicativos duplicados nos arquivos .csv...${NC}"

ALL_APPS=$(for file in *_apps.csv; do [ -f "$file" ] && tail -n +2 "$file" | cut -d, -f1; done)
DUPLICATES=$(echo "$ALL_APPS" | sort | uniq -d)

if [ -z "$DUPLICATES" ]; then
    echo -e "${VERDE}Nenhum aplicativo duplicado encontrado.${NC}"
else
    echo -e "${VERMELHO}AVISO: Foram encontrados os seguintes aplicativos duplicados:${NC}"
    echo "$DUPLICATES" | while read -r app; do
        echo -e "\n- ${AMARELO}${app}${NC} encontrado nos arquivos:"
        grep -l "^${app}," *_apps.csv | sed 's/^/  - /'
    done
fi
