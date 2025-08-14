#/bin/bash

#--------------------------------------TESTES----------------------------------#
# ---- E root
[ $UID -eq "0" ] || { echo "Necessita ser root..."; exit 1; }

# ---- tem internet
goo="http://www.google.com.br/intl/en_com/images/srpr/logo1w.png"
arq=$(basename "$goo")
wget -q $goo && [ -s "$arq" ] && rm "$arq" || { echo "Necessita de internet..."; exit 1; } 

#-------------------------------------FUNCOES----------------------------------#
function doInstalado() {
    app=$1 # aplivativo a ser verificado se esta instalado (1) ou não (0)
    [ $(which $app 2>/dev/null) ] && echo 1 || echo 0
}

function doSeparador() {
    echo ""
    echo "----------------------------"
    echo "$1"
    echo ""
}

function doExecutar() {
    exe=$1 # script a ser executado
    ati=$2 # flag de execucao 1 executa, 0 não executa
    app=$3 # aplicativo que é usado para a execucao do script
    if [ $ati -eq 1 ]; then
        [ "$(doInstalado $app)" -eq "1" ] && echo "Executando.: $exe ..." && sh -c "$exe" && doSeparador
    fi
}

function doInstalar() {
    exe=$1 # script de instalação do $exe
    ati=$2 # flag de execucao 1 executa, 0 não executa
    app=$3 # aplicativo a ser instalado
    api=$4 # aplicativo depois de instalado
    if [ $ati -eq 1 ]; then 
        # alimenta o nome do apl para a funcao que fará o which
        [ "$api" != "$app" ] && apl=$api || apl=$app
        if [ "$(doInstalado $apl)" -eq "1" ]; then
            echo "$app Já instalado" && doSeparador
        else
            sh -c "$exe" && doSeparador
            apt -fy install 
        fi
    fi
}

function doListarUsuarios() {
    usu=""
    for i in $(cat /etc/passwd); do
        uid=$(echo $i | cut -d":" -f3) #id
        uno=$(echo $i | cut -d":" -f1) #nome
        [ $uid -ge "1000" 2>/dev/null ] && [ $uno != "nobody" ] && usu="$usu $uno"
    done
    echo "$usu"
}

function doArquitetura64() {
    # 1 amd64 0, i386
    [[ -n $(uname -a | grep "x86_64") ]] && echo "1" || echo "0"
}

#------------------------------------VARIAVEIS---------------------------------#
# ---- para executar dpkg e adduser, adicione ao PATH (/usr/sbin)

g_arq="/etc/profile.d/path.sh" 
[ -e $g_arq ] && executa=0 || executa=1
# ----
exec="echo PATH=$PATH:/usr/sbin > $g_arq && chmod +x $g_arq"
    doExecutar "$exec" $executa "sh" && source $g_arq

#----------------------------------REPOSITORIOS--------------------------------#
# 0 desligado, 1 ligado
executa=1

if [ $executa -eq 1 ] 
then
    doSeparador "Adicionando repositorios..."
    # ---- apps basicos para os repos
    apt install -y curl ca-certificates gnupg lsb-release

    # ---- adicionando contrib e non-free
    sed -i 's/main/main contrib non-free/' /etc/apt/sources.list

    # ---- virtualbox
    echo "deb http://download.virtualbox.org/virtualbox/debian $(lsb_release -cs) contrib" > /etc/apt/sources.list.d/virtualbox.list
    wget -q https://www.virtualbox.org/download/oracle_vbox_2016.asc -O- | apt-key add - 
    wget -q https://www.virtualbox.org/download/oracle_vbox.asc -O- | apt-key add -

    # ---- brave-browser
    echo "deb [arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main" > /etc/apt/sources.list.d/brave-browser.list
    curl -s https://brave-browser-apt-release.s3.brave.com/brave-core.asc | apt-key --keyring /etc/apt/trusted.gpg.d/brave-browser-release.gpg add -

    # ---- lutris
    echo "deb http://download.opensuse.org/repositories/home:/strycore/Debian_10/ ./" > /etc/apt/sources.list.d/lutris.list
    wget -q https://download.opensuse.org/repositories/home:/strycore/Debian_10/Release.key -O- | sudo apt-key add -

    # ---- insync
    echo "deb http://apt.insync.io/debian $(lsb_release -cs) non-free contrib" > /etc/apt/sources.list.d/insync.list
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys ACCAF35C
    
    # ---- docker
    # colocar o envio do erro para /dev/null
    apt remove docker docker-engine docker.io containerd runc
    # testar se existe o arquivo
    rm "/usr/share/keyrings/docker-archive-keyring.gpg"
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
fi

