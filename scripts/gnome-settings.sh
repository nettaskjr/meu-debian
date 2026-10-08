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
    "org.gnome.desktop.peripherals.mouse" "natural-scroll" "true"
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

main() {
    aplicar_configuracoes

    echo
    echo "ℹ️  Algumas alterações podem exigir reiniciar a sessão para surtir efeito."
}

main
