#!/bin/bash
set -e

# =============================================================================
#  camera.sh - Correção de acesso à câmera (Cheese + PipeWire)
#
#  FUNÇÃO DESTE SCRIPT:
#  Neste tipo de webcam (ex.: Microdia w200), o PipeWire cria o nó de vídeo,
#  mas ele falha ao iniciar:
#     spa.v4l2: '/dev/video0' VIDIOC_QUERYCTRL: Pipe quebrado
#     pw.core: error -32 ... target not found
#  O Cheese escolhe justamente esse dispositivo do PipeWire (ele tem prioridade
#  sobre o dispositivo v4l2) e mostra:
#     "Ocorreu um erro ao reproduzir o vídeo a partir da webcam"
#
#  Por isso a variável GST_V4L2_USE_LIBV4L2=1 sozinha não resolve: ela só vale
#  para o elemento v4l2src, e o Cheese está usando pipewiresrc.
#
#  A correção é fazer o Cheese ignorar os backends PipeWire e libcamera do
#  GStreamer, sobrando apenas o dispositivo v4l2 (que funciona com a libv4l2).
#  Isso é feito com GST_PLUGIN_LOADING_WHITELIST, uma lista de todos os plugins
#  GStreamer instalados, exceto "pipewire" e "libcamera". A lista é montada
#  dinamicamente, então continua correta após atualizações do sistema.
#
#  O aplicativo "Câmera" (GNOME Snapshot) funciona de outro jeito: ele NÃO usa
#  v4l2src, e sim o portal do XDG (org.freedesktop.portal.Camera) + PipeWire.
#  Dois problemas impediam o funcionamento:
#   1. A permissão "camera" do portal estava como "no" para aplicativos
#      nativos (app_id vazio), retornando "Permission denied" antes mesmo de
#      abrir a câmera;
#   2. Não havia fonte de vídeo padrão no WirePlumber (default.video.source),
#      então a política de linking não encontrava a câmera e o stream recebia
#      "target not found".
#  O script corrige os dois: concede a permissão de câmera para apps nativos
#  (Flatpaks continuam com permissões próprias) e define a câmera detectada
#  como default.video.source via wpctl.
#
#  Comandos aplicados:
#
#  1. systemctl --user restart pipewire wireplumber pipewire-pulse
#     - Reinicia a pilha de mídia do usuário, liberando a câmera caso ela tenha
#       ficado presa em uma sessão antiga ou após suspender/retomar.
#     - É executado ANTES de abrir o Cheese, para que ele já encontre o
#       dispositivo disponível.
#     - Para o app Câmera (--camera) apenas o WirePlumber é reiniciado:
#       reiniciar o PipeWire quebra a conexão usada pelo portal, e o fd
#       entregue ao app deixa de enxergar os nós da câmera.
#
#  2. GST_V4L2_USE_LIBV4L2=1 cheese --device=/dev/video0
#     - GST_V4L2_USE_LIBV4L2=1 faz o GStreamer usar a libv4l2 como
#       intermediária, que converte formatos que a câmera expõe de forma
#       incompleta (evita tela preta/imagem distorcida).
#     - --device=/dev/video0 força o uso do nó de vídeo correto. Em máquinas
#       com mais de um nó (/dev/video0, /dev/video1...), o Cheese pode
#       escolher o nó de metadados e falhar.
#
#  O script também:
#   - Verifica se o Cheese, a libv4l2 e o grupo "video" estão ok;
#   - Confere se o dispositivo realmente existe antes de abrir;
#   - Mostra os formatos suportados pela câmera (se v4l2-ctl existir);
#   - Opcionalmente (-p/--permanente) cria um wrapper em ~/.local/bin/cheese e
#     um atalho em ~/.local/share/applications, para que o ícone do Cheese no
#     menu já abra com a correção;
#   - Opcionalmente (-c/--camera) abre o aplicativo Câmera (GNOME Snapshot) em
#     vez do Cheese, usando o caminho portal + PipeWire corrigido;
#   - Opcionalmente (-n/--sem-cheese) apenas reinicia os serviços, sem abrir
#     nenhum aplicativo de câmera.
#
#  USO (execute como usuário normal, NÃO com sudo):
#     ./scripts/camera.sh                    # usa /dev/video0 e abre o Cheese
#     ./scripts/camera.sh /dev/video1        # escolhe outro dispositivo
#     ./scripts/camera.sh --camera           # abre o app Câmera (Snapshot)
#     ./scripts/camera.sh --permanente       # corrige também o ícone do menu
#     ./scripts/camera.sh --sem-cheese       # só reinicia PipeWire/WirePlumber
#     ./scripts/camera.sh --ajuda            # mostra esta ajuda
#
#  OBS.: reiniciar o pipewire-pulse interrompe o áudio por alguns segundos.
# =============================================================================

