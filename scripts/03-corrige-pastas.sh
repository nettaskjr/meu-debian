#!/bin/bash
set -e

# =============================================================================
#  13-corrige-pastas.sh - Links das pastas do Google Drive no diretório HOME
#
#  FUNÇÃO DESTE SCRIPT:
#  O Insync mantém as pastas do Google Drive em um caminho longo, com espaços
#  e acentos (por exemplo:
#     /mnt/FILE_SERVER/Insync/nestor.junior@gmail.com/Google Drive/Downloads).
#  Este script cria atalhos (links simbólicos) em ~/ para essas pastas, de modo
#  que ~/Downloads, ~/Documentos, ~/Imagens etc. apontem para o Google Drive.
#
#  VERSÃO ANTERIOR (scripts/outros/corrige_pastas.sh):
#  Havia um espaço depois do sinal de igual em:
#     PASTA_ORIGEM= "/mnt/FILE_SERVER/..."
#  O Bash interpretava PASTA_ORIGEM como vazio e tentava executar o caminho
#  como um comando. Com isso, os links eram criados apontando para /AppImages,
#  /Documentos etc. (caminhos inexistentes), ficando todos quebrados.
#
#  O que este script faz:
#   1. Descobre automaticamente a pasta do Google Drive (desktop ou notebook);
#   2. Confere se cada pasta de origem realmente existe antes de criar o link;
#   3. Se o link já estiver correto, não faz nada (idempotente);
#   4. Se houver um link errado, remove e recria;
#   5. Se houver uma pasta real em ~/, move para <nome>.old (sem sobrescrever
#      um backup anterior: nesse caso usa <nome>.old.<data>-<hora>);
#   6. Cria o link simbólico para a pasta correspondente no Google Drive;
#   7. Ao final, mostra um resumo do que foi feito.
#
#  Uso:
#    ./scripts/13-corrige-pastas.sh                     # aplica as correções
#    ./scripts/13-corrige-pastas.sh --simular           # só mostra o que faria
#    ./scripts/13-corrige-pastas.sh --origem CAMINHO    # força outra origem
#    ./scripts/13-corrige-pastas.sh --ajuda             # mostra esta ajuda
#
#  Execute como usuário comum, NUNCA com sudo: os links devem pertencer a você.
# =============================================================================

appNome="Pastas do Google Drive no HOME"

# Caminhos possíveis do Insync. O primeiro que existir será usado.
ORIGEM_DESKTOP="/mnt/FILE_SERVER/Insync/nestor.junior@gmail.com/Google Drive"
ORIGEM_NOTEBOOK="$HOME/Insync/nestor.junior@gmail.com/Google Drive"
PASTA_ORIGEM=""

PASTAS=("AppImages" "Backups" "Documentos" "Downloads" "Imagens" "Modelos" "Músicas" "Projetos-Github" "Público" "Vídeos")

MODO="aplicar"
ORIGEM_INFORMADA=""

# Contadores do resumo final.
CRIADOS=0
CORRIGIDOS=0
JA_CORRETOS=0
PASTAS_MOVIDAS=0
IGNORADOS=0

mostrar_ajuda() {
    cat << 'AJUDA'
USO: ./scripts/13-corrige-pastas.sh [opções]

Cria links simbólicos em ~/ para as pastas do Google Drive sincronizadas pelo
Insync (AppImages, Backups, Documentos, Downloads, Imagens, Modelos, Músicas,
Público e Vídeos).

Opções:
  (sem opção)        Aplica as correções
  -n, --simular      Mostra o que seria feito, sem alterar nada (dry-run)
  -o, --origem PATH  Usa uma pasta de origem específica do Google Drive
  -h, --ajuda        Mostra esta ajuda

Observações:
  - Execute como usuário comum, sem sudo.
  - Pastas reais já existentes em ~/ são preservadas como <nome>.old.
  - Links que já apontam para o lugar certo não são alterados.
  - Se a pasta de origem não existir, o item é ignorado com aviso.
AJUDA
}

