#/bin/bash

rm meudebian.sh
rm teste-apt.sh
rm *.csv

#curl -L -o appimage_apps.csv https://raw.githubusercontent.com/nettaskjr/meudebian/refs/heads/main/appimage_apps.csv && chmod +x appimage_apps.csv
#curl -L -o apt_apps.csv https://raw.githubusercontent.com/nettaskjr/meudebian/refs/heads/main/apt_apps.csv && chmod +x apt_apps.csv
#curl -L -o deb_apps.csv https://raw.githubusercontent.com/nettaskjr/meudebian/refs/heads/main/deb_apps.csv && chmod +x deb_apps.csv
#curl -L -o flatpak_apps.csv https://raw.githubusercontent.com/nettaskjr/meudebian/refs/heads/main/flatpak_apps.csv && chmod +x flatpak_apps.csv
#curl -L -o meudebian.sh https://raw.githubusercontent.com/nettaskjr/meudebian/refs/heads/main/meudebian.sh && chmod +x meudebian.sh
#curl -L -o teste-apt.sh https://raw.githubusercontent.com/nettaskjr/meudebian/refs/heads/main/teste-apt.sh && chmod +x teste-apt.sh

wget https://raw.githubusercontent.com/nettaskjr/meudebian/refs/heads/main/appimage_apps.csv
wget https://raw.githubusercontent.com/nettaskjr/meudebian/refs/heads/main/apt_apps.csv
wget https://raw.githubusercontent.com/nettaskjr/meudebian/refs/heads/main/deb_apps.csv
wget csv https://raw.githubusercontent.com/nettaskjr/meudebian/refs/heads/main/flatpak_apps.csv
wget https://raw.githubusercontent.com/nettaskjr/meudebian/refs/heads/main/meudebian.sh
wget https://raw.githubusercontent.com/nettaskjr/meudebian/refs/heads/main/teste-apt.sh