appNome="Correção de acesso à câmera"
DISPOSITIVO="/dev/video0"
ABRIR_APP="cheese"
TORNAR_PERMANENTE="nao"
LOG_CHEESE="${TMPDIR:-/tmp}/cheese-camera.log"
LOG_CAMERA="${TMPDIR:-/tmp}/camera-snapshot.log"
WRAPPER_CHEESE="$HOME/.local/bin/cheese"
DESKTOP_CHEESE="$HOME/.local/share/applications/org.gnome.Cheese.desktop"

mostrar_ajuda() {
    cat <<'AJUDA'
USO: ./scripts/camera.sh [dispositivo] [opções]

Corrige o acesso à câmera no Cheese: reinicia o PipeWire/WirePlumber e abre o
Cheese usando o backend v4l2 (com libv4l2) em vez do PipeWire quebrado.

Argumentos:
  /dev/videoN            Dispositivo de vídeo a usar (padrão: /dev/video0)

Opções:
  -c, --camera           Abre o app Câmera (GNOME Snapshot) em vez do Cheese
  -p, --permanente       Cria wrapper em ~/.local/bin/cheese e atalho no menu
  -n, --sem-cheese       Apenas reinicia os serviços, sem abrir aplicativo
  -h, --ajuda            Mostra esta ajuda

Exemplos:
  ./scripts/camera.sh
  ./scripts/camera.sh /dev/video1
  ./scripts/camera.sh --camera
  ./scripts/camera.sh --permanente

Execute como usuário normal (NÃO com sudo).
AJUDA
}

# Monta a lista de plugins GStreamer instalados, exceto pipewire e libcamera.
# Formato exigido: nomes separados por ":" (G_SEARCHPATH_SEPARATOR).
montar_whitelist_gstreamer() {
    local f b
    for f in /usr/lib/*/gstreamer-1.0/*.so /usr/lib/gstreamer-1.0/*.so; do
        [ -e "$f" ] || continue
        b=${f##*/}
        b=${b#libgst}
        b=${b%.so}
        case "$b" in
            pipewire|libcamera) continue ;;
        esac
        echo "$b"
    done | sort -u | paste -sd: -
}

# Descobre o ID do nó PipeWire correspondente ao dispositivo (/dev/videoN).
# É necessário para definir a fonte de vídeo padrão usada pelo WirePlumber.
obter_no_camera_pipewire() {
    command -v pw-dump >/dev/null 2>&1 || return 1
    command -v python3 >/dev/null 2>&1 || return 1

    pw-dump 2>/dev/null | python3 -c '
import json, sys
alvo = sys.argv[1]
for obj in json.load(sys.stdin):
    if obj.get("type") != "PipeWire:Interface:Node":
        continue
    props = obj.get("info", {}).get("props", {})
    if (props.get("media.class") == "Video/Source"
            and props.get("api.v4l2.path") == alvo):
        print(obj["id"])
        break
' "$DISPOSITIVO"
}

