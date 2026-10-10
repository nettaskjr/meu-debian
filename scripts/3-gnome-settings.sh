#!/bin/bash
set -e

appNome="Configurações GNOME (gsettings)"

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
    "org.gnome.desktop.interface" "enable-animations" "false"
    "org.gnome.desktop.wm.preferences" "button-layout" "'appmenu:minimize,close'"
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
    aplicar_configuracoes_terminal

    echo
    echo "ℹ️  Algumas alterações podem exigir reiniciar a sessão para surtir efeito."
}

main