#-----------------------------------APLICATIVOS--------------------------------#

#------------------------------------------------------------------------------#
# ----                         ---- #
# ---- INSTALAÇÃO COM APT-GET  ---- #
# ----                         ---- #

# 0 desligado, 1 ligado
executa=1

# ---- app base
apps="build-essential g++ wget"                                     #ferramentas base
apps="$apps python3-apt"                                            #para o steam
apps="$apps lolcat"                                                 #cores no shell, utilizado para fetch
apps="$apps figlet"                                                 #gera escritas via terminal
apps="$apps cmake"                                                  #compilador em C
apps="$apps libudev-dev"                                            #biblioteca compartilhada
apps="$apps apt-transport-https software-properties-common"         #apps base 
apps="$apps hwloc"                                                  #Visao de hieraquia da maquina (lstopo, lstopo-no-graphics)
apps="$apps bluetooth bluez bluez-tools blueman"                    #bluetooth $ blueman-manager
apps="$apps rfkill"                                                 #verificar se interface de rede está bloqueada $ rfkill list, $ rfkill unblock bluetooth
apps="$apps progress"                                               #apresenta progresso nos comandos shell ex.: cp e mvP

# ---- drivers
#apps="$apps firmware-atheros"                                      #driver da placa de wifi atheros (DELL Latitude/Vostro)
#apps="$apps firmware-iwlwifi"                                      #driver da placa de wifi/bluetooth (Samsung Book)

# ---- redes                            
apps="$apps net-tools"                                              #(ifconfig entre outros)
apps="$apps iproute2 iproute2-doc"                                  #(comandos de rede tb)
apps="$apps iptraf-ng"                                              #(verificar trafego de rede)
apps="$apps nmap ndiff"                                             #(verificacao de status de rede)
apps="$apps whois"                                                  #identificacao de proprietario de dominio"
apps="$apps filezilla"                                              #cliente ftp
apps="$apps wireshark"                                              #ferramenta de invasao
apps="$apps dnsutils"                                               #informacoes de dns
apps="$apps cntlm"                                                  #conecta em proxy de forma automatica
apps="$apps gufw"                                                   #interface para ufw que por sua vez é interface para iptables
apps="$apps openconnect"                                            #cliente vpn

