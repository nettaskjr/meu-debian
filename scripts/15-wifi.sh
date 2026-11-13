#!/bin/bash
set -e

# =============================================================================
#  wifi.sh - Configuração da placa Wi-Fi USB (TP-Link Archer T2U PLUS)
#
#  FUNÇÃO DESTE SCRIPT:
#  Instala e carrega o driver da placa Wi-Fi USB baseada no chipset RTL8811AU /
#  RTL8821AU (aqui: TP-Link Archer T2U PLUS, USB ID 2357:0120) e, se o
#  NetworkManager estiver ativo, já permite conectar a uma rede Wi-Fi.
#
#  POR QUE É NECESSÁRIO UM DRIVER EXTERNO:
#  O kernel do Debian 13 (6.12) traz os módulos rtw88_8821ce/8821cs/8821cu,
#  mas NÃO traz o rtw88_8821au. O suporte nativo a esse chipset só entrou no
#  kernel 6.14. Em kernels anteriores é preciso usar o driver fora da árvore
#  do morrownr (8821au-20210708), compilado via DKMS para continuar
#  funcionando após cada atualização de kernel.
#
#  O script faz, em ordem:
#   1. Detecta a placa pelo USB ID (suporta os IDs conhecidos do chipset);
#   2. Verifica se o kernel já tem o driver nativo (>= 6.14) e, se tiver,
#      usa apenas ele (sem DKMS);
#   3. Caso contrário, instala as dependências de compilação
#      (build-essential, bc, dkms, git, headers do kernel, libelf-dev,
#      rfkill, iw e nano);
#   4. Clona/atualiza o driver em /usr/local/src/8821au-20210708 e executa
#      o install-driver.sh em modo não interativo (NoPrompt);
#   5. Carrega o módulo 8821au, desbloqueia o Wi-Fi no rfkill e mostra a
#      interface de rede criada;
#   6. Opcionalmente conecta a uma rede Wi-Fi via nmcli (NetworkManager).
#
#  OBSERVAÇÕES IMPORTANTES:
#   - É necessário acesso à internet durante a instalação (use o cabo de rede
#     ou o compartilhamento de rede do celular via USB).
#   - Secure Boot ativo exige assinatura do módulo. O DKMS do Debian costuma
#     assinar automaticamente, mas pode ser necessário reiniciar e cadastrar
#     a chave MOK. O script avisa quando detectar Secure Boot.
#   - Recomenda-se reiniciar ao final para o módulo subir com as opções
#     padrão do arquivo /etc/modprobe.d/8821au.conf.
#   - Placas baseadas em RTL8812AU (outro chipset) usam outro driver; este
#     script não serve para elas.
#
#  USO (execute com sudo):
#     sudo ./scripts/wifi.sh                 # instala o driver e oferece conexão
#     sudo ./scripts/wifi.sh --sem-conexao   # instala o driver sem conectar
#     sudo ./scripts/wifi.sh --status        # mostra o estado atual (sem root)
#     sudo ./scripts/wifi.sh --remover       # remove o driver DKMS
#     sudo ./scripts/wifi.sh --ajuda         # mostra esta ajuda
# =============================================================================

appNome="Wi-Fi USB (RTL8821AU / Archer T2U PLUS)"
DRIVER_REPO="https://github.com/morrownr/8821au-20210708.git"
DRIVER_DIR="/usr/local/src/8821au-20210708"
MODULO_DKMS="8821au"
MODULO_KERNEL="rtw88_8821au"
IDS_SUPORTADOS=(
    "2357:0120" # TP-Link Archer T2U PLUS
    "2357:011e" # TP-Link
    "2357:011f" # TP-Link
    "0bda:0811" # Realtek
    "0bda:0820" # Realtek
    "0bda:0821" # Realtek
    "0bda:0823" # Realtek
    "0bda:8822" # Realtek
    "0bda:a811" # Realtek
    "0411:0242" # Buffalo
    "0411:029b" # Buffalo
    "04bb:0953" # I-O DATA
    "056e:4007" # ELECOM
    "056e:400e" # ELECOM
    "056e:400f" # ELECOM
    "0846:9052" # Netgear
    "0e66:0023" # HAWKING
    "2001:3314" # D-Link
    "2001:3318" # D-Link
    "2019:ab32" # Planex
    "20f4:804b" # TRENDnet
    "3823:6249" # Obihai
    "7392:a811" # Edimax
    "7392:a812" # Edimax
    "7392:a813" # Edimax
    "7392:b611" # Edimax
)

MODO="instalar"
FAZER_CONEXAO="sim"

