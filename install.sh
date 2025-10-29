#/bin/bash

rm meu-debian.sh
rm *.csv

wget https://raw.githubusercontent.com/nettaskjr/meudebian/refs/heads/main/appimage_apps.csv
wget https://raw.githubusercontent.com/nettaskjr/meudebian/refs/heads/main/apt_apps.csv
wget https://raw.githubusercontent.com/nettaskjr/meudebian/refs/heads/main/deb_apps.csv
wget https://raw.githubusercontent.com/nettaskjr/meudebian/refs/heads/main/flatpak_apps.csv
wget https://raw.githubusercontent.com/nettaskjr/meudebian/refs/heads/main/meu-debian.sh && chmod +x meu-debian.sh