#!/bin/bash
set -e

appNome="Usuário Sudo"

echo "=============================================="
echo "  🔧 $appNome"
echo "=============================================="
echo

listar_usuarios_nao_sistema() {
    echo "=== ➡️ Usuários não-sistema disponíveis: ==="
    awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd
    echo
}

adicionar_usuario_ao_sudo() {
    local usuario="$1"

    if groups "$usuario" 2>/dev/null | grep -qw "sudo"; then
        echo "⚠️  O usuário '$usuario' já pertence ao grupo sudo."
        return 1
    fi

    sudo usermod -aG sudo "$usuario"
    echo "✅  Usuário '$usuario' adicionado ao grupo sudo com sucesso!"
    return 0
}

adicionar_todos_ao_sudo() {
    local usuarios
    usuarios=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd)
    local adicionados=0
    local ignorados=0

    for usuario in $usuarios; do
        if groups "$usuario" 2>/dev/null | grep -qw "sudo"; then
            echo "⚠️  '$usuario' já está no grupo sudo — ignorando."
            ((ignorados++))
        else
            sudo usermod -aG sudo "$usuario"
            echo "✅  '$usuario' adicionado ao grupo sudo."
            ((adicionados++))
        fi
    done

    echo
    echo "=============================================="
    echo "✅  Concluído: $adicionados usuários adicionados, $ignorados já existentes."
    echo "=============================================="
}

echo "Escolha uma opção:"
echo "  1) Informar o nome de um usuário específico"
echo "  2) Adicionar todos os usuários não-sistema ao grupo sudo"
echo "  3) Sair"
echo
read -r -p "Opção [1-3]: " opcao

case "$opcao" in
    1)
        echo
        listar_usuarios_nao_sistema
        read -r -p "Digite o nome do usuário: " usuario_alvo

        if [ -z "$usuario_alvo" ]; then
            echo "❌ Nenhum nome de usuário informado."
            exit 1
        fi

        if ! id "$usuario_alvo" &>/dev/null; then
            echo "❌ Usuário '$usuario_alvo' não existe no sistema."
            exit 1
        fi

        uid=$(id -u "$usuario_alvo")
        if [ "$uid" -lt 1000 ]; then
            echo "❌ '$usuario_alvo' é um usuário de sistema (UID=$uid)."
            exit 1
        fi

        adicionar_usuario_ao_sudo "$usuario_alvo"
        ;;
    2)
        echo
        adicionar_todos_ao_sudo
        ;;
    3)
        echo "Saindo..."
        exit 0
        ;;
    *)
        echo "❌ Opção inválida."
        exit 1
        ;;
esac

echo
echo "=============================================="
echo "  Para aplicar a alteração, execute:"
echo "  source /etc/sudoers"
echo "=============================================="