# -----------------------------------------------------------------------------
# Escolhe a pasta de origem: a informada pelo usuário ou a primeira que existir.
# -----------------------------------------------------------------------------
definir_origem() {
    local candidato

    if [ -n "$ORIGEM_INFORMADA" ]; then
        if [ ! -d "$ORIGEM_INFORMADA" ]; then
            echo "❌ Pasta de origem não encontrada: $ORIGEM_INFORMADA"
            exit 1
        fi
        PASTA_ORIGEM="$ORIGEM_INFORMADA"
    else
        for candidato in "$ORIGEM_NOTEBOOK" "$ORIGEM_DESKTOP"; do
            if [ -d "$candidato" ]; then
                PASTA_ORIGEM="$candidato"
                break
            fi
        done
    fi

    if [ -z "$PASTA_ORIGEM" ]; then
        echo "❌ Pasta do Google Drive não encontrada."
        echo "   Procurei em:"
        echo "     $ORIGEM_NOTEBOOK"
        echo "     $ORIGEM_DESKTOP"
        echo "   Informe o caminho com: --origem \"CAMINHO\""
        exit 1
    fi

    # Remove barra final, se houver, para não gerar links com //.
    PASTA_ORIGEM="${PASTA_ORIGEM%/}"
    echo "=== ➡️ Origem: $PASTA_ORIGEM ==="
}

# -----------------------------------------------------------------------------
# Cria/atualiza o link de uma pasta. Recebe apenas o nome da pasta.
# -----------------------------------------------------------------------------
processar_pasta() {
    local pasta="$1"
    local destino="$HOME/$pasta"
    local origem="$PASTA_ORIGEM/$pasta"
    local backup

    if [ ! -d "$origem" ]; then
        echo "=== ⚠️ Origem não encontrada, ignorando: $origem ==="
        IGNORADOS=$((IGNORADOS + 1))
        return
    fi

    # Link já aponta para o lugar certo: nada a fazer.
    if [ -L "$destino" ] && [ "$(readlink "$destino")" = "$origem" ]; then
        echo "=== ✅ $pasta já está correto: ~/$pasta -> $origem ==="
        JA_CORRETOS=$((JA_CORRETOS + 1))
        return
    fi

    # Link existente, mas apontando para outro lugar (inclusive link quebrado).
    if [ -L "$destino" ]; then
        if [ "$MODO" = "simular" ]; then
            echo "=== 🔎 [simulação] Removeria o link incorreto ~/$pasta ($(readlink "$destino")) ==="
        else
            echo "=== ➡️ Removendo link incorreto ~/$pasta ($(readlink "$destino")) ==="
            rm -f -- "$destino"
        fi
        CORRIGIDOS=$((CORRIGIDOS + 1))
    # Pasta ou arquivo real: preserva como .old antes de criar o link.
    elif [ -e "$destino" ]; then
        backup="$destino.old"
        if [ -e "$backup" ] || [ -L "$backup" ]; then
            backup="$destino.old.$(date +%Y%m%d-%H%M%S)"
        fi

        if [ "$MODO" = "simular" ]; then
            echo "=== 🔎 [simulação] Moveria ~/$pasta para $backup ==="
        else
            echo "=== ➡️ Movendo ~/$pasta para $backup ==="
            mv -- "$destino" "$backup"
        fi
        PASTAS_MOVIDAS=$((PASTAS_MOVIDAS + 1))
    else
        CRIADOS=$((CRIADOS + 1))
    fi

    if [ "$MODO" = "simular" ]; then
        echo "=== 🔎 [simulação] Criaria o link ~/$pasta -> $origem ==="
    else
        echo "=== ➡️ Criando link: ~/$pasta -> $origem ==="
        ln -s -- "$origem" "$destino"
        echo "=== ✅ Link criado ==="
    fi
}

# =============================================================================
# Execução
# =============================================================================

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--simular|--dry-run)
            MODO="simular"
            ;;
        -o|--origem)
            shift
            if [ -z "${1:-}" ]; then
                echo "❌ A opção --origem exige um caminho."
                exit 1
            fi
            ORIGEM_INFORMADA="$1"
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
    shift
done

if [ "$(id -u)" -eq 0 ]; then
    echo "❌ Não execute este script como root ou com sudo."
    echo "   Os links precisam pertencer ao seu usuário."
    exit 1
fi

echo "=============================================="
echo "  🔧 $appNome"
echo "=============================================="
echo

definir_origem
echo

for pasta in "${PASTAS[@]}"; do
    processar_pasta "$pasta"
done

echo
echo "=============================================="
if [ "$MODO" = "simular" ]; then
    echo "🔎 Simulação concluída (nada foi alterado)"
else
    echo "✅ $appNome configuradas!"
fi
echo
echo "  Links criados .........: $CRIADOS"
echo "  Links corrigidos ......: $CORRIGIDOS"
echo "  Já estavam corretos ...: $JA_CORRETOS"
echo "  Pastas movidas p/ .old : $PASTAS_MOVIDAS"
echo "  Pastas ignoradas ......: $IGNORADOS"
echo
echo "  Para conferir: ls -la ~"
echo "=============================================="
