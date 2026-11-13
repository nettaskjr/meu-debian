#!/bin/bash
set -e

# =============================================================================
#  14-nvidia.sh - Instalação e configuração do driver NVIDIA proprietário
#
#  FUNÇÃO DESTE SCRIPT:
#  Instala o driver oficial da NVIDIA no Debian, substituindo o driver livre
#  nouveau, e deixa a configuração pronta para Xorg e Wayland (GNOME).
#  Testado neste computador com a placa:
#     NVIDIA Corporation TU116 [GeForce GTX 1650 SUPER] [10de:2187]
#     Debian 13 (trixie) - driver disponível: 550.163.01
#
#  O que este script faz:
#   1. Detecta a GPU NVIDIA e mostra o modelo;
#   2. Verifica Secure Boot (se estiver ativo, avisa sobre assinatura/MOK);
#   3. Atualiza os índices do APT e confere se os repositórios têm non-free;
#   4. Instala o linux-headers do kernel atual (necessário para o DKMS);
#   5. Usa o nvidia-detect para confirmar qual pacote é recomendado;
#   6. Instala nvidia-driver, nvidia-settings e firmware-misc-nonfree;
#   7. Cria /etc/modprobe.d/99-nvidia-modeset.conf com nvidia-drm.modeset=1
#      (KMS necessário para Wayland/GNOME);
#   8. Regera o initramfs e confere o módulo no DKMS;
#   9. Mostra um resumo e pede para reiniciar.
#
#  Uso:
#    ./scripts/14-nvidia.sh             # instala/configura o driver
#    ./scripts/14-nvidia.sh --status    # mostra a situação atual
#    ./scripts/14-nvidia.sh --remover   # remove o driver e volta ao nouveau
#    ./scripts/14-nvidia.sh --ajuda     # mostra esta ajuda
#
#  Pode ser executado como usuário comum: o script pede sudo sozinho.
#  É NECESSÁRIO REINICIAR ao final para o driver entrar em uso.
# =============================================================================

appNome="Driver NVIDIA"
MODO="instalar"

ARQUIVO_MODESET="/etc/modprobe.d/99-nvidia-modeset.conf"
PACOTES_BASE=("nvidia-driver" "nvidia-settings" "firmware-misc-nonfree")

mostrar_ajuda() {
    cat << 'AJUDA'
USO: ./scripts/14-nvidia.sh [opções]

Instala e configura o driver proprietário da NVIDIA no Debian. Ao final é
necessário reiniciar para que o driver substitua o nouveau.

Opções:
  (sem opção)     Instala ou atualiza o driver NVIDIA
  -s, --status    Mostra GPU, driver em uso, pacotes, DKMS e nvidia-smi
  -r, --remover   Remove o driver NVIDIA e volta ao driver livre nouveau
  -h, --ajuda     Mostra esta ajuda

Observações:
  - O script pede sudo automaticamente, se necessário.
  - Os repositórios precisam ter os componentes contrib, non-free e
    non-free-firmware habilitados.
  - Com Secure Boot ativo, o módulo do DKMS pode precisar de assinatura/MOK.
  - Wayland/GNOME é configurado com nvidia-drm.modeset=1.
  - Não reinicie o computador no meio da instalação.
AJUDA
}

# -----------------------------------------------------------------------------
# Verifica se existe uma GPU NVIDIA no sistema.
# -----------------------------------------------------------------------------
verificar_gpu() {
    local gpu

    if ! command -v lspci >/dev/null 2>&1; then
        echo "=== ➡️ Instalando pciutils (necessário para detectar a GPU) ==="
        apt-get update
        apt-get install -y pciutils
    fi

    gpu=$(lspci -nn 2>/dev/null | grep -Ei '(vga|3d|display).*\[10de:' | head -n1 || true)
    if [ -z "$gpu" ]; then
        echo "❌ Nenhuma GPU NVIDIA foi detectada neste computador."
        exit 1
    fi

    echo "=== ➡️ GPU NVIDIA detectada: ==="
    echo "   $gpu"
}

