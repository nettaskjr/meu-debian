#!/bin/bash
set -e

appNome="Configurações GNOME (gsettings)"

# Botão lateral "avançar" do mouse -> <Ctrl>+<F4> (fecha a aba) via input-remapper.
# Consulte o nome do dispositivo com: input-remapper-control --list-devices
MOUSE_DEVICE="HREBOS-299 Mouse"        # nome do mouse
MOUSE_FORWARD_BUTTON="BTN_EXTRA"       # botão 9 (avançar). Use "BTN_SIDE" para o "voltar"
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

    if ! python3 - "$MOUSE_DEVICE" "$MOUSE_PRESET" "$MOUSE_FORWARD_BUTTON" "$MOUSE_FORWARD_MACRO" <<'PY'
import sys
from evdev import ecodes
from inputremapper.configs.paths import PathUtils
from inputremapper.configs.preset import Preset
from inputremapper.configs.mapping import Mapping
from inputremapper.configs.input_config import InputCombination, InputConfig
from inputremapper.configs.global_config import GlobalConfig

device, preset_name, button, macro = sys.argv[1:5]

code = getattr(ecodes, button, None)
if code is None:
    print(f'Botão inválido: {button}', file=sys.stderr)
    sys.exit(1)

caminho = PathUtils.get_preset_path(device, preset_name)
preset = Preset(caminho)
preset.empty()
preset.add(Mapping(
    input_combination=InputCombination([InputConfig(type=ecodes.EV_KEY, code=code)]),
    target_uinput="keyboard",
    output_symbol=macro,
    name="Fechar aba (Botão Avançar)",
))
preset.save()

config = GlobalConfig()
config.load_config()
config.set_autoload_preset(device, preset_name)

print(f"   ✅ Preset salvo em {caminho}")
print(f"   ✅ Autoload registrado para '{device}'")
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

    if ! command -v dconf &>/dev/null; then
        echo "⚠️  Comando 'dconf' não encontrado."
        return
    fi

    # 1. Pega o UUID do perfil padrão atual (remover aspas se houver)
    local perfil_id
    perfil_id=$(dconf read /org/gnome/terminal/legacy/profiles:/default 2>/dev/null | tr -d "'")

    # Se a chave 'default' estiver vazia, tenta extrair o primeiro UUID da lista
    if [ -z "$perfil_id" ]; then
        perfil_id=$(dconf read /org/gnome/terminal/legacy/profiles:/list 2>/dev/null | grep -o -E "[a-f0-9-]{36}" | head -n 1)
    fi

    if [ -z "$perfil_id" ]; then
        echo "⚠️  Não foi possível identificar o perfil atual do terminal."
        return
    fi

    echo "   Perfil encontrado: $perfil_id"
    local base_path="/org/gnome/terminal/legacy/profiles:/$perfil_id/"

    # 2. Configura as cores e desativa as cores do tema
    dconf write "${base_path}use-theme-colors" "false" 2>/dev/null
    dconf write "${base_path}background-color" "'#000000'" 2>/dev/null
    dconf write "${base_path}foreground-color" "'#00ff00'" 2>/dev/null

    # Opcional: define um nome legível para o perfil
    dconf write "${base_path}visible-name" "'Verde no Preto'" 2>/dev/null

    echo "   ✅ Cores 'verde no preto' aplicadas com sucesso no perfil!"
}

main() {
    aplicar_configuracoes
    aplicar_atalhos
    #aplicar_botao_mouse
    aplicar_apps_padrao
    aplicar_configuracoes_terminal

    echo
    echo "ℹ️  Algumas alterações podem exigir reiniciar a sessão para surtir efeito."
}

main