# Define a câmera como fonte de vídeo padrão (default.video.source). Sem isso,
# o WirePlumber não encontra um alvo para streams de câmera vindos do portal e
# o app Câmera (Snapshot) recebe "target not found".
configurar_default_video() {
    local no
    no=$(obter_no_camera_pipewire || true)

    if [ -z "$no" ]; then
        echo "⚠️  Não foi possível localizar a câmera no PipeWire;"
        echo "    o app Câmera pode não encontrar a fonte de vídeo padrão."
        return
    fi

    if wpctl set-default "$no" 2>/dev/null; then
        echo "✅ Câmera definida como fonte de vídeo padrão do PipeWire"
    else
        echo "⚠️  Não foi possível definir a câmera como padrão do PipeWire"
    fi
}

# Concede permissão de câmera no portal XDG para aplicativos nativos
# (app_id vazio). Flatpaks têm permissões próprias e não são afetados.
configurar_permissao_portal() {
    command -v gdbus >/dev/null 2>&1 || return

    if gdbus call --session \
        --dest org.freedesktop.impl.portal.PermissionStore \
        --object-path /org/freedesktop/impl/portal/PermissionStore \
        --method org.freedesktop.impl.portal.PermissionStore.SetPermission \
        devices true camera "" "['yes']" >/dev/null 2>&1; then
        echo "✅ Permissão de câmera do portal concedida para apps nativos"
    else
        echo "⚠️  Não foi possível ajustar a permissão de câmera do portal"
    fi
}

# --- Argumentos ---
for arg in "$@"; do
    case "$arg" in
        -h|--ajuda)
            mostrar_ajuda
            exit 0
            ;;
        -n|--sem-cheese)
            ABRIR_APP="nenhum"
            ;;
        -c|--camera)
            ABRIR_APP="camera"
            ;;
        -p|--permanente)
            TORNAR_PERMANENTE="sim"
            ;;
        -*)
            echo "Opção desconhecida: $arg (use --ajuda)"
            exit 1
            ;;
        *)
            DISPOSITIVO="$arg"
            ;;
    esac
done

echo "=== ➡️ $appNome ==="

# O script precisa rodar como o usuário da sessão gráfica: systemctl --user e a
# abertura do Cheese não funcionam se for executado como root (via sudo).
if [ "$(id -u)" -eq 0 ]; then
    echo "⚠️  Não execute este script como root/sudo."
    echo "    Ele precisa rodar como o usuário da sessão gráfica."
    exit 1
fi

# --- 1. Verificações de dependências ------------------------------------------

echo "=== ➡️ Verificando se o dispositivo existe ==="
if [ ! -e "$DISPOSITIVO" ]; then
    echo "⚠️  $DISPOSITIVO não encontrado. Procurando outras câmeras..."
    DISPOSITIVO=$(ls /dev/video* 2>/dev/null | head -1 || true)
fi

if [ -z "$DISPOSITIVO" ] || [ ! -e "$DISPOSITIVO" ]; then
    echo "❌ Nenhum dispositivo /dev/video* encontrado."
    echo "   Verifique se a câmera está conectada ou se é um notebook com"
    echo "   câmera desabilitada no firmware (Fn + tecla da câmera)."
    exit 1
fi

echo "✅ Usando o dispositivo: $DISPOSITIVO"

if command -v v4l2-ctl >/dev/null 2>&1; then
    echo
    echo "=== ➡️ Formatos suportados por $DISPOSITIVO ==="
    v4l2-ctl --device="$DISPOSITIVO" --list-formats-ext 2>/dev/null || true
fi

echo
echo "=== ➡️ Verificando permissões e dependências ==="
if id -nG "$(id -un)" | grep -qw video; then
    echo "✅ Usuário pertence ao grupo 'video'"
else
    echo "⚠️  Usuário NÃO pertence ao grupo 'video'. Adicionando..."
    sudo usermod -aG video "$(id -un)"
    echo "   ⚠️  Será necessário sair e entrar na sessão para o grupo valer."
fi

if ldconfig -p 2>/dev/null | grep -q 'libv4l2\.so\.0'; then
    echo "✅ libv4l2 encontrada (necessária para GST_V4L2_USE_LIBV4L2=1)"
