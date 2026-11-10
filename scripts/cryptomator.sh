#!/bin/bash
set -e

# =============================================================================
#  cryptomator.sh - Dá ao Cryptomator (Flatpak) acesso às pastas fora de ~
#
#  FUNÇÃO DESTE SCRIPT:
#  O Cryptomator instalado via Flatpak roda dentro de um sandbox. O sandbox só
#  enxerga o que está declarado nas permissões do aplicativo. Na instalação
#  padrão do Flathub as permissões são:
#
#     filesystems=home;host-etc:ro;...
#
#  Ou seja: a pasta pessoal (~) e /etc (somente leitura). Pastas como /mnt,
#  /media e /run/media NÃO existem dentro do sandbox.
#
#  Sintoma: o Nautilus e o terminal veem /mnt normalmente (não são sandboxed),
#  mas no seletor de pastas do Cryptomator só aparecem as pastas da raiz do
#  sandbox (app, bin, dev, etc, home, lib, lib64, proc, run, sbin, sys, tmp,
#  usr, var) e nenhuma pasta de /mnt. Nada tem a ver com o /etc/fstab, que pode
#  estar correto.
#
#  A correção é conceder a permissão de filesystem ao sandbox:
#
#     flatpak override --user --filesystem=/mnt org.cryptomator.Cryptomator
#
#  Isso NÃO precisa de root: o override de usuário fica em
#  ~/.local/share/flatpak/overrides/<id> e tem prioridade sobre o override de
#  sistema. A permissão é permanente (sobrevive a updates do Flatpak e a
#  reinicializações) e não altera o /etc/fstab.
#
#  Depois de alterar as permissões é obrigatório reiniciar o aplicativo: o
#  Flatpak cria o namespace (as pastas visíveis) no momento em que o processo
#  é iniciado. Fechar só a janela não basta; o script usa "flatpak kill" e
#  reabre o Cryptomator se ele estiver rodando.
#
#  O script também:
#   - Detecta se o Cryptomator está instalado como Flatpak;
#   - Aceita vários caminhos de uma vez (padrão: /mnt);
#   - Não repete a permissão se ela já existir (idempotente);
#   - Confere dentro do sandbox, de verdade, se cada pasta ficou visível;
#   - Oferece --sistema para valer para todos os usuários (usa sudo);
#   - Oferece --remover para revogar o acesso;
#   - Oferece --nao-reiniciar para apenas ajustar as permissões;
#   - Aceita --app para aplicar em outro aplicativo Flatpak qualquer.
#
#  USO (execute como usuário normal, NÃO com sudo):
#     ./scripts/cryptomator.sh                     # libera /mnt
#     ./scripts/cryptomator.sh /mnt/GAMES          # libera uma pasta só
#     ./scripts/cryptomator.sh /mnt /run/media/$USER
#     ./scripts/cryptomator.sh --sistema           # todos os usuários (sudo)
#     ./scripts/cryptomator.sh --remover           # revoga o acesso a /mnt
#     ./scripts/cryptomator.sh --nao-reiniciar     # só ajusta, não reabre
#     ./scripts/cryptomator.sh --app org.gnome.Nautilus /mnt
#     ./scripts/cryptomator.sh --ajuda             # mostra esta ajuda
#
#  OBS.: pastas dentro da sua home (~) já são visíveis e não precisam disso.
#        Se o cofre ficar em um disco montado sob demanda (udisks), o caminho
#        costuma ser /run/media/$USER/<rótulo>.
# =============================================================================

appNome="Acesso do Cryptomator fora da pasta pessoal"
APP_ID="org.cryptomator.Cryptomator"
ESCOPO="usuario"
REINICIAR="sim"
REMOVER="nao"
CAMINHOS=()
LOG_APP="${TMPDIR:-/tmp}/cryptomator.log"

