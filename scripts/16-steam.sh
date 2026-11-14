#!/bin/bash
set -euo pipefail

# =============================================================================
#  16-steam.sh - Instalação do Steam OFICIAL (pacote .deb), sem Flatpak
#
#  FUNÇÃO DESTE SCRIPT:
#  Instala o cliente Steam pelo método oficial da Valve no Debian, usando o
#  pacote steam-installer do repositório contrib. É a alternativa ao Flatpak,
#  que não consegue adicionar bibliotecas em discos fora do $HOME
#  (ex.: /mnt/GAMES) por limitação do sandbox.
#
#  O que o script faz:
#   1. Habilita a arquitetura i386 (necessária para steam-libs-i386);
#   2. Confere se o pacote steam-installer está disponível (contrib habilitado);
#   3. Instala steam-installer e steam-devices;
#   4. Opcionalmente remove o Steam Flatpak (--remover-flatpak), preservando
#      a pasta ~/.var/app/com.valvesoftware.Steam como backup;
#   5. Confere se /mnt/GAMES está montado com escrita (biblioteca de jogos);
#   6. Mostra o resultado e os próximos passos.
#
#  Uso:
#    ./scripts/16-steam.sh                    # instala o Steam oficial
#    ./scripts/16-steam.sh --remover-flatpak  # instala e remove o Flatpak
#    ./scripts/16-steam.sh --ajuda            # mostra a ajuda
#
#  Pode ser executado como usuário comum: o script pede sudo sozinho.
# =============================================================================

appNome="Steam oficial (pacote .deb)"

PACOTES=(steam-installer steam-devices)
FLATPAK_ID="com.valvesoftware.Steam"
PONTO_JOGOS="/mnt/GAMES"

REMOVER_FLATPAK="nao"

mostrar_ajuda() {
    cat << 'AJUDA'
USO: ./scripts/16-steam.sh [opções]

Instala o Steam pelo método oficial (pacote steam-installer) em vez do Flatpak.

Opções:
  (sem opção)          Instala/atualiza o Steam oficial e as dependências
  --remover-flatpak    Também desinstala o com.valvesoftware.Steam do Flatpak
  -h, --ajuda          Mostra esta ajuda

Observações:
  - Habilita a arquitetura i386, exigida pelo steam-libs-i386.
  - Requer o componente 'contrib' habilitado no /etc/apt/sources.list.
  - O cliente é baixado na primeira execução de 'steam' (por usuário, sem sudo).
  - Ao remover o Flatpak, a pasta ~/.var/app/com.valvesoftware.Steam é mantida.
AJUDA
}

# -----------------------------------------------------------------------------
# Confere se o sistema é Debian-like e se o apt está disponível.
# -----------------------------------------------------------------------------
verificar_debian() {
    if [ ! -f /etc/debian_version ]; then
        echo "❌ Este script é para Debian. Sistema diferente detectado."
        exit 1
    fi
    if ! command -v apt-get >/dev/null 2>&1; then
        echo "❌ apt-get não encontrado."
        exit 1
    fi
    echo "=== ✅ Debian detectado: $(grep -m1 '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"') ==="
}

# -----------------------------------------------------------------------------
# Habilita i386, que o steam-libs-i386 exige. Idempotente.
# -----------------------------------------------------------------------------
habilitar_i386() {
    if dpkg --print-foreign-architectures | grep -qx i386; then
        echo "=== ✅ Arquitetura i386 já habilitada ==="
    else
        echo "=== ➡️ Habilitando arquitetura i386 (necessária para o Steam) ==="
        dpkg --add-architecture i386
    fi
    echo "=== ➡️ Atualizando a lista de pacotes ==="
    apt-get update
}

# -----------------------------------------------------------------------------
# Garante que o pacote existe nos repositórios (componente contrib).
# -----------------------------------------------------------------------------
verificar_repositorio() {
    local candidato

    if ! apt-cache show steam-installer >/dev/null 2>&1; then
        echo "❌ Pacote 'steam-installer' não encontrado."
        echo "   Habilite o componente 'contrib' no Debian e rode 'apt update'."
        echo "   Exemplo de linha no /etc/apt/sources.list:"
        echo "   deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware"
        exit 1
    fi

    candidato=$(apt-cache policy steam-installer | awk '/^[[:space:]]+(Candidato|Candidate):/ {print $2; exit}')
    echo "=== ✅ steam-installer disponível: ${candidato:-desconhecida} ==="
}