# -----------------------------------------------------------------------------
# Avisa sobre Secure Boot. Com ele ativo, o módulo compilado pelo DKMS precisa
# estar assinado e cadastrado no MOK, senão o driver não carrega no boot.
# -----------------------------------------------------------------------------
verificar_secure_boot() {
    local estado

    if ! command -v mokutil >/dev/null 2>&1; then
        echo "=== ⚠️ mokutil não instalado; não foi possível verificar o Secure Boot ==="
        return
    fi

    estado=$(mokutil --sb-state 2>/dev/null || true)
    if grep -qi 'SecureBoot enabled' <<< "$estado"; then
        echo "=== ⚠️ Secure Boot está ATIVO ==="
        echo "    O módulo da NVIDIA pode não carregar até ser assinado/cadastrado."
        echo "    Se o driver não funcionar após reiniciar, consulte a seção"
        echo "    'Secure Boot' do Debian Wiki ou desative o Secure Boot na BIOS."
        echo
    else
        echo "=== ✅ Secure Boot desativado ou sem suporte ==="
    fi
}

# -----------------------------------------------------------------------------
# Confere se o pacote nvidia-driver está disponível nos repositórios.
# -----------------------------------------------------------------------------
verificar_repositorio() {
    local candidato

    candidato=$(LC_ALL=C apt-cache policy nvidia-driver 2>/dev/null |
        awk '/Candidate:/ {print $2; exit}')

    if [ -z "$candidato" ] || [ "$candidato" = "(none)" ]; then
        echo "❌ O pacote nvidia-driver não está disponível no APT."
        echo
        echo "   Habilite os componentes contrib, non-free e non-free-firmware."
        echo "   Exemplo de linha no /etc/apt/sources.list:"
        echo "   deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware"
        echo
        echo "   Depois execute: sudo apt update"
        exit 1
    fi

    echo "=== ✅ Versão disponível do driver: $candidato ==="
}

# -----------------------------------------------------------------------------
# Cria o arquivo de opções do módulo nvidia-drm. O modeset=1 é necessário para
# Wayland/GNOME e também melhora a integração com Xorg.
# -----------------------------------------------------------------------------
configurar_modeset() {
    if [ -f "$ARQUIVO_MODESET" ] &&
       grep -q '^options nvidia-drm modeset=1' "$ARQUIVO_MODESET"; then
        echo "=== ✅ KMS da NVIDIA já está configurado em $ARQUIVO_MODESET ==="
        return
    fi

    echo "=== ➡️ Configurando nvidia-drm.modeset=1 (Wayland/GNOME) ==="
    cat > "$ARQUIVO_MODESET" << 'EOF'
# Gerado por meu-debian/scripts/14-nvidia.sh - não edite manualmente.
# Habilita o Kernel Mode Setting (KMS) do driver NVIDIA, necessário para
# Wayland (GNOME) e para o funcionamento correto do Xorg.
options nvidia-drm modeset=1
EOF
    echo "=== ✅ Configuração criada em $ARQUIVO_MODESET ==="
}

# -----------------------------------------------------------------------------
# Confere se o nouveau foi bloqueado pelo pacote da NVIDIA.
# -----------------------------------------------------------------------------
verificar_blacklist_nouveau() {
    if [ -e /etc/modprobe.d/nvidia-blacklists-nouveau.conf ]; then
        echo "=== ✅ Nouveau bloqueado pelo pacote da NVIDIA ==="
    else
        echo "=== ⚠️ Arquivo de bloqueio do nouveau não encontrado ==="
        echo "    O pacote nvidia-alternative deveria tê-lo criado."
        echo "    Se o nouveau continuar em uso após reiniciar, verifique:"
        echo "    /etc/modprobe.d/nvidia-blacklists-nouveau.conf"
    fi
}

