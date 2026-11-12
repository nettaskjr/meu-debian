#!/bin/bash
set -euo pipefail

# =============================================================================
#  13-hds-fstab.sh - Cadastro dos HDs FILE_SERVER e GAMES no /etc/fstab
#
#  FUNÇÃO DESTE SCRIPT:
#  Registra permanentemente os dois discos NTFS no /etc/fstab, para que sejam
#  montados automaticamente em /mnt/FILE_SERVER e /mnt/GAMES a cada boot.
#  Assim, após formatar o computador, não é preciso lembrar UUIDs, opções de
#  montagem nem recriar as linhas manualmente: basta rodar este script.
#
#  Configuração reproduzida da instalação atual:
#    FILE_SERVER : UUID 26D447C2D44792CB -> /mnt/FILE_SERVER (ntfs3)
#    GAMES       : UUID 58FE0D26FE0CFE4E -> /mnt/GAMES       (ntfs3)
#    Opções      : defaults,uid=<usuário>,gid=<grupo>,umask=022
#
#  O que o script faz:
#   1. Detecta o UID/GID do usuário que executa (ou de SUDO_USER), em vez de
#      assumir 1000, para que o acesso continue funcionando em qualquer conta;
#   2. Confere se os UUIDs ainda existem. Se um disco tiver sido reformatado,
#      procura pelo rótulo (FILE_SERVER/GAMES) e usa o UUID novo;
#   3. Cria os pontos de montagem /mnt/FILE_SERVER e /mnt/GAMES;
#   4. Faz backup do /etc/fstab antes de alterar;
#   5. Remove entradas antigas desses discos e grava um bloco identificado,
#      evitando duplicidade (script idempotente);
#   6. Valida a sintaxe, recarrega o systemd e monta os discos;
#   7. Mostra o resultado final com findmnt.
#
#  Uso:
#    ./scripts/13-hds-fstab.sh            # instala/atualiza as entradas
#    ./scripts/13-hds-fstab.sh --remover  # remove as entradas
#    ./scripts/13-hds-fstab.sh --ajuda    # mostra a ajuda
#
#  Pode ser executado como usuário comum: o script pede sudo sozinho.
# =============================================================================

appNome="HDs FILE_SERVER e GAMES no /etc/fstab"

ARQUIVO_FSTAB="/etc/fstab"
TIPO_FS="ntfs3"
OPCOES_EXTRA="umask=022"

MARCADOR_INICIO="# === HDs - meu-debian (início) ==="
MARCADOR_FIM="# === HDs - meu-debian (fim) ==="

# Dados atuais dos discos (obtidos com blkid). Se o UUID não existir mais,
# o script tenta localizar o disco pelo rótulo e atualiza a lista em memória.
ROTULOS=("FILE_SERVER" "GAMES")
UUIDS=("26D447C2D44792CB" "58FE0D26FE0CFE4E")
PONTOS=("/mnt/FILE_SERVER" "/mnt/GAMES")

MODO="instalar"
UID_MONTAGEM=""
GID_MONTAGEM=""
USUARIO_MONTAGEM=""
DISCOS_AUSENTES=0

mostrar_ajuda() {
    cat << 'AJUDA'
USO: ./scripts/13-hds-fstab.sh [opções]

Cadastra os HDs FILE_SERVER e GAMES no /etc/fstab para montagem automática
em /mnt/FILE_SERVER e /mnt/GAMES, usando o sistema de arquivos ntfs3.

Opções:
  (sem opção)     Instala ou atualiza as entradas no /etc/fstab
  -r, --remover   Remove as entradas e o bloco gerenciado pelo script
  -h, --ajuda     Mostra esta ajuda

Observações:
  - O script pede sudo automaticamente, se necessário.
  - Um backup do fstab é criado como /etc/fstab.bak.<data>-<hora>.
  - As opções uid/gid são ajustadas para o usuário que executa o script.
  - Se um disco foi reformatado, o UUID é redescoberto pelo rótulo.
  - Executar novamente não duplica entradas (idempotente).
AJUDA
}

# -----------------------------------------------------------------------------
# Escolhe o usuário dono dos arquivos montados.
# - Execução via sudo: usa SUDO_USER (quem chamou o sudo).
# - Execução como root direto: usa o primeiro usuário comum (UID >= 1000).
# - Execução como usuário comum: usa o próprio usuário.
# -----------------------------------------------------------------------------
definir_usuario_montagem() {
    if [ "$(id -u)" -eq 0 ]; then
        USUARIO_MONTAGEM="${SUDO_USER:-}"
        if [ -z "$USUARIO_MONTAGEM" ]; then
            USUARIO_MONTAGEM=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}')
        fi
    else
        USUARIO_MONTAGEM="$(id -un)"
    fi

    if [ -z "$USUARIO_MONTAGEM" ] || ! id "$USUARIO_MONTAGEM" >/dev/null 2>&1; then
        echo "❌ Não foi possível identificar o usuário dono dos arquivos."
        echo "   Execute como usuário comum (o script pede sudo) ou informe SUDO_USER."
        exit 1
    fi

    UID_MONTAGEM=$(id -u "$USUARIO_MONTAGEM")
    GID_MONTAGEM=$(id -g "$USUARIO_MONTAGEM")
    echo "=== ➡️ Dono dos arquivos: $USUARIO_MONTAGEM (uid=$UID_MONTAGEM, gid=$GID_MONTAGEM) ==="
}