# -----------------------------------------------------------------------------
# Instala (ou atualiza) o Steam oficial e os dispositivos de controle.
# -----------------------------------------------------------------------------
instalar_steam() {
    echo "=== ➡️ Instalando: ${PACOTES[*]} ==="
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${PACOTES[@]}"
    echo "=== ✅ Pacotes instalados ==="
}

# -----------------------------------------------------------------------------
# Remove o Steam Flatpak, preservando os dados em ~/.var/app como backup.
# -----------------------------------------------------------------------------
remover_flatpak() {
    local usuario dados

    usuario="${SUDO_USER:-${USER:-}}"

    if ! command -v flatpak >/dev/null 2>&1; then
        echo "=== ℹ️ Flatpak não instalado; nada a remover ==="
        return
    fi

    if ! flatpak list --app --columns=application 2>/dev/null | grep -qx "$FLATPAK_ID"; then
        echo "=== ℹ️ Steam Flatpak não está instalado; nada a remover ==="
        return
    fi

    echo "=== ➡️ Removendo o Steam Flatpak ($FLATPAK_ID) ==="
    flatpak uninstall --system -y "$FLATPAK_ID" ||
        flatpak uninstall --user -y "$FLATPAK_ID" ||
        echo "=== ⚠️ Não foi possível remover o Flatpak; remova manualmente ==="

    if [ -n "$usuario" ]; then
        dados="/home/$usuario/.var/app/$FLATPAK_ID"
        if [ -d "$dados" ]; then
            echo "=== ⚠️ Dados antigos preservados em: $dados ==="
            echo "    Apague manualmente quando não precisar mais: rm -rf \"$dados\""
        fi
    fi
    echo "=== ✅ Steam Flatpak removido ==="
}

# -----------------------------------------------------------------------------
# Confere a montagem do disco de jogos (biblioteca em /mnt/GAMES).
# -----------------------------------------------------------------------------
verificar_disco_jogos() {
    if ! findmnt -rn -M "$PONTO_JOGOS" >/dev/null 2>&1; then
        echo "=== ⚠️ $PONTO_JOGOS não está montado. Verifique o fstab (scripts/02-hds-fstab.sh) ==="
        return
    fi

    if findmnt -rn -M "$PONTO_JOGOS" -o OPTIONS | grep -qE '(^|,)ro(,|$)'; then
        echo "=== ⚠️ $PONTO_JOGOS está montado somente leitura."
        echo "    Desmonte, rode 'sudo ntfsfix -d /dev/sdb1' e monte novamente."
        return
    fi

    echo "=== ✅ $PONTO_JOGOS montado com escrita ==="
    findmnt -rn -M "$PONTO_JOGOS"
}

mostrar_resultado() {
    echo
    echo "=== ➡️ Estado da instalação ==="
    dpkg -l steam-installer 2>/dev/null | awk '/^ii/ {print "  steam-installer: " $3}'
    dpkg -l steam-devices 2>/dev/null | awk '/^ii/ {print "  steam-devices:   " $3}'
    echo "  arquiteturas: $(dpkg --print-foreign-architectures | tr '\n' ' ')"
    echo "  lançador:     $(command -v steam || echo /usr/games/steam)"
    echo
    echo "=== ➡️ Próximos passos ==="
    echo "  1. Abra o Steam como usuário comum (NÃO use sudo): steam"
    echo "     Na primeira execução o cliente é baixado em ~/.steam/debian-installation."
    echo "  2. Faça login e vá em Configurações > Armazenamento > adicionar:"
    echo "     $PONTO_JOGOS/SteamLibrary"
    echo "  3. Instale um jogo pequeno para validar a escrita no disco."
    echo
    echo "  Se 'steam' não for encontrado, use /usr/games/steam ou adicione"
    echo "  /usr/games ao PATH (ver scripts/07-atalhos-bashrc.sh)."
}

# =============================================================================
# Execução
# =============================================================================

case "${1:-}" in
    "")
        ;;
    --remover-flatpak)
        REMOVER_FLATPAK="sim"
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

if [ "$(id -u)" -ne 0 ]; then
    echo "=== ➡️ Elevando privilégios com sudo ==="
    exec sudo bash "$0" "$@"
fi

echo "=============================================="
echo "  🔧 $appNome - Instalação"
echo "=============================================="
echo

verificar_debian
habilitar_i386
verificar_repositorio
instalar_steam

if [ "$REMOVER_FLATPAK" = "sim" ]; then
    remover_flatpak
fi

verificar_disco_jogos
mostrar_resultado

echo
echo "=============================================="
echo "✅ $appNome instalado!"
echo "=============================================="