mostrar_ajuda() {
    cat <<'AJUDA'
USO: sudo ./scripts/wifi.sh [opções]

Instala o driver da placa Wi-Fi USB RTL8811AU/RTL8821AU (TP-Link Archer T2U
PLUS e similares) e, opcionalmente, conecta a uma rede Wi-Fi.

Opções:
  -n, --sem-conexao   Instala o driver sem oferecer conexão Wi-Fi
  -s, --status        Mostra placa, driver, rfkill e interfaces (não precisa root)
  -r, --remover       Remove o driver DKMS instalado
  -h, --ajuda         Mostra esta ajuda

Exemplos:
  sudo ./scripts/wifi.sh
  sudo ./scripts/wifi.sh --sem-conexao
  ./scripts/wifi.sh --status
  sudo ./scripts/wifi.sh --remover

Execute a instalação/remoção com sudo.
AJUDA
}

# --- Argumentos ---
for arg in "$@"; do
    case "$arg" in
        -h|--ajuda)
            mostrar_ajuda
            exit 0
            ;;
        -n|--sem-conexao)
            FAZER_CONEXAO="nao"
            ;;
        -s|--status)
            MODO="status"
            ;;
        -r|--remover)
            MODO="remover"
            ;;
        -*)
            echo "Opção desconhecida: $arg (use --ajuda)"
            exit 1
            ;;
        *)
            echo "Argumento desconhecido: $arg (use --ajuda)"
            exit 1
            ;;
    esac
done

# Lista os adaptadores suportados conectados no momento.
detectar_adaptador() {
    local id encontrados=0

    for id in "${IDS_SUPORTADOS[@]}"; do
        if lsusb -d "$id" >/dev/null 2>&1; then
            lsusb -d "$id" | sed 's/^/   /'
            encontrados=1
        fi
    done

    [ "$encontrados" -eq 1 ]
}