# -----------------------------------------------------------------------------
# Garante que cada UUID ainda corresponde a um disco conectado. Caso o UUID
# não exista (disco reformatado), tenta descobrir pelo rótulo.
# -----------------------------------------------------------------------------
resolver_uuids() {
    local i dispositivo uuid_atual
    for i in "${!UUIDS[@]}"; do
        if blkid -U "${UUIDS[$i]}" >/dev/null 2>&1; then
            echo "=== ✅ ${ROTULOS[$i]}: disco encontrado (UUID ${UUIDS[$i]}) ==="
            continue
        fi

        dispositivo=$(blkid -L "${ROTULOS[$i]}" 2>/dev/null || true)
        if [ -n "$dispositivo" ]; then
            uuid_atual=$(blkid -s UUID -o value "$dispositivo")
            if [ -n "$uuid_atual" ]; then
                echo "=== ⚠️ ${ROTULOS[$i]}: UUID antigo não encontrado; usando o atual ($uuid_atual) ==="
                UUIDS[i]="$uuid_atual"
                continue
            fi
        fi

        echo "=== ⚠️ ${ROTULOS[$i]}: disco não encontrado (UUID nem rótulo). A entrada será mantida mesmo assim. ==="
        DISCOS_AUSENTES=$((DISCOS_AUSENTES + 1))
    done
}

# -----------------------------------------------------------------------------
# Remove o bloco gerenciado e qualquer entrada antiga dos mesmos discos
# (mesmo UUID ou mesmo ponto de montagem), gravando o resultado em $1.
# -----------------------------------------------------------------------------
gerar_fstab_limpo() {
    local destino="$1"
    sed "\|^${MARCADOR_INICIO}$|,\|^${MARCADOR_FIM}$|d" "$ARQUIVO_FSTAB" |
        awk -v uuid1="${UUIDS[0]}" -v uuid2="${UUIDS[1]}" \
            -v ponto1="${PONTOS[0]}" -v ponto2="${PONTOS[1]}" '
            $1 == "UUID=" uuid1 || $1 == "UUID=" uuid2 ||
            $2 == ponto1 || $2 == ponto2 { next }
            { print }
        ' > "$destino"
}

# -----------------------------------------------------------------------------
# Cria os pontos de montagem, se ainda não existirem.
# -----------------------------------------------------------------------------
criar_pontos_montagem() {
    local ponto
    for ponto in "${PONTOS[@]}"; do
        if [ ! -d "$ponto" ]; then
            echo "=== ➡️ Criando ponto de montagem $ponto ==="
            mkdir -p "$ponto"
        fi
    done
}

# -----------------------------------------------------------------------------
# Acrescenta ao fstab o bloco gerenciado com as duas entradas.
# -----------------------------------------------------------------------------
adicionar_bloco() {
    local destino="$1" i opcoes
    opcoes="defaults,uid=${UID_MONTAGEM},gid=${GID_MONTAGEM},${OPCOES_EXTRA}"

    {
        echo ""
        echo "$MARCADOR_INICIO"
        echo "# Bloco gerenciado por scripts/13-hds-fstab.sh - não edite manualmente."
        echo "# Discos NTFS com acesso de leitura/escrita para $USUARIO_MONTAGEM."
        for i in "${!UUIDS[@]}"; do
            printf 'UUID=%-18s %-18s %-6s %s  0  0\n' \
                "${UUIDS[$i]}" "${PONTOS[$i]}" "$TIPO_FS" "$opcoes"
        done
        echo "$MARCADOR_FIM"
    } >> "$destino"
}

# -----------------------------------------------------------------------------
# Substitui o /etc/fstab pelo arquivo gerado, guardando backup do original.
# -----------------------------------------------------------------------------
instalar_fstab() {
    local origem="$1" backup
    backup="${ARQUIVO_FSTAB}.bak.$(date +%Y%m%d-%H%M%S)"

    echo "=== ➡️ Criando backup em $backup ==="
    cp -a "$ARQUIVO_FSTAB" "$backup"

    echo "=== ➡️ Gravando novo $ARQUIVO_FSTAB ==="
    install -m 0644 -o root -g root "$origem" "$ARQUIVO_FSTAB"
}

# -----------------------------------------------------------------------------
# Confere a sintaxe do arquivo gerado (antes de substituir o fstab).
# O findmnt acusa "parse errors" para linhas malformadas. Erros de dispositivo
# ausente são apenas avisos, pois o disco pode estar desconectado.
# -----------------------------------------------------------------------------
validar_fstab() {
    local arquivo="$1" saida
    saida=$(LC_ALL=C findmnt --verify --tab-file "$arquivo" 2>&1 || true)

    if ! grep -q '^0 parse errors' <<< "$saida"; then
        echo "❌ O fstab gerado possui erro de sintaxe:"
        echo "$saida"
        exit 1
    fi

    if [ "$DISCOS_AUSENTES" -eq 0 ] && grep -q '\[E\]' <<< "$saida"; then
        echo "❌ O fstab gerado não passou na validação:"
        echo "$saida"
        exit 1
    fi

    echo "=== ✅ Sintaxe do fstab validada ==="
}