# -----------------------------------------------------------------------------
# Instala o driver.
# -----------------------------------------------------------------------------
instalar_driver() {
    local candidato saida headers
    local pacotes=()

    echo "=== ➡️ Verificando a GPU ==="
    verificar_gpu
    echo

    echo "=== ➡️ Verificando Secure Boot ==="
    verificar_secure_boot
    echo

    echo "=== ➡️ Atualizando a lista de pacotes (apt update) ==="
    apt-get update
    echo

    verificar_repositorio
    echo

    echo "=== ➡️ Instalando nvidia-detect para confirmar o driver correto ==="
    apt-get install -y nvidia-detect
    saida=$(nvidia-detect 2>&1 || true)
    echo "$saida"
    echo

    if ! grep -q 'nvidia-driver' <<< "$saida"; then
        echo "❌ O nvidia-detect não recomendou o pacote nvidia-driver."
        echo "   A placa pode precisar de um driver legado ou de um kernel mais novo."
        echo "   Nenhuma alteração foi feita."
        exit 1
    fi

    pacotes=("${PACOTES_BASE[@]}")

    # O DKMS precisa dos headers do kernel que está rodando agora.
    headers="linux-headers-$(uname -r)"
    if apt-cache show "$headers" >/dev/null 2>&1; then
        pacotes+=("$headers")
    else
        pacotes+=("linux-headers-amd64")
    fi

    echo "=== ➡️ Pacotes que serão instalados: ==="
    printf '   %s\n' "${pacotes[@]}"
    echo

    echo "=== ➡️ Instalando o driver NVIDIA (pode demorar alguns minutos) ==="
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${pacotes[@]}"
    echo

    configurar_modeset
    echo

    echo "=== ➡️ Regerando o initramfs ==="
    update-initramfs -u -k all
    echo

    echo "=== ➡️ Verificando o módulo no DKMS ==="
    if command -v dkms >/dev/null 2>&1; then
        dkms status | grep -i nvidia || echo "   (nenhum módulo NVIDIA listado no DKMS)"
    fi
    echo

    verificar_blacklist_nouveau

    echo
    echo "=============================================="
    echo "✅ $appNome instalado!"
    echo
    echo "  É NECESSÁRIO REINICIAR para o driver entrar em uso:"
    echo "     sudo reboot"
    echo
    echo "  Depois do boot, confira com:"
    echo "     ./scripts/14-nvidia.sh --status"
    echo "     nvidia-smi"
    echo "=============================================="
}

# -----------------------------------------------------------------------------
# Remove os pacotes da NVIDIA e restaura o uso do nouveau após reiniciar.
# -----------------------------------------------------------------------------
remover_driver() {
    local resposta
    local pacotes=()

    echo "=== ⚠️ Esta operação remove o driver NVIDIA e os pacotes relacionados. ==="
    read -r -p "Confirmar remoção? [s/N] " resposta || resposta=""
    if ! [[ "$resposta" =~ ^[sS]$ ]]; then
        echo "=== Operação cancelada ==="
        exit 0
    fi
    echo

    mapfile -t pacotes < <(
        dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package}\n' 2>/dev/null |
            awk '$1 == "ii" && (
                $2 ~ /^nvidia-/ ||
                $2 ~ /^libnvidia-/ ||
                $2 ~ /^libcuda/ ||
                $2 ~ /^libnvcuvid/ ||
                $2 ~ /^libglx-nvidia/ ||
                $2 ~ /^libegl-nvidia/ ||
                $2 ~ /^libgles-nvidia/ ||
                $2 ~ /^libgl1-nvidia/ ||
                $2 == "xserver-xorg-video-nvidia"
            ) {print $2}'
    )

    if [ "${#pacotes[@]}" -eq 0 ]; then
        echo "=== ⚠️ Nenhum pacote NVIDIA instalado; nada a remover ==="
    else
        echo "=== ➡️ Pacotes que serão removidos: ==="
        printf '   %s\n' "${pacotes[@]}"
        echo
        apt-get purge -y "${pacotes[@]}"
        apt-get autoremove -y
    fi

    if [ -f "$ARQUIVO_MODESET" ] &&
       grep -q 'meu-debian/scripts/14-nvidia.sh' "$ARQUIVO_MODESET"; then
        rm -f "$ARQUIVO_MODESET"
        echo "=== ✅ Removido $ARQUIVO_MODESET ==="
    fi

    echo "=== ➡️ Regerando o initramfs ==="
    update-initramfs -u -k all

    echo
    echo "=============================================="
    echo "✅ $appNome removido!"
    echo
    echo "  Reinicie para o driver livre nouveau voltar a ser usado:"
    echo "     sudo reboot"
    echo "=============================================="
}