# ---- dev  
apps="$apps openjdk-17-jdk"                                         #jdk
apps="$apps git"                                                    #repositorio
apps="$apps dialog"                                                 #criacao de telas na linha de comando
apps="$apps shellcheck"                                             #verifica bugs em scripts shell
apps="$apps composer"                                               #framework backend
apps="$apps dia"                                                    #editor de fluxogramas, UML, etc...
apps="$apps recode"                                                 #converte arquivos em diferentes tipos de formatos (UTF8 em ISO8859...) >> $ cat oie.txt | recode html.utf8
apps="$apps python3-pip"                                            #gerenciador de pacotes python       
apps="$apps nodejs"                                                 #framework frontend
apps="$apps npm"                                                    #gerenciador de pacotes do node
apps="$apps php"                                                    #php
apps="$apps docker-ce docker-ce-cli containerd.io"                  #aplicativo de container
apps="$apps docker-compose"                                         #desenvolvimento de rotinas usando docker
apps="$apps postgresql"                                             #postgresql
apps="$apps mariadb-server-10.5"                                    #mysql
apps="$apps umbrello"                                               #diagramcao uml estilo Astha
# instalados via docker
#apps="$apps tomcat9 tomcat9-admin tomcat9-docs tomcat9-examples tomcat9-user" #tomcat
#apps="$apps pgadmin3"                                              #ide para postgresql
#apps="$apps apache2 apache2-utils"                                 #apache e Apache Bench >> $ ab -n 10 [url] >> envia 10 requisicoes para a url informada
#apps="$apps mysql-workbench"                                       #ide para mysql (não está no repo padráo)
#apps="$apps phpmyadmin"                                            #admin para mysql (usando no /home)
#apps="$apps nginx"                                                 #servidor web

# ---- aplicativos
apps="$apps arc arj lhasa unrar-free unace bzip2 gzip unzip"        #compactadores
apps="$apps printer-driver-cups-pdf"                                #impressora PDF
apps="$apps vim"                                                    #vi melhorado
apps="$apps gparted"                                                #editor de partição
apps="$apps htop"                                                   #top melhorado
apps="$apps locate"                                                 #localizacao de arquivos no computador
apps="$apps calibre"                                                #gerenciador de ebook
apps="$apps dconf-editor"                                           #editor de configuração, util para identicar quais as chaves são usadas
apps="$apps terminator"                                             #terminal shell
apps="$apps brave-browser"                                          #navegador brave
apps="$apps telegram-desktop"                                       #cliente official do Telegram
apps="$apps kodi"                                                   #Home Theater
apps="$apps chromium"                                               #navegador open sourcer do projeto chrome
apps="$apps insync"                                                 #sincronizacao com a nuvem (Google drive e One Drive)
apps="$apps insync-nautilus"                                        #plugin nautilus para insync
apps="$apps netselect-apt"                                          #pesquisa qual o melhor mirror para o apt
apps="$apps keepassxc"                                              #gerenciador de senhas
# apps="$apps playonlinux"                                          #front-end para wine

# ---- videos e graficos
apps="$apps openshot"                                               #editor de videos
apps="$apps blender"                                                #editor 3D
apps="$apps vlc"                                                    #player
apps="$apps gimp"                                                   #editor de imagens
apps="$apps darktable"                                              #processador de fotos RAW

# ---- gnome
apps="$apps gnome-tweaks"                                           #ferramentas para gnome
apps="$apps gir1.2-gtop-2.0 gir1.2-nm-1.0 gir1.2-gconf-2.0"         #para extensões do gnome
apps="$apps gnome-shell-extension-system-monitor"                   #base para extensao system monitor
apps="$apps chrome-gnome-shell"                                     #extensoes do shell no chrome

# ---- nautilus
apps="$apps gnome-sushi"                                            #visualizador de arquivos (clique no arqivo e press espaço)
apps="$apps nautilus-admin"                                         #menu de admin no nautilus
apps="$apps nautilus-image-converter"                               #converte e rotaciona imagens
apps="$apps nautilus-sendto"                                        #envia como anexo

# ---- grub
#apps="$apps grub-customizer"                                       #ferramentas para grub (não está no repo padrão)

# ---- mobile
apps="$apps adb"                                                   #ferramentas para android
apps="$apps fastboot"                                              #ferramentas para android

# ---- hardware
apps="$apps inxi"                                                   #informações sobre o hardware
apps="$apps neofetch"                                               #informações sobre o hardware/software
apps="$apps lshw"                                                   #mostra informações do hardware (Ex.: para ver video digite # lshw -C video)
#apps="$apps glances"                                               #mostra informações de processos - obsoleto

# ---- virtualização
apps="$apps virtualbox-7.0"                                         #maquina virtual

