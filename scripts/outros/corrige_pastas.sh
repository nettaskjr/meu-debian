#!/bin/bash

#PASTA_ORIGEM= "/mnt/FILE_SERVER/Insync/nettask@hotmail.com/OneDrive/Modelos/" # DESKTOP
PASTA_ORIGEM="/home/nestor/Insync/nettask@hotmail.com/OneDrive/" # NOTEBOOK
PASTAS=("Documentos" "Imagens" "Modelos" "Músicas" "Público" "Vídeos" "Backups")

for pasta in "${PASTAS[@]}"; do
   DESTINO="$HOME/$pasta"
   ORIGEM="$PASTA_ORIGEM/$pasta"

   if [ -L "$DESTINO" ]; then
   	rm "$DESTINO"
   elif [ -d "$DESTINO" ]; then
   	mv "$DESTINO" "$DESTINO.old"
   fi
   
   ln -s "$ORIGEM" "$DESTINO"
   
done