# -----------------------------------------------------------------------------
# Mostra o estado atual da GPU e do driver.
# -----------------------------------------------------------------------------
mostrar_status() {
    echo "=============================================="
    echo "  🔧 $appNome - Status"
    echo "=============================================="
    echo

    echo "=== ➡️ Placa de vídeo ==="
    lspci -nn 2>/dev/null | grep -Ei '(vga|3d|display)' || echo "   (não foi possível consultar o lspci)"
    echo

    echo "=== ➡️ Driver de kernel em uso ==="
    lspci -k 2>/dev/null | grep -A3 -Ei '(vga|3d|display)' || true
    echo

    echo "=== ➡️ Pacotes NVIDIA instalados ==="
    dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package} ${Version}\n' 2>/dev/null |
        awk '$1 == "ii" && $2 ~ /nvidia/ {print "   " $2 " " $3}' || true
    echo

    echo "=== ➡️ Módulos no DKMS ==="
    if command -v dkms >/dev/null 2>&1; then
        dkms status 2>/dev/null | grep -i nvidia || echo "   (nenhum módulo NVIDIA listado)"
    else
        echo "   (dkms não instalado)"
    fi
    echo

    echo "=== ➡️ nvidia-smi ==="
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi 2>&1 || echo "   (nvidia-smi não respondeu; reinicie se acabou de instalar)"
    else
        echo "   (nvidia-smi não encontrado; driver proprietário não instalado)"
    fi
    echo

    echo "=== ➡️ Secure Boot ==="
    if command -v mokutil >/dev/null 2>&1; then
        mokutil --sb-state 2>&1 || true
    else
        echo "   (mokutil não instalado)"
    fi
    echo

    echo "=== ➡️ Configuração de KMS ==="
    if [ -f "$ARQUIVO_MODESET" ]; then
        echo "   $ARQUIVO_MODESET:"
        sed 's/^/   /' "$ARQUIVO_MODESET"
    else
        echo "   (arquivo $ARQUIVO_MODESET não encontrado)"
    fi
}

# =============================================================================
# Execução
# =============================================================================

case "${1:-}" in
    "")
        MODO="instalar"
        ;;
    -s|--status)
        MODO="status"
        ;;
    -r|--remover)
        MODO="remover"
        ;;
    -h|--ajuda|--help)
        mostrar_ajuda
        exit 0
        ;;
    *)
        echo "❌ Opção inválida: $1"
        echo
        mostrar_ajuda
        exit 1
        ;;
esac

# O status não precisa de root e deve rodar como o usuário atual.
if [ "$MODO" = "status" ]; then
    mostrar_status
    exit 0
fi

# Instalação e remoção alteram o sistema: eleva privilégios se necessário.
if [ "$(id -u)" -ne 0 ]; then
    echo "=== ➡️ Elevando privilégios com sudo ==="
    exec sudo bash "$(readlink -f "$0")" "$@"
fi

echo "=============================================="
echo "  🔧 $appNome"
echo "=============================================="
echo

if [ "$MODO" = "remover" ]; then
    remover_driver
else
    instalar_driver
fi