mostrar_ajuda() {
    cat <<'AJUDA'
USO: ./scripts/cryptomator.sh [caminhos...] [opções]

Concede ao Cryptomator (Flatpak) acesso a pastas fora da pasta pessoal, como
/mnt, /media e /run/media/$USER. Sem isso o seletor de pastas do app mostra
apenas a raiz do sandbox e nenhuma pasta de /mnt.

Argumentos:
  /caminho               Pasta a liberar (padrão: /mnt). Pode repetir.

Opções:
  -s, --sistema          Aplica para todos os usuários (usa sudo)
  -r, --remover          Revoga o acesso aos caminhos informados
  -n, --nao-reiniciar    Apenas ajusta as permissões, sem reabrir o app
      --app ID           Aplica em outro Flatpak (padrão: org.cryptomator.Cryptomator)
  -h, --ajuda            Mostra esta ajuda

Exemplos:
  ./scripts/cryptomator.sh
  ./scripts/cryptomator.sh /mnt/GAMES
  ./scripts/cryptomator.sh /mnt /run/media/$USER
  ./scripts/cryptomator.sh --sistema
  ./scripts/cryptomator.sh --remover
  ./scripts/cryptomator.sh --nao-reiniciar

Execute como usuário normal (NÃO com sudo), exceto com --sistema, que pede a
senha na hora de gravar o override de sistema.
AJUDA
}

morrer() {
    echo "❌ $*"
    exit 1
}

# Caminho do arquivo de override do escopo escolhido. Usado apenas pelo
# --remover (o Flatpak não tem comando para apagar uma permissão específica).
arquivo_override() {
    if [ "$ESCOPO" = "sistema" ]; then
        echo "/var/lib/flatpak/overrides/$APP_ID"
    else
        echo "${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/overrides/$APP_ID"
    fi
}

ler_arquivo() {
    if [ "$ESCOPO" = "sistema" ]; then
        sudo cat "$1"
    else
        cat "$1"
    fi
}

escrever_arquivo() {
    if [ "$ESCOPO" = "sistema" ]; then
        sudo tee "$1" >/dev/null
    else
        cat > "$1"
    fi
}

# Valor atual da linha "filesystems=" do aplicativo (vazio se não houver).
linha_filesystems() {
    flatpak info --show-permissions "$APP_ID" 2>/dev/null |
        sed -n 's/^filesystems=//p'
}

tem_permissao() {
    local atual
    atual=$(linha_filesystems)
    case ";$atual;" in
        *";$1;"*) return 0 ;;
    esac
    return 1
}

# Mesma checagem, mas só no escopo escolhido (usuário ou sistema). É essa que
# decide se há algo a fazer: uma permissão vinda do outro escopo continua
# valendo, e o --sistema precisa gravar a dele mesmo assim.
tem_permissao_escopo() {
    local atual
    if [ "$ESCOPO" = "sistema" ]; then
        atual=$(flatpak override --show "$APP_ID" 2>/dev/null | sed -n 's/^filesystems=//p')
    else
        atual=$(flatpak override --user --show "$APP_ID" 2>/dev/null | sed -n 's/^filesystems=//p')
    fi
    case ";$atual;" in
        *";$1;"*) return 0 ;;
    esac
    return 1
}

app_instalado() {
    flatpak info "$APP_ID" >/dev/null 2>&1
}

app_rodando() {
    flatpak ps 2>/dev/null | awk '{print $3}' | grep -qx "$APP_ID"
}

