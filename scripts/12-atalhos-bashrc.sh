#!/bin/bash
set -e

appNome="Atalhos do Bash"

MARCADOR_INICIO="# === Atalhos Bash - meu-debian (início) ==="
MARCADOR_FIM="# === Atalhos Bash - meu-debian (fim) ==="

MODO="instalar"

mostrar_ajuda() {
    cat << 'AJUDA'
USO: ./scripts/atalhos-bashrc.sh [opções]

Adiciona um conjunto de atalhos (aliases e funções) ao .bashrc.

Opções:
  (sem opção)     Instala os atalhos
  -r, --remover   Remove os atalhos instalados
  -h, --ajuda     Mostra esta ajuda

Observações:
  - Execute sem sudo para configurar o usuário atual, o root e o /etc/skel.
  - Se executado como root via sudo, também configura o usuário que chamou o sudo.
  - O bloco é idempotente: executar novamente não duplica as linhas.

Atalhos disponíveis:
  Listagem/navegação : ll, la, l, .., ..., ...., home, docs, downloads, cls, h
  Segurança          : cp, mv, rm (com confirmação)
  APT                : att, inst, rem, limp
  Sistema            : discos, memoria, portas, processos, top10, servicos,
                       log, meuip, reiniciar, desligar
  Git                : gs, ga, gaa, gc, gp, gpl, gl, gd, gb, gco, gcl
  Docker             : dps, dpsa, dc, dcu, dcd, dcl, dprune
  Editores (Flatpak) : code
  Funções            : mkcd, extrair, quemusa
AJUDA
}

adicionar_atalhos() {
    local bashrc_path="$1"

    if grep -q "$MARCADOR_INICIO" "$bashrc_path" 2>/dev/null; then
        echo "=== ⚠️ Os atalhos já estão instalados em $bashrc_path ==="
        return
    fi

    echo "=== ➡️ Adicionando atalhos em $bashrc_path ==="
    [ -f "$bashrc_path" ] || touch "$bashrc_path"

    cat >> "$bashrc_path" << 'ATALHOS_EOF'

# === Atalhos Bash - meu-debian (início) ===
# Bloco gerenciado por scripts/atalhos-bashrc.sh - não edite manualmente.

# --- Listagem e navegação ---
alias ll='ls -alFh --group-directories-first'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias home='cd ~'
alias docs='cd ~/Documentos'
alias downloads='cd ~/Downloads'
alias cls='clear'
alias h='history'

# --- Segurança ---
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -I --preserve-root'

# --- APT ---
alias att='sudo apt update && sudo apt full-upgrade -y'
alias inst='sudo apt install -y'
alias rem='sudo apt remove -y'
alias limp='sudo apt autoremove -y && sudo apt autoclean'

# --- Sistema ---
alias discos='df -h'
alias memoria='free -h'
alias portas='sudo ss -tulpn'
alias processos='ps aux --sort=-%mem | head -n 15'
alias top10='ps aux --sort=-%cpu | head -n 11'
alias servicos='systemctl list-units --type=service --state=running'
alias log='journalctl -xe'
alias meuip='curl -s https://ifconfig.me/ip && echo'
alias reiniciar='sudo reboot'
alias desligar='sudo poweroff'

# --- Git ---
alias gs='git status -sb'
alias ga='git add'
alias gaa='git add -A'
alias gc='git commit -m'
alias gp='git push'
alias gpl='git pull'
alias gl='git log --oneline --graph --decorate -15'
alias gd='git diff'
alias gb='git branch'
alias gco='git checkout'
alias gcl='git clone'

# --- Docker ---
alias dps='docker ps'
alias dpsa='docker ps -a'
alias dc='docker compose'
alias dcu='docker compose up -d'
alias dcd='docker compose down'
alias dcl='docker compose logs -f'
alias dprune='docker system prune -af'

# --- Editores (Flatpak) ---
alias code='flatpak run com.visualstudio.code'

# --- Funções úteis ---
mkcd() {
    mkdir -p "$1" && cd "$1" || return 1
}

extrair() {
    if [ -z "$1" ]; then
        echo "Uso: extrair <arquivo>"
        return 1
    fi
    case "$1" in
        *.tar.bz2|*.tbz2) tar -xjf "$1" ;;
        *.tar.gz|*.tgz)   tar -xzf "$1" ;;
        *.tar.xz|*.txz)   tar -xJf "$1" ;;
        *.tar)            tar -xf "$1" ;;
        *.zip)            unzip "$1" ;;
        *.rar)            unrar x "$1" ;;
        *.7z)             7z x "$1" ;;
        *.gz)             gunzip "$1" ;;
        *.bz2)            bunzip2 "$1" ;;
        *)                echo "Formato não suportado: $1"; return 1 ;;
    esac
}

quemusa() {
    if [ -z "$1" ]; then
        echo "Uso: quemusa <porta>"
        return 1
    fi
    sudo ss -tulpn | grep ":$1 " || echo "Nenhum processo usando a porta $1"
}

# === Atalhos Bash - meu-debian (fim) ===
ATALHOS_EOF

    echo "=== ✅ Atalhos adicionados a $bashrc_path ==="
}

remover_atalhos() {
    local bashrc_path="$1"

    if [ ! -f "$bashrc_path" ] || ! grep -q "$MARCADOR_INICIO" "$bashrc_path" 2>/dev/null; then
        echo "=== ⚠️ Nenhum atalho encontrado em $bashrc_path ==="
        return
    fi

    echo "=== ➡️ Removendo atalhos de $bashrc_path ==="
    sed -i "\|^${MARCADOR_INICIO}$|,\|^${MARCADOR_FIM}$|d" "$bashrc_path"
    echo "=== ✅ Atalhos removidos de $bashrc_path ==="
}

aplicar_em() {
    if [ "$MODO" = "remover" ]; then
        remover_atalhos "$1"
    else
        adicionar_atalhos "$1"
    fi
}

executar_como_root() {
    local bashrc_path="$1"
    sudo bash -c "$(declare -f adicionar_atalhos remover_atalhos aplicar_em); MODO='$MODO'; aplicar_em '$bashrc_path'"
}

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

echo "=============================================="
echo "  🔧 $appNome - ${MODO^}"
echo "=============================================="
echo

if [ "$(id -u)" -eq 0 ]; then
    aplicar_em "/root/.bashrc"

    if [ -f /etc/skel/.bashrc ] || [ -d /etc/skel ]; then
        aplicar_em "/etc/skel/.bashrc"
    fi

    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        home_usuario=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        if [ -n "$home_usuario" ] && [ -f "$home_usuario/.bashrc" ]; then
            sudo -u "$SUDO_USER" bash -c "$(declare -f adicionar_atalhos remover_atalhos aplicar_em); MODO='$MODO'; aplicar_em '$home_usuario/.bashrc'"
        fi
    fi
else
    aplicar_em "$HOME/.bashrc"
    executar_como_root "/root/.bashrc"

    if [ -f /etc/skel/.bashrc ] || [ -d /etc/skel ]; then
        executar_como_root "/etc/skel/.bashrc"
    fi
fi

echo
echo "=============================================="
if [ "$MODO" = "remover" ]; then
    echo "✅ $appNome removidos!"
else
    echo "✅ $appNome instalados!"
    echo
    echo "  Para aplicar agora, execute:"
    echo "  source ~/.bashrc"
    echo
    echo "  Para ver todos os atalhos:"
    echo "  alias"
fi
echo "=============================================="