# Retorna a interface de rede criada pelo driver informado (8821au ou
# rtw88_8821au), procurando o vínculo do dispositivo em /sys/class/net.
obter_interface() {
    local driver_alvo="$1" dir nome driver

    for dir in /sys/class/net/*; do
        [ -e "$dir" ] || continue
        nome=$(basename "$dir")
        driver=$(basename "$(readlink -f "$dir/device/driver" 2>/dev/null || true)")
        if [ "$driver" = "$driver_alvo" ]; then
            echo "$nome"
        fi
    done | head -1
}

# Exibe placa, módulos, rfkill e interfaces.
mostrar_status() {
    echo
    echo "=== ➡️ Placa detectada ==="
    if ! detectar_adaptador; then
        echo "   ⚠️  Nenhum adaptador RTL8811AU/RTL8821AU encontrado no USB."
    fi

    echo
    echo "=== ➡️ Módulos carregados ==="
    lsmod | grep -E "(^|_)(${MODULO_DKMS}|${MODULO_KERNEL})( |_)" || echo "   (nenhum driver 8821au carregado)"

    if command -v dkms >/dev/null 2>&1; then
        echo
        echo "=== ➡️ Estado no DKMS ==="
        dkms status | grep -i 8821au || echo "   (nenhum driver DKMS 8821au registrado)"
    fi

    echo
    echo "=== ➡️ rfkill ==="
    if command -v rfkill >/dev/null 2>&1; then
        local saida_rfkill
        saida_rfkill=$(rfkill list wifi 2>/dev/null || true)
        if [ -n "$saida_rfkill" ]; then
            echo "$saida_rfkill" | sed 's/^/   /'
        else
            echo "   (nenhum dispositivo Wi-Fi registrado no rfkill)"
        fi
    else
        echo "   (rfkill não instalado)"
    fi

    echo
    echo "=== ➡️ Interfaces de rede ==="
    ip -br link show | grep -vE "^(lo|docker|veth|br-)" || true

    local iface
    iface=$(obter_interface "$MODULO_DKMS")
    [ -z "$iface" ] && iface=$(obter_interface "$MODULO_KERNEL")
    if [ -n "$iface" ]; then
        echo
        echo "✅ Interface Wi-Fi ativa: $iface"
        if command -v iw >/dev/null 2>&1; then
            iw dev "$iface" link 2>/dev/null || true
        fi
    else
        echo
        echo "⚠️  Nenhuma interface Wi-Fi criada pelo driver 8821au no momento."
    fi
}

# --- Modo status (não exige root) ---
if [ "$MODO" = "status" ]; then
    echo "=============================================="
    echo "  🔎 Status de $appNome"
    echo "=============================================="
    mostrar_status
    exit 0
fi

echo "=============================================="
echo "  🔧 Configuração de $appNome"
echo "=============================================="
echo

if [ "$EUID" -ne 0 ]; then
    echo "❌ Execute como root: sudo bash $0"
    exit 1
fi

# --- Modo remoção -------------------------------------------------------------
if [ "$MODO" = "remover" ]; then
    echo "=== ➡️ Removendo o driver $MODULO_DKMS ==="

    # Descarrega o módulo antes de remover, se estiver em uso.
    modprobe -r "$MODULO_DKMS" 2>/dev/null || true
    modprobe -r "$MODULO_KERNEL" 2>/dev/null || true

    if [ -x "$DRIVER_DIR/remove-driver.sh" ]; then
        (cd "$DRIVER_DIR" && sh ./remove-driver.sh NoPrompt)
    elif [ -n "$(dkms status | grep -i 8821au || true)" ]; then
        dkms remove -m "$MODULO_DKMS" --all
        echo "   ✅ Driver removido do DKMS"
    else
        echo "   ⚠️  Nenhuma instalação do driver $MODULO_DKMS encontrada."
    fi

    echo
    echo "=============================================="
    echo "✅ Remoção de $appNome finalizada!"
    echo "   O diretório $DRIVER_DIR foi mantido (pode ser apagado)."
    echo "   Recomenda-se reiniciar o sistema."
    echo "=============================================="
    exit 0
fi

# --- 1. Detecção da placa -----------------------------------------------------

echo "=== ➡️ Procurando adaptador RTL8811AU/RTL8821AU ==="
if detectar_adaptador; then
    echo "✅ Adaptador encontrado"
else
    echo "⚠️  Nenhum adaptador RTL8811AU/RTL8821AU foi encontrado no USB."
    echo "    Verifique se a placa está bem encaixada (de preferência em uma"
    echo "    porta USB traseira, sem hub/HUB externo)."
    echo
    read -r -p "Continuar mesmo assim? [s/N]: " RESP
    if [ "$RESP" != "s" ] && [ "$RESP" != "S" ]; then
        echo "Cancelado."
        exit 1
    fi
fi

# --- 2. Driver nativo do kernel (>= 6.14) ------------------------------------

echo
echo "=== ➡️ Verificando o kernel atual: $(uname -r) ==="
if modinfo "$MODULO_KERNEL" >/dev/null 2>&1; then
    echo "✅ O kernel já possui o driver nativo $MODULO_KERNEL (kernel >= 6.14)."
    echo "   Não é necessário instalar o driver externo (DKMS)."

    echo "=== ➡️ Carregando o driver nativo e desbloqueando o Wi-Fi ==="
    modprobe "$MODULO_KERNEL"
    command -v rfkill >/dev/null 2>&1 && rfkill unblock wifi || true
    sleep 3

    IFACE=$(obter_interface "$MODULO_KERNEL")
    if [ -n "$IFACE" ]; then
        echo "✅ Interface Wi-Fi criada: $IFACE"
    else
        echo "⚠️  O módulo carregou, mas a interface ainda não apareceu."
        echo "    Se o adaptador foi conectado agora, tente reconectar ou reiniciar."
    fi

    mostrar_status

    echo
    echo "=============================================="
    echo "✅ $appNome pronto (driver nativo do kernel)."
    echo "   Nenhuma alteração permanente foi necessária."
    echo "=============================================="
    exit 0
fi

echo "⚠️  O kernel $(uname -r) não possui $MODULO_KERNEL; será usado o driver DKMS."

# Aviso de Secure Boot (a assinatura de módulos pode ser exigida).
if command -v mokutil >/dev/null 2>&1; then
    if mokutil --sb-state 2>/dev/null | grep -qi enabled; then
        echo
        echo "⚠️  Secure Boot está ATIVO."
        echo "    O DKMS do Debian tenta assinar o módulo automaticamente. Se o"
        echo "    Wi-Fi não funcionar após reiniciar, cadastre a chave MOK com:"
        echo "       sudo mokutil --import /var/lib/dkms/mok.pub"
        echo "    e siga as instruções na tela do firmware no próximo boot."
    fi
fi

# --- 3. Dependências ----------------------------------------------------------

echo
echo "=== ➡️ Instalando dependências de compilação ==="
apt update
apt install -y \
    build-essential bc dkms git libelf-dev rfkill iw nano \
    "linux-headers-$(uname -r)" ||
    apt install -y build-essential bc dkms git libelf-dev rfkill iw nano linux-headers-amd64

echo "✅ Dependências instaladas"

# --- 4. Driver externo (morrownr/8821au) --------------------------------------

echo
echo "=== ➡️ Obtendo o driver $MODULO_DKMS ==="
if [ -d "$DRIVER_DIR/.git" ]; then
    echo "   Diretório já existe; atualizando..."
    git -C "$DRIVER_DIR" pull --ff-only || {
        echo "⚠️  Não foi possível atualizar o repositório; usando a versão local."
    }
else
    echo "   Clonando em $DRIVER_DIR..."
    mkdir -p "$(dirname "$DRIVER_DIR")"
    git clone --depth 1 "$DRIVER_REPO" "$DRIVER_DIR"
fi

# Mostra drivers DKMS de Wi-Fi Realtek já registrados (conflitos comuns).
DKMS_CONFLITOS=$(dkms status | grep -iE "(8812au|8821au|rtl8821)" | grep -viE "$MODULO_DKMS" || true)
if [ -n "$DKMS_CONFLITOS" ]; then
    echo
    echo "⚠️  Outros drivers Realtek de Wi-Fi estão registrados no DKMS:"
    echo "$DKMS_CONFLITOS" | sed 's/^/   /'
    echo "    Drivers concorrentes costumam impedir o funcionamento correto."
    echo "    Recomenda-se removê-los antes de continuar."
fi

echo
echo "=== ➡️ Compilando e instalando o driver (DKMS) ==="
echo "    Isso pode levar alguns minutos..."
(cd "$DRIVER_DIR" && sh ./install-driver.sh NoPrompt)

# --- 5. Carga do módulo e verificação ----------------------------------------

echo
echo "=== ➡️ Carregando o módulo $MODULO_DKMS ==="
modprobe "$MODULO_DKMS" || {
    echo "❌ Falha ao carregar o módulo $MODULO_DKMS."
    echo "   Veja os detalhes com: dmesg | tail -50"
    exit 1
}

echo "=== ➡️ Desbloqueando o Wi-Fi no rfkill ==="
command -v rfkill >/dev/null 2>&1 && rfkill unblock wifi || true
sleep 3

IFACE=$(obter_interface "$MODULO_DKMS")
if [ -n "$IFACE" ]; then
    echo "✅ Interface Wi-Fi criada: $IFACE"
else
    echo "⚠️  A interface ainda não apareceu. Isso é normal antes do primeiro"
    echo "    reinício; reinicie e verifique com: ./scripts/wifi.sh --status"
fi

mostrar_status

# --- 6. Conexão Wi-Fi (opcional) ---------------------------------------------

CONECTOU="nao"
if [ "$FAZER_CONEXAO" = "sim" ] && command -v nmcli >/dev/null 2>&1 &&
    systemctl is-active NetworkManager >/dev/null 2>&1 && [ -n "$IFACE" ]; then

    echo
    echo "=== ➡️ Redes Wi-Fi disponíveis ==="
    nmcli radio wifi on 2>/dev/null || true
    sleep 2
    nmcli -f SSID,SIGNAL,SECURITY device wifi list --rescan yes 2>/dev/null |
        awk 'NR==1 || $1!=""' | sed 's/^/   /' || true

    echo
    read -r -p "Conectar a uma rede Wi-Fi agora? [s/N]: " RESP
    if [ "$RESP" = "s" ] || [ "$RESP" = "S" ]; then
        read -r -p "Nome da rede (SSID): " SSID
        if [ -z "$SSID" ]; then
            echo "⚠️  SSID não informado; conexão ignorada."
        else
            # --ask solicita a senha sem exibi-la na tela (redes abertas não pedem).
            if nmcli device wifi connect "$SSID" --ask; then
                CONECTOU="sim"
                echo "✅ Conectado à rede $SSID"
            else
                echo "❌ Não foi possível conectar à rede $SSID."
                echo "   Confira a senha e tente novamente:"
                echo "   nmcli device wifi connect \"$SSID\" --ask"
            fi
        fi
    fi
fi

# --- 7. Resumo ----------------------------------------------------------------

echo
echo "=============================================="
echo "✅ $appNome finalizado!"
echo
echo "  Placa       : TP-Link Archer T2U PLUS / RTL8821AU (2357:0120)"
echo "  Driver      : $MODULO_DKMS (DKMS, compilado para $(uname -r))"
echo "  Fonte       : $DRIVER_DIR"
echo "  Interface   : ${IFACE:-não criada ainda (reinicie e verifique)}"
[ "$CONECTOU" = "sim" ] && echo "  Conexão     : rede conectada via NetworkManager"
echo
echo "  Próximos passos:"
echo "   1. Recomenda-se reiniciar:  sudo reboot"
echo "   2. Verificar o estado:      ./scripts/wifi.sh --status"
echo "   3. Se a interface não aparecer, veja o log do kernel:"
echo "        dmesg | grep -iE '8821au|rtl8821|usb' | tail -30"
echo "   4. Se o Wi-Fi cair sozinho, teste desativar a economia de energia:"
echo "        sudo nano /etc/modprobe.d/8821au.conf"
echo "        (ajuste rtw_power_mgnt=0 e reinicie)"
echo "   5. Remover o driver depois:  sudo ./scripts/wifi.sh --remover"
echo "=============================================="