# Confere DENTRO do sandbox se as pastas estão visíveis de verdade: inicia um
# "sh" efêmero com as permissões atuais do aplicativo.
verificar_sandbox() {
    local saida
    if command -v timeout >/dev/null 2>&1; then
        saida=$(timeout 30 flatpak run --command=sh "$APP_ID" -c '
            for p in "$@"; do
                if [ -d "$p" ]; then
                    printf "OK|%s\n" "$p"
                else
                    printf "SEM|%s\n" "$p"
                fi
            done' sh "$@" 2>/dev/null) || return 1
    else
        saida=$(flatpak run --command=sh "$APP_ID" -c '
            for p in "$@"; do
                if [ -d "$p" ]; then
                    printf "OK|%s\n" "$p"
                else
                    printf "SEM|%s\n" "$p"
                fi
            done' sh "$@" 2>/dev/null) || return 1
    fi
    printf '%s\n' "$saida"
}

# Remove uma entrada exata da linha "filesystems=" do override.
remover_entrada() {
    local arquivo="$1" alvo="$2"
    local tmp
    tmp=$(mktemp)
    ler_arquivo "$arquivo" | awk -v alvo="$alvo" '
        /^filesystems=/ {
            n = split(substr($0, 13), itens, ";")
            saida = ""
            for (i = 1; i <= n; i++) {
                if (itens[i] == "" || itens[i] == alvo || itens[i] == "!" alvo) continue
                saida = (saida == "" ? itens[i] : saida ";" itens[i])
            }
            if (saida == "") next
            print "filesystems=" saida
            next
        }
        { print }
    ' > "$tmp"
    escrever_arquivo "$arquivo" < "$tmp"
    rm -f "$tmp"
}

# --- Argumentos --------------------------------------------------------------

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--ajuda)
            mostrar_ajuda
            exit 0
            ;;
        -s|--sistema)
            ESCOPO="sistema"
            shift
            ;;
        -r|--remover)
            REMOVER="sim"
            shift
            ;;
        -n|--nao-reiniciar)
            REINICIAR="nao"
            shift
            ;;
        --app)
            [ $# -ge 2 ] || morrer "A opção --app exige um ID (ex.: org.cryptomator.Cryptomator)."
            APP_ID="$2"
            shift 2
            ;;
        -*)
            morrer "Opção desconhecida: $1 (use --ajuda)"
            ;;
        /*)
            CAMINHOS+=("$1")
            shift
            ;;
        *)
            morrer "Caminho deve ser absoluto (começar com /): $1"
            ;;
    esac
done

[ ${#CAMINHOS[@]} -gt 0 ] || CAMINHOS=("/mnt")

echo "=== ➡️ $appNome ==="

# O override de usuário e a reinicialização do app pertencem à sessão do
# usuário; rodar como root aplicaria as permissões em outro dono.
if [ "$(id -u)" -eq 0 ] && [ "$ESCOPO" != "sistema" ]; then
    morrer "Não execute este script como root/sudo (use --sistema se for o caso)."
fi

# --- 1. Verificações ---------------------------------------------------------

echo
echo "=== ➡️ Verificando o Flatpak e o aplicativo ==="
command -v flatpak >/dev/null 2>&1 || morrer "Flatpak não está instalado."
app_instalado || morrer "O Flatpak '$APP_ID' não está instalado.
   Instale com: flatpak install flathub $APP_ID"

echo "✅ Aplicativo encontrado: $APP_ID"
echo "   Escopo do override: $ESCOPO"

echo
echo "=== ➡️ Verificando os caminhos no sistema ==="
for caminho in "${CAMINHOS[@]}"; do
    [ -d "$caminho" ] || morrer "A pasta '$caminho' não existe (ou não está montada)."
    echo "✅ $caminho"
    case "$caminho" in
        "$HOME"|"$HOME"/*)
            echo "   ⚠️  Já fica dentro da pasta pessoal, que o sandbox sempre vê."
            ;;
    esac
done

echo
echo "=== ➡️ Permissões atuais do sandbox ==="
PERMISSOES=$(linha_filesystems)
echo "   filesystems=${PERMISSOES:-<vazio>}"

# --- 2. Aplicar ou remover as permissões -------------------------------------

echo
if [ "$REMOVER" = "sim" ]; then
    echo "=== ➡️ Revogando o acesso ==="
    ARQUIVO=$(arquivo_override)
    for caminho in "${CAMINHOS[@]}"; do
        if ! tem_permissao_escopo "$caminho"; then
            echo "   ℹ️  $caminho já não tinha permissão neste escopo (nada a fazer)"
            continue
        fi
        if [ ! -f "$ARQUIVO" ]; then
            morrer "Arquivo de override não encontrado: $ARQUIVO"
        fi
        remover_entrada "$ARQUIVO" "$caminho"
        echo "   🗑️  Permissão removida: $caminho"
        if tem_permissao "$caminho"; then
            echo "   ⚠️  Ainda concedida em outro escopo (ex.: sistema)."
            echo "       Remova no outro escopo para revogar de vez."
        fi
    done
else
    echo "=== ➡️ Concedendo acesso ==="
    for caminho in "${CAMINHOS[@]}"; do
        if tem_permissao_escopo "$caminho"; then
            echo "   ✅ $caminho já tinha permissão neste escopo (nada a fazer)"
            continue
        fi
        if [ "$ESCOPO" = "sistema" ]; then
            sudo flatpak override --filesystem="$caminho" "$APP_ID"
        else
            flatpak override --user --filesystem="$caminho" "$APP_ID"
        fi
        echo "   ✅ Permissão concedida: $caminho"
    done
fi

echo
echo "=== ➡️ Permissões depois do ajuste ==="
PERMISSOES=$(linha_filesystems)
echo "   filesystems=${PERMISSOES:-<vazio>}"

# --- 3. Conferir dentro do sandbox ------------------------------------------

echo
echo "=== ➡️ Testando o acesso dentro do sandbox ==="
if verificacao=$(verificar_sandbox "${CAMINHOS[@]}"); then
    while IFS='|' read -r estado caminho; do
        case "$estado" in
            OK)  echo "   ✅ visível:    $caminho" ;;
            SEM) echo "   ❌ invisível:  $caminho" ;;
        esac
    done <<< "$verificacao"
else
    echo "   ⚠️  Não foi possível iniciar o app para testar (sessão gráfica?)"
    echo "      Abra o Cryptomator e confira o seletor de pastas."
fi

# --- 4. Reiniciar o aplicativo ----------------------------------------------

echo
if app_rodando; then
    if [ "$REINICIAR" = "sim" ]; then
        echo "=== ➡️ Reiniciando o $APP_ID ==="
        flatpak kill "$APP_ID" 2>/dev/null || true
        sleep 2
        if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
            nohup flatpak run "$APP_ID" > "$LOG_APP" 2>&1 &
            sleep 4
            if app_rodando; then
                echo "   ✅ Aplicativo reaberto"
            else
                echo "   ⚠️  O aplicativo não subiu; veja o log: $LOG_APP"
            fi
        else
            echo "   ⚠️  Nenhuma sessão gráfica detectada; abra o app manualmente."
        fi
    else
        echo "⚠️  O app está aberto e NÃO foi reiniciado."
        echo "    Feche-o por completo (ou rode sem --nao-reiniciar) para a"
        echo "    permissão passar a valer."
    fi
else
    echo "ℹ️  O aplicativo não está aberto; a permissão vale no próximo início."
fi

echo
echo "=============================================="
echo "✅ $appNome finalizado!"
echo
echo "  Aplicativo : $APP_ID"
echo "  Escopo     : $ESCOPO"
echo "  Pastas     : ${CAMINHOS[*]}"
echo "  Override   : $(arquivo_override)"
echo
echo "  Sobre o /etc/fstab: ele não precisa ser alterado. O problema era só o"
echo "  sandbox do Flatpak, que não enxergava /mnt."
echo
echo "  Se o seletor de pastas continuar sem /mnt:"
echo "   1. Confirme que o app foi reiniciado:  flatpak ps | grep -i cryptomator"
echo "   2. Veja as permissões:                 flatpak info --show-permissions $APP_ID"
echo "   3. Veja o log de abertura:             cat $LOG_APP"
echo "   4. Para interface gráfica, instale o Flatseal e ajuste em Filesystem."
echo "=============================================="