# -----------------------------------------------------------------------------
# Recarrega o systemd e monta os discos usando as novas entradas.
# -----------------------------------------------------------------------------
aplicar_montagens() {
    local i ponto montagem_atual

    echo "=== ➡️ Recarregando unidades do systemd (systemctl daemon-reload) ==="
    systemctl daemon-reload

    for i in "${!UUIDS[@]}"; do
        ponto="${PONTOS[$i]}"
        montagem_atual=$(findmnt -rn -S "UUID=${UUIDS[$i]}" -o TARGET | head -n1 || true)

        if [ "$montagem_atual" = "$ponto" ]; then
            echo "=== ➡️ ${ROTULOS[$i]} já está montado em $ponto; reaplicando opções ==="
            if mount -o remount "$ponto"; then
                echo "=== ✅ Opções reaplicadas ==="
            else
                echo "=== ⚠️ Não foi possível reaplicar as opções; desmonte e monte novamente. ==="
            fi
        elif [ -n "$montagem_atual" ]; then
            echo "=== ⚠️ ${ROTULOS[$i]} está montado em $montagem_atual; desmonte antes de usar $ponto ==="
        else
            echo "=== ➡️ Montando ${ROTULOS[$i]} em $ponto ==="
            if mount "$ponto" 2>/dev/null; then
                echo "=== ✅ ${ROTULOS[$i]} montado ==="
            else
                echo "=== ⚠️ Não foi possível montar ${ROTULOS[$i]} agora. Verifique se o disco está conectado. ==="
            fi
        fi
    done
}

mostrar_resultado() {
    local i ponto
    echo
    echo "=== ➡️ Entradas no fstab ==="
    grep -A4 "$MARCADOR_INICIO" "$ARQUIVO_FSTAB" || true
    echo
    echo "=== ➡️ Estado atual das montagens ==="
    for ponto in "${PONTOS[@]}"; do
        if findmnt -rn -M "$ponto" >/dev/null 2>&1; then
            findmnt -rn -M "$ponto"
        else
            echo "$ponto -> não montado"
        fi
    done
}

# -----------------------------------------------------------------------------
# Modo de remoção
# -----------------------------------------------------------------------------
remover_entradas() {
    local tmp backup
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT

    echo "=== ➡️ Removendo entradas de ${ROTULOS[*]} do $ARQUIVO_FSTAB ==="
    gerar_fstab_limpo "$tmp"

    backup="${ARQUIVO_FSTAB}.bak.$(date +%Y%m%d-%H%M%S)"
    echo "=== ➡️ Criando backup em $backup ==="
    cp -a "$ARQUIVO_FSTAB" "$backup"

    install -m 0644 -o root -g root "$tmp" "$ARQUIVO_FSTAB"
    echo "=== ✅ Entradas removidas ==="

    systemctl daemon-reload
    echo "=== ⚠️ Os discos continuam montados até o próximo boot ou desmontagem manual. ==="
    echo "    Para desmontar agora: umount ${PONTOS[*]}"
}

# =============================================================================
# Execução
# =============================================================================

case "${1:-}" in
    "")
        MODO="instalar"
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

# Ajuda não precisa de root; o restante precisa alterar /etc/fstab.
if [ "$(id -u)" -ne 0 ]; then
    echo "=== ➡️ Elevando privilégios com sudo ==="
    exec sudo bash "$0" "$@"
fi

echo "=============================================="
echo "  🔧 $appNome - ${MODO^}"
echo "=============================================="
echo

if [ "$MODO" = "remover" ]; then
    remover_entradas
    echo
    echo "=============================================="
    echo "✅ $appNome removidos!"
    echo "=============================================="
    exit 0
fi

definir_usuario_montagem
resolver_uuids
criar_pontos_montagem

TMP_FSTAB=$(mktemp)
trap 'rm -f "$TMP_FSTAB"' EXIT

gerar_fstab_limpo "$TMP_FSTAB"
adicionar_bloco "$TMP_FSTAB"

validar_fstab "$TMP_FSTAB"
instalar_fstab "$TMP_FSTAB"
aplicar_montagens
mostrar_resultado

if [ "$DISCOS_AUSENTES" -gt 0 ]; then
    echo
    echo "⚠️  $DISCOS_AUSENTES disco(s) não foram encontrados agora."
    echo "    A entrada foi mantida no fstab; conecte o disco e rode novamente"
    echo "    para que o UUID seja atualizado, se necessário."
fi

echo
echo "=============================================="
echo "✅ $appNome configurados!"
echo
echo "  Para conferir:  findmnt /mnt/FILE_SERVER /mnt/GAMES"
echo "  Para testar:    sudo umount /mnt/GAMES && sudo mount /mnt/GAMES"
echo "=============================================="
