#!/bin/bash
set -e

appNome="Configurações GNOME (gsettings)"

# Botão lateral "avançar" do mouse -> <Ctrl>+<F4> (fecha a aba) via input-remapper.
# Funciona para QUALQUER modelo de mouse: todos os mouses conectados são
# detectados automaticamente em /proc/bus/input/devices.
#
# MOUSE_FORWARD_BUTTON="auto" detecta o botão (preferência: BTN_EXTRA, depois
# BTN_FORWARD, BTN_SIDE e BTN_BACK). Se o botão "avançar" do seu mouse usar
# outro código, force aqui: BTN_SIDE, BTN_EXTRA, BTN_FORWARD ou BTN_BACK.
# Para descobrir qual botão dispara, use: sudo evtest
MOUSE_FORWARD_BUTTON="auto"
MOUSE_FORWARD_MACRO="KEY_LEFTCTRL+F4"  # atalho emitido (Ctrl+F4)
MOUSE_PRESET="FecharAbas"              # nome do preset salvo

echo "=== ➡️ Aplicando $appNome ==="

# ============================================================
# LISTA DE CONFIGURAÇÕES (a ser preenchida)
#
# Formato por linha:
#   "schema" "chave" "valor"
#
# Exemplos:
#   "org.gnome.desktop.interface" "color-scheme" "'prefer-dark'"
#   "org.gnome.desktop.interface" "clock-show-seconds" "true"
# ============================================================

CONFIGURACOES=(
    # "schema" "chave" "valor"
    "org.gnome.desktop.interface" "color-scheme" "'prefer-dark'"
    "org.gnome.desktop.interface" "clock-show-seconds" "true"
    "org.gnome.desktop.interface" "clock-show-weekday" "true"
    "org.gnome.desktop.interface" "enable-animations" "false"
    "org.gnome.desktop.wm.preferences" "button-layout" "'appmenu:minimize,maximize,close'"
    "org.gnome.desktop.wm.preferences" "auto-raise" "false"
    "org.gnome.desktop.wm.preferences" "focus-mode" "'click'"
    "org.gnome.desktop.sound" "event-sounds" "false"
    "org.gnome.desktop.sound" "input-feedback-sounds" "false"
    "org.gnome.desktop.privacy" "remember-recent-files" "false"
    "org.gnome.desktop.privacy" "send-software-usage-stats" "false"
    "org.gnome.desktop.privacy" "usb-protection" "false"
    "org.gnome.desktop.peripherals.keyboard" "repeat" "true"
    "org.gnome.desktop.peripherals.mouse" "natural-scroll" "false"
    "org.gnome.gedit.preferences.editor" "display-right-margin" "true"
    "org.gnome.gedit.preferences.editor" "right-margin-position" "80"
    "org.gnome.gedit.preferences.editor" "insert-spaces" "true"
    "org.gnome.gedit.plugins" "active-plugins" "['docinfo', 'filebrowser', 'modelines', 'sort', 'spell', 'time', 'quickhighlight']"
    # atalhos de teclado customizados (pré-definidos)
    "org.gnome.settings-daemon.plugins.media-keys" "www" "['<Super>w']"
    "org.gnome.settings-daemon.plugins.media-keys" "home" "['<Super>e']"
)

# ------------------------------------------------------------
# ATALHOS DE TECLADO CUSTOMIZADOS
#
# Formato por linha (4 campos):
#   "tecla" "comando" "nome" "descrição"
#
# Exemplos:
#   "<Super>e" "nautilus" "Pasta Home" "Abrir pasta home"
#   "<Control><Alt>t" "gnome-terminal" "Terminal" "Abrir terminal"
# ------------------------------------------------------------
ATALHOS=(
    "<Control><Alt>t" "gnome-terminal" "Terminal" "Abrir terminal"
    "<Super>g" "gedit" "Editor de Texto" "Abrir editor de texto"
)

# ------------------------------------------------------------

