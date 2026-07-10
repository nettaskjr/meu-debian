#!/bin/bash
set -e

appNome="Prompt Personalizado"
appNomeLower=$(echo "$appNome" | tr '[:upper:]' '[:lower:]')

echo "=== ➡️ Instalando $appNome ==="

PROMPT_MARKER="# === Prompt Personalizado - meu-debian ==="

instalar_prompt() {
    local bashrc_path="$1"
    local cor_usuario="$2"
    local tipo="$3"

    if grep -q "$PROMPT_MARKER" "$bashrc_path" 2>/dev/null; then
        echo "=== ⚠️ O prompt ($tipo) já está instalado em $bashrc_path ==="
        return
    fi

    echo "=== ➡️ Adicionando configuração do prompt ($tipo) em $bashrc_path ==="

    echo "" >> "$bashrc_path"
    echo "$PROMPT_MARKER" >> "$bashrc_path"

    cat >> "$bashrc_path" << 'GITFUNC'

parse_git_branch() {
    local branch
    branch=$(git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/')
    if [ -n "$branch" ]; then
        printf " \001\033[01;33m\002(\001\033[01;36m\002⎇ %s\001\033[01;33m\002)\001\033[00m\002" "$branch"
    fi
}
GITFUNC

    printf 'PS1="\\[\\033[01;%sm\\]\\u@\\h \\$(lsb_release -cs)\\[\\033[00m\\] \\[\\033[01;34m\\]\\w\\[\\033[00m\\]\\$(parse_git_branch)\\n\\[\\033[01;%sm\\]\\342\\224\\224\\342\\224\\200\\342\\224\\200> \\[\\033[00m\\]"\n' "$cor_usuario" "$cor_usuario" >> "$bashrc_path"

    echo "=== ✅ Prompt ($tipo) adicionado a $bashrc_path ==="
}

echo
echo "=== ➡️ Configurando prompt para o usuário atual ==="

if [ "$(id -u)" -eq 0 ]; then
    instalar_prompt "/root/.bashrc" "31" "root"
else
    instalar_prompt "$HOME/.bashrc" "32" "usuário"

    echo
    echo "=== ➡️ Configurando prompt para o root ==="
    if [ -f /root/.bashrc ] || [ -d /root ]; then
        sudo bash -c "PROMPT_MARKER='$PROMPT_MARKER'; $(declare -f instalar_prompt); instalar_prompt /root/.bashrc 31 root"
    else
        echo "=== ⚠️ Arquivo /root/.bashrc não encontrado. Pulando ==="
    fi

    echo
    echo "=== ➡️ Configurando prompt para novos usuários (/etc/skel) ==="
    if [ -f /etc/skel/.bashrc ] || [ -d /etc/skel ]; then
        sudo bash -c "PROMPT_MARKER='$PROMPT_MARKER'; $(declare -f instalar_prompt); instalar_prompt /etc/skel/.bashrc 32 skel"
    else
        echo "=== ⚠️ Diretório /etc/skel não encontrado. Pulando ==="
    fi
fi

echo
echo "=============================================="
echo "  Para aplicar o novo prompt, execute:"
echo "  source ~/.bashrc"
echo
echo "  Formato do prompt:"
echo "  usuário@host codename ~/caminho (⎇ branch)"
echo "  └──> "
echo
echo "  Cores: verde = usuário  |  vermelho = root"
echo "=============================================="
echo "✅ $appNome configurado com sucesso!"
echo "=============================================="
