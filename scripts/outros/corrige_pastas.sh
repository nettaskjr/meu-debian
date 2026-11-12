#!/bin/bash

PASTA_ORIGEM= "/mnt/FILE_SERVER/Insync/nestor.junior@gmail.com/Google Drive" # DESKTOP
#PASTA_ORIGEM="/home/nestor/Insync/nestor.junior@gmail.com/Google Drive" # NOTEBOOK
PASTAS=("AppImages" "Backups" "Documentos" "Downloads" "Imagens" "Modelos" "Músicas" "Público" "Vídeos")

for pasta in "${PASTAS[@]}"; do
   DESTINO="$HOME/$pasta"
   ORIGEM="$PASTA_ORIGEM/$pasta"

   if [ -L "$DESTINO" ]; then
   	rm "$DESTINO"
   elif [ -d "$DESTINO" ]; then
   	mv "$DESTINO" "$DESTINO.old"
   fi
   
   echo "Criando link simbólico de $ORIGEM para $DESTINO"

   ln -s "$ORIGEM" "$DESTINO"
   
done