aplicar_configuracoes() {
    local schema chave valor
    local sucesso=0 falha=0

    if [ ${#CONFIGURACOES[@]} -eq 0 ]; then
        echo "⚠️  Nenhuma configuração cadastrada na lista."
        exit 1
    fi

    for ((i = 0; i < ${#CONFIGURACOES[@]}; i += 3)); do
        schema="${CONFIGURACOES[$i]}"
        chave="${CONFIGURACOES[$((i + 1))]}"
        valor="${CONFIGURACOES[$((i + 2))]}"

        echo
        echo "➡️ $schema $chave"

        if gsettings set "$schema" "$chave" "$valor" 2>/dev/null; then
            echo "   ✅ Aplicado (valor: $valor)"
            sucesso=$((sucesso + 1))
        else
            echo "   ❌ Falha ao aplicar"
            falha=$((falha + 1))
        fi
    done

    echo
    echo "=============================================="
    echo "✅  $sucesso configurações aplicadas"
    [ "$falha" -gt 0 ] && echo "❌  $falha configurações falharam"
    echo "=============================================="
}

aplicar_atalhos() {
    if [ ${#ATALHOS[@]} -eq 0 ]; then
        echo
        echo "⚠️  Nenhum atalho registrado na lista."
        return
    fi

    local total=$(( ${#ATALHOS[@]} / 4 ))
    local caminhos=()
    local i tecla comando nome desc path

    for ((i = 0; i < total; i++)); do
        caminhos+=("'/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom${i}/'")
    done

    local lista_caminhos
    lista_caminhos="$(printf "%s," "${caminhos[@]}")"
    lista_caminhos="[${lista_caminhos%,}]"

    echo
    echo "➡️ org.gnome.settings-daemon.plugins.media-keys custom-keybindings"
    echo "   $lista_caminhos"

    if gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$lista_caminhos" 2>/dev/null; then
        echo "   ✅ Caminhos registrados"
    else
        echo "   ❌ Falha ao registrar caminhos"
    fi

    local sucesso=0 falha=0
    for ((i = 0; i < total; i++)); do
        tecla="${ATALHOS[$((i * 4))]}"
        comando="${ATALHOS[$((i * 4 + 1))]}"
        nome="${ATALHOS[$((i * 4 + 2))]}"
        desc="${ATALHOS[$((i * 4 + 3))]}"
        path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom${i}/"

        echo
        echo "➡️ Atalho ${i}: $tecla → $comando ($nome)"

        if gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${path}" name "$nome" 2>/dev/null \
            && gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${path}" command "$comando" 2>/dev/null \
            && gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${path}" binding "$tecla" 2>/dev/null; then
            echo "   ✅ $nome ($tecla)"
            sucesso=$((sucesso + 1))
        else
            echo "   ❌ Falha ao aplicar $nome"
            falha=$((falha + 1))
        fi
    done

    echo
    echo "=============================================="
    echo "✅  $sucesso atalhos aplicados"
    [ "$falha" -gt 0 ] && echo "❌  $falha atalhos falharam"
    echo "=============================================="
}

aplicar_botao_mouse() {
    echo
    echo "=== ➡️ Configurando botão 'avançar' do mouse → <Ctrl>+<F4> ==="

    if ! command -v input-remapper-control &>/dev/null; then
        echo "⚠️  input-remapper não encontrado. Instale com: sudo apt install input-remapper"
        return
    fi

    if ! python3 - "$MOUSE_PRESET" "$MOUSE_FORWARD_BUTTON" "$MOUSE_FORWARD_MACRO" <<'PY'
import sys

from evdev import ecodes
from inputremapper.configs.global_config import GlobalConfig
from inputremapper.configs.input_config import InputCombination, InputConfig
from inputremapper.configs.mapping import Mapping
from inputremapper.configs.paths import PathUtils
from inputremapper.configs.preset import Preset

PRESET_NAME, BUTTON_PREF, MACRO = sys.argv[1:4]

BTN_LEFT = 0x110
REL_X, REL_Y = 0x00, 0x01
# Ordem de preferência para o botão "avançar"
BTN_CANDIDATES = [ecodes.BTN_EXTRA, ecodes.BTN_FORWARD, ecodes.BTN_SIDE, ecodes.BTN_BACK]


def parse_proc(path="/proc/bus/input/devices"):
    """Lê os dispositivos de entrada direto do /proc (não exige root)."""
    devices, cur = [], None
    with open(path) as file:
        for line in file:
            line = line.rstrip("\n")
            if not line:
                if cur:
                    devices.append(cur)
                    cur = None
                continue

            if line.startswith("I: "):
                if cur:
                    devices.append(cur)
                cur = {
                    "bus": "", "vendor": "", "product": "", "version": "",
                    "name": "", "phys": "", "uniq": "", "bits": {},
                }
                for token in line[3:].split():
                    key, _, value = token.partition("=")
                    cur[key.lower()] = value
            elif cur is None:
                continue
            elif line.startswith("N: Name="):
                cur["name"] = line[len("N: Name="):].strip().strip('"')
            elif line.startswith("P: Phys="):
                cur["phys"] = line[len("P: Phys="):].strip()
            elif line.startswith("U: Uniq="):
                cur["uniq"] = line[len("U: Uniq="):].strip()
            elif line.startswith("B: "):
                key, _, value = line[3:].partition("=")
                cur["bits"][key.strip()] = value.strip()

    if cur:
        devices.append(cur)
    return devices


def has_bit(bitsmap, number):
    """Bitmaps do kernel vêm como palavras de 64 bits, da mais alta para a
    mais baixa, sem zero-padding (ex.: 'ff0000 0 0 0 0')."""
    if not bitsmap:
        return False
    try:
        value = 0
        for word in bitsmap.split():
            value = (value << 64) | int(word, 16)
        return bool((value >> number) & 1)
    except ValueError:
        return False


def unique_key(device):
    """Mesma chave usada pelo input-remapper para agrupar as interfaces de um
    mesmo dispositivo físico."""
    phys = device["phys"].split("/")[0] or "-"
    return f"{device['bus']}_{device['vendor']}_{device['product']}_{device['uniq']}_{phys}"


def is_mouse(devices):
    for device in devices:
        bits = device["bits"]
        if (
            has_bit(bits.get("REL"), REL_X)
            and has_bit(bits.get("REL"), REL_Y)
            and has_bit(bits.get("KEY"), BTN_LEFT)
        ):
            return True
    return False


# Agrupa as interfaces e seleciona apenas os mouses
grupos = {}
for device in parse_proc():
    if device["name"] == "Power Button":
        continue
    # Ignora os dispositivos virtuais criados pelo próprio input-remapper para
    # não reconfigurar a injeção (isso poderia causar recursão).
    if device["name"].startswith("input-remapper"):
        continue
    grupos.setdefault(unique_key(device), []).append(device)

mouses = []
for group_key, devices in grupos.items():
    if not is_mouse(devices):
        continue
    # O input-remapper usa o menor nome do grupo como nome do perfil E como
    # chave do autoload (group.key). O agrupamento acima serve só para juntar
    # as interfaces do mesmo dispositivo físico.
    name = sorted((device["name"] for device in devices), key=len)[0]
    available = {
        button
        for device in devices
        for button in BTN_CANDIDATES
        if has_bit(device["bits"].get("KEY"), button)
    }
    mouses.append((name, available))

if not mouses:
    print("   ⚠️  Nenhum mouse detectado em /proc/bus/input/devices")
    sys.exit(1)

# Botão forçado manualmente (ex.: BTN_SIDE), se configurado
forced = None
if BUTTON_PREF != "auto":
    forced = getattr(ecodes, BUTTON_PREF, None)
    if forced is None:
        print(f"   ❌ Botão inválido: {BUTTON_PREF}")
        sys.exit(1)

config = GlobalConfig()
config.load_config()

for name, available in mouses:
    button = forced
    if button is None or button not in available:
        if forced is not None:
            print(f'   ⚠️  "{name}" não expõe {BUTTON_PREF}; usando detecção automática')
        button = next((candidate for candidate in BTN_CANDIDATES if candidate in available), None)

    if button is None:
        print(f'   ⚠️  "{name}" não possui botões laterais (BTN_SIDE/BTN_EXTRA/...)')
        continue

    preset_path = PathUtils.get_preset_path(name, PRESET_NAME)
    preset = Preset(preset_path)
    preset.empty()
    preset.add(Mapping(
        input_combination=InputCombination(
            [InputConfig(type=ecodes.EV_KEY, code=button)]
        ),
        target_uinput="keyboard",
        output_symbol=MACRO,
        name="Fechar aba (Botão Avançar)",
    ))
    preset.save()

    config.set_autoload_preset(name, PRESET_NAME)

    print(f"   ✅ {name}: {ecodes.bytype[ecodes.EV_KEY][button]} → {MACRO}")
    print(f"      preset: {preset_path}")
PY
    then
        echo "   ❌ Falha ao configurar o botão do mouse"
        return
    fi

    if input-remapper-control --command autoload 2>/dev/null; then
        echo "   ✅ Preset aplicado"
    else
        echo "   ⚠️  Reinicie a sessão ou rode: sudo systemctl restart input-remapper-daemon.service"
    fi
}

aplicar_apps_padrao() {
    echo
    echo "=== ➡️ Definindo aplicativos padrão ==="

    if ! command -v xdg-mime &>/dev/null; then
        echo "⚠️  Comando 'xdg-mime' não encontrado."
        return
    fi

    echo "➡️ Arquivos .txt (text/plain) → gedit"
    if xdg-mime default org.gnome.gedit.desktop text/plain 2>/dev/null; then
        echo "   ✅ gedit definido como padrão para text/plain"
    else
        echo "   ❌ Falha ao definir gedit como padrão"
    fi
}

aplicar_configuracoes_terminal() {
    echo
    echo "=== ➡️ Configurando cores do terminal (Verde no Preto) ==="

    if ! command -v gsettings &>/dev/null; then
        echo "⚠️  Comando 'gsettings' não encontrado."
        return
    fi

    # 1. Pega o UUID do perfil padrão.
    #    Importante: quando o usuário nunca alterou o perfil, o dconf está vazio
    #    e os valores vêm apenas do schema (default). Por isso consultamos o
    #    gsettings primeiro; o dconf fica como fallback.
    local uuid_regex="[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}"
    local perfil_id

    perfil_id=$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null \
        | grep -o -E "$uuid_regex" | head -n 1)

    if [ -z "$perfil_id" ]; then
        perfil_id=$(dconf read /org/gnome/terminal/legacy/profiles:/default 2>/dev/null \
            | grep -o -E "$uuid_regex" | head -n 1)
    fi

    if [ -z "$perfil_id" ]; then
        perfil_id=$(gsettings get org.gnome.Terminal.ProfilesList list 2>/dev/null \
            | grep -o -E "$uuid_regex" | head -n 1)
    fi

    # Último recurso: UUID do perfil criado automaticamente pelo GNOME Terminal
    if [ -z "$perfil_id" ]; then
        perfil_id="b1dcc9dd-5262-4d8d-a863-c897e6d979b9"
    fi

    echo "   Perfil encontrado: $perfil_id"

    local esquema="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${perfil_id}/"

    # 2. Configura as cores e desativa as cores do tema
    local configs=(
        "use-theme-colors" "false"
        "background-color" "'#000000'"
        "foreground-color" "'#00ff00'"
        "visible-name" "'Verde no Preto'"
    )

    local i chave valor sucesso=0 falha=0
    for ((i = 0; i < ${#configs[@]}; i += 2)); do
        chave="${configs[$i]}"
        valor="${configs[$((i + 1))]}"

        if gsettings set "$esquema" "$chave" "$valor" 2>/dev/null; then
            sucesso=$((sucesso + 1))
        else
            echo "   ❌ Falha ao aplicar $chave"
            falha=$((falha + 1))
        fi
    done

    if [ "$falha" -eq 0 ]; then
        echo "   ✅ Cores 'verde no preto' aplicadas com sucesso no perfil!"
    else
        echo "   ⚠️  Algumas chaves não puderam ser aplicadas ($falha falha(s))."
    fi

    echo "   ℹ️  Feche e reabra o terminal para ver o resultado."
}

main() {
    aplicar_configuracoes
    aplicar_atalhos
    aplicar_botao_mouse
    aplicar_apps_padrao
    aplicar_configuracoes_terminal

    echo
    echo "ℹ️  Algumas alterações podem exigir reiniciar a sessão para surtir efeito."
}

main