else
    echo "=== ➡️ Instalando libv4l2 ==="
    sudo apt update -y
    sudo apt install -y libv4l-0t64 2>/dev/null ||
        sudo apt install -y libv4l-0 2>/dev/null ||
        echo "⚠️  Não foi possível instalar a libv4l2; a correção pode não funcionar."
fi

if command -v cheese >/dev/null 2>&1; then
    echo "✅ Cheese encontrado"
else
    echo "=== ➡️ Instalando Cheese ==="
    sudo apt install -y cheese
fi

# --- 2. Reinício da pilha de mídia (PipeWire/WirePlumber) ---------------------

echo
if [ "$ABRIR_APP" = "camera" ]; then
    # O app Câmera usa o portal + PipeWire. Reiniciar o PipeWire quebra a
    # conexão que o portal usa para entregar a câmera (o fd fica sem os nós),
    # então aqui reiniciamos apenas o WirePlumber, que é quem reaplica as
    # permissões dos clientes do portal.
    echo "=== ➡️ Reiniciando o WirePlumber ==="
    if systemctl --user restart wireplumber 2>/dev/null; then
        echo "  ✅ wireplumber reiniciado"
    else
        echo "  ⚠️  Não foi possível reiniciar wireplumber (ignorando)"
    fi
    sleep 2
else
    echo "=== ➡️ Reiniciando PipeWire, WirePlumber e PipeWire-Pulse ==="
    for servico in pipewire wireplumber pipewire-pulse; do
        if systemctl --user restart "$servico" 2>/dev/null; then
            echo "  ✅ $servico reiniciado"
        else
            echo "  ⚠️  Não foi possível reiniciar $servico (ignorando)"
        fi
    done
    # Dá um instante para os serviços subirem antes de abrir o Cheese.
    sleep 2
fi

echo
echo "=== ➡️ Estado dos serviços ==="
for servico in pipewire wireplumber pipewire-pulse; do
    estado=$(systemctl --user is-active "$servico" 2>/dev/null || true)
    echo "  $servico: ${estado:-desconhecido}"
done

# --- 3. Correções exigidas pelo app Câmera (portal + WirePlumber) -------------

echo
echo "=== ➡️ Ajustando o PipeWire e o portal para o app Câmera ==="
configurar_default_video
configurar_permissao_portal

# --- 4. Correção permanente (opcional) ---------------------------------------

if [ "$TORNAR_PERMANENTE" = "sim" ]; then
    echo
    echo "=== ➡️ Criando wrapper permanente do Cheese ==="

    CHEESE_BIN=$(command -v cheese)
    mkdir -p "$(dirname "$WRAPPER_CHEESE")"

    cat > "$WRAPPER_CHEESE" <<EOF
#!/bin/bash
# Gerado por meu-debian/scripts/camera.sh --permanente
# Abre o Cheese usando v4l2src (com libv4l2) em vez do PipeWire quebrado.
CHEESE_BIN="$CHEESE_BIN"
WHITELIST=\$(for f in /usr/lib/*/gstreamer-1.0/*.so /usr/lib/gstreamer-1.0/*.so; do
    [ -e "\$f" ] || continue
    b=\${f##*/}
    b=\${b#libgst}
    b=\${b%.so}
    case "\$b" in
        pipewire|libcamera) continue ;;
    esac
    echo "\$b"
done | sort -u | paste -sd: -)
export GST_V4L2_USE_LIBV4L2=1
[ -n "\$WHITELIST" ] && export GST_PLUGIN_LOADING_WHITELIST="\$WHITELIST"
exec "\$CHEESE_BIN" "\$@"
EOF
    chmod +x "$WRAPPER_CHEESE"
    echo "   ✅ Wrapper criado: $WRAPPER_CHEESE"

    if [ -f /usr/share/applications/org.gnome.Cheese.desktop ]; then
        mkdir -p "$(dirname "$DESKTOP_CHEESE")"
        sed -e "s|^Exec=.*|Exec=$WRAPPER_CHEESE|" \
            -e "s|^TryExec=.*|TryExec=$WRAPPER_CHEESE|" \
            -e "s|^DBusActivatable=true|DBusActivatable=false|" \
            /usr/share/applications/org.gnome.Cheese.desktop > "$DESKTOP_CHEESE"
        command -v update-desktop-database >/dev/null 2>&1 &&
            update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
        echo "   ✅ Atalho do menu atualizado: $DESKTOP_CHEESE"
        echo "      (o ícone Cheese do menu passará a abrir com a correção)"
    else
        echo "   ⚠️  Arquivo .desktop do Cheese não encontrado; só o wrapper foi criado."
    fi