# ---- aws
apps="$apps s3fs"                                                   #monta particao AWS s3
apps="$apps awscli"                                                 #cliente aws para linha de comando

# --- conky
apps="$apps lua5.3 dos2unix"                                        #para o conky
apps="$apps conky-all"                                              #conky

# --- fontes themes and icons
apps="$apps ttf-aenigma"                                            #conjunto de 465 fontes
apps="$apps faenza-icon-theme"                                      #icones faenza
apps="$apps materia-gtk-theme"                                      #tema materia
apps="$apps deepin-icon-theme"                                      #icones do deepin

# --- games
#apps="$apps flightgear"                                            #flightgear simulator
#apps="$apps lutris"                                                #player de games

[ $executa -eq 1 ] && doSeparador "Instalando aplicativos..." && apt update && apt dist-upgrade -y && apt install -y $apps && apt -y autoremove

# ----                      ---- #
# ----  OUTRAS INSTALAÇÕES  ---- #
# ----                      ---- #

# 0 desligado, 1 ligado
executa=1

# ----  Extension Pack of Virtualbox  ---- #
# [ ] atualiza automaticamente
if [ $executa -eq 1 ] 
then
    end="http://download.virtualbox.org/virtualbox/$(VBoxManage -v | cut -d r -f1)/Oracle_VM_VirtualBox_Extension_Pack-$(VBoxManage -v | cut -d r -f1)-$(VBoxManage -v | cut -d r -f2).vbox-extpack"
    arq=$(basename "$end")
    sha256='33d7284dc4a0ece381196fda3cfe2ed0e1e8e7ed7f27b9a9ebc4ee22e24bd23c' # sha256 do arquivo de licensa
    # ----
    wget -c -P "/tmp" "$end"
    exec="VBoxManage extpack install --replace --accept-license=$sha256 /tmp/$arq" # instala
        doExecutar "$exec" $executa "virtualbox"
fi

# # ----  Google Chrome  ---- #
# # [x] atualiza automaticamente
if [ $executa -eq 1 ] 
then
    prg="google-chrome"
    end="https://dl.google.com/linux/direct"
    a64="google-chrome-stable_current_amd64.deb"
    a86="google-chrome-stable_current_i386.deb"
    [ "$(doArquitetura64)" -eq "1" ] && arq="$a64" || arq="$a86"
    # ----
    wget -c -P "/tmp" "$end/$arq"
    exec="dpkg -i /tmp/$arq"
        doInstalar "$exec" $executa "$prg" "$prg"
fi

# ----  AWS Elastic Beanstalk cliente  ---- #
# [ ] atualiza automaticamente
if [ $executa -eq 1 ] 
then
    prg="awsebcli"
    # ----
    exec="pip install $prg --upgrade --user"
        doInstalar "$exec" $executa "$prg" "eb"
fi

# ----  Teams  ---- #
# [x] atualiza automaticamente
if [ $executa -eq 1 ] 
then
    vs="1.5.00.23861_amd64"
    prg="teams"
    end="https://packages.microsoft.com/repos/ms-teams/pool/main/t/teams"
    arq="${prg}_${vs}.deb"
    # ----
    wget -c -P "/tmp" "$end/$arq"
    exec="dpkg -i /tmp/$arq"
        doInstalar "$exec" $executa "$prg" "$prg"
fi

# ----  Skype  ---- #
# [ ] atualiza automaticamente
#if [ $executa -eq 1 ] 
#then
#    vs="latest"
#    prg="skype"
#    end="https://repo.skype.com/${vs}"
#    arq="${prg}forlinux-64.deb"
#    # ----
#    wget -c -P "/tmp" "$end/$arq"
#    exec="dpkg -i /tmp/$arq"
#        doInstalar "$exec" $executa "$prg" "$prg"
#fi

