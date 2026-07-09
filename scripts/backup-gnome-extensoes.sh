#!/bin/bash
set -e

appNome="Backup Extensões GNOME"

DIR_EXTENSOES="$HOME/.local/share/gnome-shell/extensions"
DIR_BACKUP_BASE="$HOME/backups/gnome-extensoes"
DATA=$(date +%Y-%m-%d_%H-%M-%S)
DIR_BACKUP="$DIR_BACKUP_BASE/$DATA"

# --------------------------------------------------

listar_extensoes_instaladas() {
    local dir="$1"

    if [ -z "$dir" ] || [ ! -d "$dir" ]; then
        return
    fi

    for ext in "$dir"/*; do
        if [ -d "$ext" ]; then
            local nome_ext
            nome_ext=$(basename "$ext")

            if [ -f "$ext/metadata.json" ]; then
                nome=$(python3 -c "import json; print(json.load(open('$ext/metadata.json')).get('name', '$nome_ext'))" 2>/dev/null || echo "$nome_ext")
                versao=$(python3 -c "import json; print(json.load(open('$ext/metadata.json')).get('version', '?'))" 2>/dev/null || echo "?")
            else
                nome="$nome_ext"
                versao="?"
            fi

            echo "  • $nome ($nome_ext) v$versao"
        fi
    done
}

gerar_relatorio() {
    {
        echo "=============================================="
        echo " Backup de Extensões GNOME"
        echo "=============================================="
        echo "Data: $(date '+%d/%m/%Y %H:%M:%S')"
        echo "Host: $(hostname)"
        echo "Usuário: $USER"
        echo "Versão GNOME: $(gnome-shell --version 2>/dev/null || echo 'N/D')"
        echo "------------------------------------------------"
        echo "Extensões copiadas:"
        echo
        listar_extensoes_instaladas "$DIR_EXTENSOES"
        echo "=============================================="
    } > "$DIR_BACKUP/relatorio.txt"
}

recarregar_gnome_shell() {
    if [ -n "$DISPLAY" ] && [ -n "$XDG_SESSION_DESKTOP" ]; then
        if busctl --user call org.gnome.Shell /org/gnome/Shell org.gnome.Shell Eval s 'Meta.restart("Restaurando extensões...")' 2>/dev/null; then
            return
        fi

        if gdbus call --session --dest org.gnome.Shell --object-path /org/gnome/Shell --method org.gnome.Shell.Eval 'Meta.restart("Restaurando extensões...")' 2>/dev/null; then
            return
        fi
    fi

    echo "⚠️  Não foi possível recarregar o GNOME Shell automaticamente."
    echo "    Pressione Alt+F2, digite 'r' e Enter, ou reinicie a sessão."
}

# --------------------------------------------------

fazer_backup() {
    echo
    echo "=== ➡️ Criando diretório de backup em: $DIR_BACKUP ==="
    mkdir -p "$DIR_BACKUP"

    echo "=== ➡️ Copiando extensões instaladas ==="
    cp -a "$DIR_EXTENSOES" "$DIR_BACKUP/extensoes"

    local qtd_extensoes
    qtd_extensoes=$(ls -1 "$DIR_EXTENSOES" | wc -l)
    echo "✅  $qtd_extensoes extensões copiadas."

    echo "=== ➡️ Exportando configurações das extensões (dconf) ==="
    dconf dump /org/gnome/shell/extensions/ > "$DIR_BACKUP/extensoes-dconf.conf"

    echo "=== ➡️ Exportando lista de extensões habilitadas ==="
    dconf read /org/gnome/shell/enabled-extensions > "$DIR_BACKUP/enabled-extensions.txt"
    dconf read /org/gnome/shell/disabled-extensions > "$DIR_BACKUP/disabled-extensions.txt" 2>/dev/null || true

    echo "=== ➡️ Gerando relatório do backup ==="
    gerar_relatorio

    echo
    echo "=============================================="
    echo "✅  Backup concluído com sucesso!"
    echo
    echo "  Local: $DIR_BACKUP"
    echo "  Extensões: $qtd_extensoes"
    echo
    cat "$DIR_BACKUP/relatorio.txt"
    echo
}

restaurar_backup() {
    local backups=()
    mapfile -t backups < <(ls -1dt "$DIR_BACKUP_BASE"/*/ 2>/dev/null || true)

    if [ ${#backups[@]} -eq 0 ]; then
        echo "❌ Nenhum backup encontrado em: $DIR_BACKUP_BASE"
        exit 1
    fi

    echo "Backups disponíveis:"
    local i
    for i in "${!backups[@]}"; do
        local nome_backup info
        nome_backup=$(basename "${backups[$i]}")
        if [ -f "${backups[$i]}relatorio.txt" ]; then
            info=$(head -4 "${backups[$i]}relatorio.txt")
        else
            info="Sem relatório"
        fi
        echo "  $((i+1))) $nome_backup"
    done
    echo

    local num
    read -r -p "Escolha o número do backup para restaurar: " num

    if ! [[ "$num" =~ ^[0-9]+$ ]] || [ "$num" -lt 1 ] || [ "$num" -gt "${#backups[@]}" ]; then
        echo "❌ Opção inválida."
        exit 1
    fi

    local backup_escolhido
    backup_escolhido="${backups[$((num-1))]}"

    echo
    echo "=== ➡️ Restaurando backup: $(basename "$backup_escolhido") ==="

    if [ -d "$DIR_EXTENSOES" ]; then
        echo "=== ➡️ Movendo extensões atuais para backup de segurança ==="
        mv "$DIR_EXTENSOES" "$DIR_EXTENSOES.bak-$(date +%Y%m%d%H%M%S)"
    fi

    echo "=== ➡️ Restaurando extensões ==="
    cp -a "$backup_escolhido/extensoes" "$DIR_EXTENSOES"

    echo "=== ➡️ Restaurando configurações dconf ==="
    dconf load /org/gnome/shell/extensions/ < "$backup_escolhido/extensoes-dconf.conf"

    echo "=== ➡️ Recarregando GNOME Shell ==="
    recarregar_gnome_shell

    echo
    echo "=============================================="
    echo "✅  Backup restaurado com sucesso!"
    echo "=============================================="
}

menu() {
    echo "=============================================="
    echo "  📦 $appNome"
    echo "=============================================="
    echo
    echo "Escolha uma opção:"
    echo "  1) Fazer backup das extensões e configurações"
    echo "  2) Restaurar um backup existente"
    echo "  3) Sair"
    echo
}

# --------------------------------------------------

main() {
    if [ ! -d "$DIR_EXTENSOES" ]; then
        echo "❌ Diretório de extensões não encontrado: $DIR_EXTENSOES"
        exit 1
    fi

    menu

    local opcao
    read -r -p "Opção [1-3]: " opcao

    case "$opcao" in
        1) fazer_backup  ;;
        2) restaurar_backup ;;
        3) echo "Saindo..."; exit 0 ;;
        *) echo "❌ Opção inválida."; exit 1 ;;
    esac

    echo
}

main