fi

# --- 5. Abrir o aplicativo de câmera -----------------------------------------

if [ "$ABRIR_APP" != "nenhum" ]; then
    if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
        echo
        echo "⚠️  Nenhuma sessão gráfica detectada; nenhum app será aberto."
    elif [ "$ABRIR_APP" = "camera" ]; then
        echo
        echo "=== ➡️ Abrindo o app Câmera (GNOME Snapshot) ==="
        # O Snapshot usa portal + PipeWire, então NÃO deve receber a whitelist
        # que oculta o plugin pipewire (usada apenas pelo Cheese).
        pkill -x snapshot 2>/dev/null || true
        if command -v snapshot >/dev/null 2>&1; then
            nohup snapshot -d > "$LOG_CAMERA" 2>&1 &
            echo "   ✅ Câmera iniciado (PID $!)"
            echo "   Log de erros: $LOG_CAMERA"
        else
            echo "   ⚠️  Aplicativo Câmera (snapshot) não instalado."
            echo "       Instale com: sudo apt install gnome-snapshot"
        fi
    else
        WHITELIST=$(montar_whitelist_gstreamer)
        echo
        echo "=== ➡️ Abrindo Cheese com backend v4l2 em $DISPOSITIVO ==="
        echo "   (plugins GStreamer 'pipewire' e 'libcamera' ocultos)"
        # Fecha uma instância antiga: ela teria sido iniciada com o backend errado.
        pkill -x cheese 2>/dev/null || true
        if [ -n "$WHITELIST" ]; then
            nohup env GST_V4L2_USE_LIBV4L2=1 \
                GST_PLUGIN_LOADING_WHITELIST="$WHITELIST" \
                cheese --device="$DISPOSITIVO" > "$LOG_CHEESE" 2>&1 &
        else
            nohup env GST_V4L2_USE_LIBV4L2=1 \
                cheese --device="$DISPOSITIVO" > "$LOG_CHEESE" 2>&1 &
        fi
        echo "   ✅ Cheese iniciado (PID $!)"
        echo "   Log de erros: $LOG_CHEESE"
    fi
fi

echo
echo "=============================================="
echo "✅ $appNome finalizado!"
echo
echo "  Dispositivo : $DISPOSITIVO"
if [ "$ABRIR_APP" = "camera" ]; then
    echo "  Backend     : portal XDG + PipeWire (default.video.source)"
    echo "  Log         : $LOG_CAMERA"
else
    echo "  Backend     : v4l2src + libv4l2 (PipeWire oculto do Cheese)"
fi
if [ "$TORNAR_PERMANENTE" = "sim" ]; then
    echo "  Permanente  : wrapper em $WRAPPER_CHEESE"
fi
echo
echo "  Se a câmera ainda não funcionar:"
echo "   1. Verifique se ela aparece:  v4l2-ctl --list-devices"
if [ "$ABRIR_APP" = "camera" ]; then
    echo "   2. Veja o log do app Câmera:  cat $LOG_CAMERA"
else
    echo "   2. Veja o log do Cheese:      cat $LOG_CHEESE"
    echo "      ('target not found' indica que o PipeWire foi usado por engano)"
fi
echo "   3. Teste em outro app (ex.: Firefox) para confirmar que a câmera está ok"
echo "   4. Se você acabou de entrar no grupo 'video', encerre a sessão"
echo "      e entre novamente."
echo "=============================================="