# ---- Terraform ---- #
# [ ] atualiza automaticamente
if [ $executa -eq 1 ] 
then
    vs="$(curl -s https://api.github.com/repos/hashicorp/terraform/releases/latest | grep tag_name | cut -d: -f2 | tr -d \"\,\v | awk '{$1=$1};1')"
    prg="terraform"
    end="https://releases.hashicorp.com/${prg}/${vs}"
    arq="${prg}_${vs}_linux_amd64.zip"
    # ----
    wget -c -P "/tmp" "$end/$arq"
    exec="unzip /tmp/${arq} && mv ${prg} /usr/local/bin"
        doInstalar "$exec" $executa "$prg" "$prg"
fi

## ---- Slack ---- #
## [x] atualiza automaticamente
#if [ $executa -eq 1 ] 
#then
#    vs="4.8.0-amd64"
#    prg="slack"
#    end="https://downloads.slack-edge.com/linux_releases"
#    arq="${prg}-desktop-${vs}.deb"
#    # ----
#    wget -c -P "/tmp" "$end/$arq"
#    exec="dpkg -i /tmp/$arq"
#        doInstalar "$exec" $executa "$prg" "$prg"
#fi

# ---- DBeaver ---- #
# [ ] atualiza automaticamente
if [ $executa -eq 1 ] 
then
    vs="22.2.5"
    prg="dbeaver"
    end="https://dbeaver.io/files/${vs}"
    arq="${prg}-ce_${vs}_amd64.deb"
    # ----
    wget -c -P "/tmp" "$end/$arq"
    exec="dpkg -i /tmp/$arq"
        doInstalar "$exec" $executa "$prg" "$prg"
fi

# ---- rpi Imager ---- #
# [ ] atualiza automaticamente
if [ $executa -eq 1 ] 
then
    vs="1.7.3"
    prg="Rpi Imager"
    end="https://downloads.raspberrypi.org/imager"
    arq="imager_${vs}_amd64.deb"
    # ----
    wget -c -P "/tmp" "$end/$arq"
    exec="dpkg -i /tmp/$arq"
        doInstalar "$exec" $executa "$prg" "$prg"
fi

## ---- Evernote Client ---- #
## [ ] atualiza automaticamente
#if [ $executa -eq 1 ] 
#then
#    vs="10.7.6"
#    prg="evernote-client"
#    end="https://cdn1.evernote.com/boron/linux/builds/"
#    arq="Evernote-${vs}-linux-ddl-ga-2321.deb"
#    # ----
#    wget -c -P "/tmp" "$end/$arq"
#    exec="dpkg -i /tmp/$arq"
#        doInstalar "$exec" $executa "$prg" "$prg"
#fi

#---------------------------------------EXTRAS---------------------------------#

# 0 desligado, 1 ligado
executa=1

# ---- updatedb
exec="updatedb" #atualiza base do locate
# ----
    doExecutar "$exec" $executa "locate"

# ---- Addicionar nos grupos
for i in $(doListarUsuarios); do
    exec="adduser $i vboxusers" # VirtuaBox
        doExecutar "$exec" $executa "virtualbox"
    exec="adduser $i sudo" # Sudo
        doExecutar "$exec" $executa "sudo"
    exec="adduser $i docker" # docker
        doExecutar "$exec" $executa "docker"
done

# ---- coloca neofetch para inciar
arq="/etc/profile.d/mymotd.sh"
# ----
exec="echo "neofetch" > $arq && chmod +x $arq"
    doExecutar "$exec" $executa "neofetch"

# # ---- pesquisa de mirror mais rapido
# exec="netselect-apt"
# # ----
#     doExecutar "$exec" $executa "apt"
#     # fazer o processo de levar o arquivo gerado para /etc/apt/source.list e
#     #   e inserir non-free ao final de cada linha

# ---- ultima atualizacao, caso alguma versao esteja antiga obrigatório
apt update && apt dist-upgrade -y && apt autoremove && apt -f install -y
