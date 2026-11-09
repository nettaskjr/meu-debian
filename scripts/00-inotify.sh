#!/bin/bash
set -e

# =============================================================================
#  00-inotify.sh - Ajuste dos limites de inotify do kernel
#
#  FUNÇÃO DESTE SCRIPT:
#  O inotify é o mecanismo do kernel Linux usado por programas para "observar"
#  alterações em arquivos e diretórios. Editores (VS Code, JetBrains), clientes
#  de sincronização (Insync, Dropbox, Nextcloud) e servidores de desenvolvimento
#  consomem uma cota de "watches" por usuário.
#
#  No Debian o padrão é fs.inotify.max_user_watches = 65536. Quando esse limite
#  se esgota, o VS Code exibe o aviso:
#     "Não é possível observar alterações no arquivo."
#  e deixa de detectar mudanças feitas fora dele (hot reload, git, etc.).
#
#  Neste ambiente o Insync vigia ~68 mil diretórios do Google Drive, ou seja,
#  sozinho ele já ultrapassa o limite padrão e consome todos os watches.
#
#  O que este script faz:
#   1. Eleva fs.inotify.max_user_watches para 1.048.576 (1 milhão);
#   2. Eleva fs.inotify.max_user_instances para 1024 (várias instâncias);
#   3. Eleva fs.inotify.max_queued_events para 32768 (evita perda de eventos
#      em rajadas de alterações, como um `git checkout` em repositório grande);
#   4. Grava a configuração em /etc/sysctl.d/99-inotify.conf, garantindo que
#      ela seja reaplicada em todo boot;
#   5. Mostra o uso atual de watches antes e depois, para diagnóstico.
#
#  Observação: os valores são globais (por usuário do sistema). Após aplicar,
#  reinicie os programas que usam inotify para que registrem os watches com o
#  novo limite. Em troca de mais watches há um pequeno custo de memória no
#  kernel (~1 KB por watch em uso).
# =============================================================================

appNome="Limites do inotify"
ARQUIVO_CONF="/etc/sysctl.d/99-inotify.conf"

# Valores alvo. 1.048.576 cobre com folga os ~68 mil diretórios do Google Drive
# sincronizados pelo Insync e ainda deixa espaço para editores e outros apps.
MAX_WATCHES=1048576
MAX_INSTANCES=1024
MAX_QUEUED_EVENTS=32768

# Conta quantos watches de inotify estão em uso por todos os processos.
contar_watches_em_uso() {
    local total=0 qtd fdinfo
    for fdinfo in /proc/*/fdinfo/*; do
        [ -r "$fdinfo" ] || continue
        qtd=$(grep -c '^inotify wd:' "$fdinfo" 2>/dev/null || true)
        total=$((total + ${qtd:-0}))
    done
    echo "$total"
}

valor_sysctl() {
    sysctl -n "$1" 2>/dev/null || echo 0
}

mostrar_valores_atuais() {
    echo "=== ➡️ Valores atuais do kernel ==="
    sysctl fs.inotify.max_user_watches \
           fs.inotify.max_user_instances \
           fs.inotify.max_queued_events
    echo "=== ➡️ Watches em uso agora: $(contar_watches_em_uso) ==="
}

echo "=== ➡️ Configurando $appNome ==="
echo
mostrar_valores_atuais

# Se os três valores já estão corretos, não há nada a fazer (script idempotente).
if [ "$(valor_sysctl fs.inotify.max_user_watches)" -ge "$MAX_WATCHES" ] &&
   [ "$(valor_sysctl fs.inotify.max_user_instances)" -ge "$MAX_INSTANCES" ] &&
   [ "$(valor_sysctl fs.inotify.max_queued_events)" -ge "$MAX_QUEUED_EVENTS" ]; then
    echo
    echo "=== ✅ Os limites já estão configurados, nada a alterar ==="
    echo "=== ➡️ Verificando se a configuração é persistente em $ARQUIVO_CONF ==="
    if [ -f "$ARQUIVO_CONF" ] &&
       grep -q "max_user_watches *= *$MAX_WATCHES" "$ARQUIVO_CONF"; then
        echo "=== ✅ Configuração persistente encontrada ==="
        exit 0
    fi
fi

echo
echo "=== ➡️ Gravando configuração persistente em $ARQUIVO_CONF ==="
sudo tee "$ARQUIVO_CONF" > /dev/null <<EOF
# Limites de inotify - gerado por meu-debian/scripts/00-inotify.sh
#
# max_user_watches: quantidade máxima de arquivos/diretórios que um usuário
#                   pode observar. O padrão (65536) é insuficiente quando há
#                   sincronização de pastas grandes (ex.: Insync/Google Drive).
# max_user_instances: quantidade de instâncias de inotify por usuário.
# max_queued_events:  eventos enfileirados antes de o kernel descartá-los.
fs.inotify.max_user_watches = $MAX_WATCHES
fs.inotify.max_user_instances = $MAX_INSTANCES
fs.inotify.max_queued_events = $MAX_QUEUED_EVENTS
EOF

echo "=== ➡️ Aplicando os novos limites (sysctl --system) ==="
sudo sysctl --system > /dev/null

echo
mostrar_valores_atuais

echo
echo "=============================================="
echo "✅ $appNome configurado com sucesso!"
echo
echo "⚠️  Os programas que já estavam abertos continuam usando a cota antiga."
echo "    Feche e reabra o VS Code e o Insync para que os novos limites valham."
echo "    Exemplo:"
echo "      pkill -f '/usr/share/code/code'   # fechar o VS Code"
echo "      insync quit                       # fechar o Insync"
echo
echo "💡 Dica: no Insync, use Selective Sync para não sincronizar pastas"
echo "   grandes que você não edita localmente; isso reduz o número de"
echo "   diretórios vigiados e o consumo de memória do kernel."
echo "=============================================="
