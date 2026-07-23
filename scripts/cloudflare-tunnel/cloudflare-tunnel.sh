#!/bin/bash
set -e

appNome="Cloudflare Tunnel"

if [ "$EUID" -ne 0 ]; then
    echo "❌ Execute como root: sudo bash $0"
    exit 1
fi

command -v curl &>/dev/null || { echo "❌ Instale curl: sudo apt install -y curl"; exit 1; }

# ============================================================
# FUNCOES AUXILIARES
# ============================================================

install_cloudflared() {
    echo
    echo "=== ➡️ Instalando cloudflared ==="

    CODENAME=$(lsb_release -cs)
    echo "   Codename detectado: $CODENAME"

    # Remove repo antigo se existir (pode ter codename errado)
    if [ -f /etc/apt/sources.list.d/cloudflared.list ]; then
        echo "   Removendo repo antigo..."
        rm -f /etc/apt/sources.list.d/cloudflared.list
    fi

    # Mapeamento: quais codenames o cloudflare suporta
    SUPPORTED="bookworm bullseye jammy noble focal"
    if echo "$SUPPORTED" | grep -qw "$CODENAME"; then
        REPO_CODENAME="$CODENAME"
    else
        # Fallback: bookworm é compatível com trixie/sid/etc
        REPO_CODENAME="bookworm"
        echo "   Codename '$CODENAME' nao suportado. Fallback: $REPO_CODENAME"
    fi

    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | \
        sudo gpg --dearmor -o /usr/share/keyrings/cloudflare-main.gpg 2>/dev/null

    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $REPO_CODENAME main" | \
        sudo tee /etc/apt/sources.list.d/cloudflared.list > /dev/null

    sudo apt update -y
    sudo apt install -y cloudflared

    CLOUDFLARED_VERSION=$(cloudflared version 2>/dev/null | head -1)
    echo "✅ cloudflared $CLOUDFLARED_VERSION"
}

authenticate() {
    echo
    echo "=== ➡️ Autenticando no Cloudflare ==="
    echo "   Um navegador sera aberto para fazer login."
    echo
    cloudflared tunnel login
    echo "✅ Autenticado."
}

get_tunnel_id() {
    local name="$1"
    cloudflared tunnel list --output json 2>/dev/null | \
        python3 -c "import sys,json; tunnels=json.load(sys.stdin); print([t['id'] for t in tunnels if t['name']=='$name'][0])" 2>/dev/null || \
        echo ""
}

get_all_tunnels() {
    cloudflared tunnel list --output json 2>/dev/null | \
        python3 -c "
import sys, json
tunnels = json.load(sys.stdin)
for t in tunnels:
    print(f\"{t['id']}|{t['name']}|{t.get('status','?')}\")
" 2>/dev/null
}

list_tunnels() {
    echo
    echo "=== ➡️ Tuneis existentes ==="
    if ! cloudflared tunnel list 2>/dev/null | grep -q '^[a-f0-9]'; then
        echo "   Nenhum tunel encontrado."
        return 1
    fi
    cloudflared tunnel list 2>/dev/null
    return 0
}

select_tunnel() {
    local name
    list_tunnels || return 1
    echo
    read -r -p "Nome do tunel: " name
    [ -z "$name" ] && return 1
    echo "$name"
}

configure_services() {
    echo
    echo "=============================================="
    echo "  📋 Configurar servicos expostos"
    echo "=============================================="

    add_one() {
        local proto host port
        read -r -p "   Protocolo (http/tcp/ssh/rdp): " proto
        read -r -p "   Subdominio (ex: ssh.$DOMINIO): " host
        read -r -p "   Porta local (ex: 22): " port

        if [ -z "$proto" ] || [ -z "$host" ] || [ -z "$port" ]; then
            echo "   ⚠️  Dados incompletos, ignorando."
            return
        fi

        CLOUDFLARED_SERVICES+=("$proto|$host|$port")
        echo "   ✅ $host -> $proto://localhost:$port"
    }

    rebuild_ingress() {
        INGRESS_RULES=""
        for srv in "${CLOUDFLARED_SERVICES[@]}"; do
            IFS='|' read -r p h po <<< "$srv"
            case "$p" in
                ssh)   url="ssh://localhost:$po" ;;
                rdp)   url="rdp://localhost:$po" ;;
                tcp)   url="tcp://localhost:$po" ;;
                http)  url="http://localhost:$po" ;;
                https) url="https://localhost:$po" ;;
                *)     url="tcp://localhost:$po" ;;
            esac
            INGRESS_RULES+="  - hostname: $h
    service: $url
"
        done
    }

    CLOUDFLARED_SERVICES=()
    INGRESS_RULES=""
    while true; do
        echo
        echo "Servicos atuais: ${#CLOUDFLARED_SERVICES[@]}"
        echo "  1) Adicionar servico"
        echo "  2) Remover ultimo servico"
        echo "  3) Concluir configuracao"
        echo "  4) Cancelar"
        read -r -p "Opcao [1-4]: " MENU_OPT

        case "$MENU_OPT" in
            1) add_one ;;
            2)
                if [ ${#CLOUDFLARED_SERVICES[@]} -gt 0 ]; then
                    echo "   Removido: ${CLOUDFLARED_SERVICES[-1]}"
                    unset 'CLOUDFLARED_SERVICES[-1]'
                    rebuild_ingress
                else
                    echo "   Nenhum servico para remover."
                fi
                ;;
            3)
                if [ ${#CLOUDFLARED_SERVICES[@]} -eq 0 ]; then
                    echo "❌ Adicione pelo menos um servico."
                else
                    break
                fi
                ;;
            4) return 1 ;;
            *) echo "❌ Opcao invalida." ;;
        esac
    done
    return 0
}

generate_config() {
    local tunnel_id="$1"
    local creds="$2"
    CONFIG_FILE="$HOME/.cloudflared/config.yml"
    echo
    echo "=== ➡️ Gerando $CONFIG_FILE ==="
    mkdir -p "$HOME/.cloudflared"
    cat > "$CONFIG_FILE" <<EOF
tunnel: $tunnel_id
credentials-file: $creds

ingress:
${INGRESS_RULES}  - service: http_status:404
EOF
    echo "✅ config.yml gerado."
}

create_dns_records() {
    local tunnel_name="$1"
    echo
    echo "=== ➡️ Criando registros DNS ==="

    for srv in "${CLOUDFLARED_SERVICES[@]}"; do
        IFS='|' read -r proto host port <<< "$srv"
        echo "   DNS: $host -> tunel $tunnel_name"
        if cloudflared tunnel route dns --overwrite-dns "$tunnel_name" "$host" 2>&1; then
            echo "   ✅ Registro DNS criado: $host"
        else
            echo "   ❌ Falha ao criar registro DNS para $host."
            echo "      Execute manualmente:"
            echo "      cloudflared tunnel route dns $tunnel_name $host"
        fi
    done
}

list_dns_routes() {
    echo
    echo "=== ➡️ Rotas DNS atuais ==="
    cloudflared tunnel route list 2>&1 || echo "   ⚠️  Nao foi possivel listar rotas."
}

install_service() {
    echo
    echo "=== ➡️ Instalando servico systemd ==="
    cloudflared service install 2>/dev/null || true
    systemctl enable cloudflared 2>/dev/null || true
    systemctl restart cloudflared
    sleep 2
    if systemctl is-active --quiet cloudflared; then
        echo "✅ Servico cloudflared: ATIVO"
    else
        echo "❌ Servico cloudflared: INATIVO"
        echo "   Logs: journalctl -u cloudflared -n 20"
    fi
}

configure_firewall() {
    echo
    echo "=== ➡️ Seguranca dos servicos ==="
    echo
    echo "   ⚠️  IMPORTANTE: Configure cada servico para escutar APENAS localhost."
    echo "   Isso impede acesso direto pela rede. O tunel Cloudflare fara o acesso."
    echo
    echo "   Exemplos de configuracao:"
    echo
    echo "   SSH:"
    echo "     Edite /etc/ssh/sshd_config:"
    echo "       ListenAddress 127.0.0.1"
    echo "     sudo systemctl restart sshd"
    echo

    for srv in "${CLOUDFLARED_SERVICES[@]}"; do
        IFS='|' read -r proto host port <<< "$srv"
        echo "   $proto (porta $port):"
        echo "     Verifique se o servico escuta em 127.0.0.1, nao 0.0.0.0"
        echo "     Teste: ss -tlnp | grep :$port"
        echo
    done

    echo "   ❌ NAO use 'ufw deny' nas portas dos servicos."
    echo "   Isso bloquearia o proprio cloudflared de acessa-los via localhost."
    echo "   O bind em 127.0.0.1 ja e suficiente."
}

configure_access() {
    local api_token="$1"
    [ -z "$api_token" ] && return

    echo
    echo "=== ➡️ Cloudflare Access (Zero Trust) ==="

    # Salvar token para uso futuro (ex: exclusao)
    mkdir -p "$HOME/.cloudflared"
    echo "$api_token" > "$HOME/.cloudflared/access_token"
    chmod 600 "$HOME/.cloudflared/access_token"

    ACCOUNT_ID=$(curl -s https://api.cloudflare.com/client/v4/accounts \
        -H "Authorization: Bearer $api_token" \
        -H "Content-Type: application/json" | \
        grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ -z "$ACCOUNT_ID" ]; then
        echo "❌ Falha ao obter Account ID. Verifique o API Token."
        return
    fi
    echo "   Account ID: $ACCOUNT_ID"

    echo
    echo "Metodo de autenticacao:"
    echo "  1) One-time PIN (email)"
    echo "  2) Google OAuth"
    read -r -p "Opcao [1-2]: " ACCESS_METHOD

    read -r -p "Emails autorizados (virgula): " ACCESS_EMAILS
    IFS=',' read -ra EMAIL_ARRAY <<< "$ACCESS_EMAILS"

    EMAIL_RULE=""
    for email in "${EMAIL_ARRAY[@]}"; do
        email=$(echo "$email" | xargs)
        [ -n "$EMAIL_RULE" ] && EMAIL_RULE+=","
        EMAIL_RULE+="\"$email\""
    done

    for srv in "${CLOUDFLARED_SERVICES[@]}"; do
        IFS='|' read -r proto host port <<< "$srv"
        echo "   Criando Access para: $host"

        APP_RESPONSE=$(curl -s -X POST \
            "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/access/apps" \
            -H "Authorization: Bearer $api_token" \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"$host\",\"domain\":\"$host\",\"session_duration\":\"24h\",\"type\":\"self_hosted\",\"allowed_idps\":[]}")

        APP_ID=$(echo "$APP_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
        [ -z "$APP_ID" ] && { echo "   ⚠️  Falha: $APP_RESPONSE"; continue; }

        if [ "$ACCESS_METHOD" = "2" ]; then
            POLICY_PAYLOAD="{\"name\":\"$host\",\"decision\":\"allow\",\"include\":[{\"email\":{\"email\":[$EMAIL_RULE]}}],\"precedence\":1}"
        else
            POLICY_PAYLOAD="{\"name\":\"$host\",\"decision\":\"allow\",\"include\":[{\"email\":{\"email\":[$EMAIL_RULE]}}],\"precedence\":1}"
        fi

        curl -s -X POST \
            "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/access/apps/$APP_ID/policies" \
            -H "Authorization: Bearer $api_token" \
            -H "Content-Type: application/json" \
            -d "$POLICY_PAYLOAD" > /dev/null && \
            echo "   ✅ Access: $host" || echo "   ⚠️  Falha na politica."
    done

    echo "✅ Cloudflare Access configurado."
}

verify_status() {
    local tunnel_name="$1"
    echo
    echo "=============================================="
    echo "  📊 Status do Tunel: $tunnel_name"
    echo "=============================================="

    echo "--- cloudflared tunnel info ---"
    cloudflared tunnel info "$tunnel_name" 2>&1 || echo "   ⚠️  Falha ao obter info."

    echo
    echo "--- Rotas DNS ---"
    cloudflared tunnel route list 2>&1 || echo "   ⚠️  Nenhuma rota."

    echo
    echo "--- Servico cloudflared ---"
    systemctl is-active cloudflared && echo "   ATIVO" || echo "   INATIVO"

    echo
    echo "--- Ultimos logs ---"
    journalctl -u cloudflared --no-pager -n 10 2>/dev/null || true
    echo "=============================================="
}

delete_everything() {
    # --- Listar e selecionar tunel ---
    echo
    echo "=== ➡️ Tuneis existentes ==="
    local tunnels_json
    tunnels_json=$(cloudflared tunnel list --output json 2>/dev/null || echo "[]")

    local tunnel_count
    tunnel_count=$(echo "$tunnels_json" | python3 -c "import sys,json;print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

    if [ "$tunnel_count" -eq 0 ]; then
        echo "Nenhum tunel encontrado no Cloudflare."
        return
    fi

    echo "$tunnels_json" | python3 -c "
import sys, json
tunnels = json.load(sys.stdin)
for i, t in enumerate(tunnels, 1):
    status = t.get('status', t.get('connections', '?'))
    print(f\"  {i}) {t['name']}  (id: {t['id'][:12]}...  status: {status})\")
" 2>/dev/null
    echo "  0) Cancelar"
    echo
    read -r -p "Qual tunel excluir? [1-$tunnel_count ou 0]: " TUNNEL_IDX

    if [ "$TUNNEL_IDX" = "0" ] || [ -z "$TUNNEL_IDX" ]; then
        echo "Cancelado."
        return
    fi

    # Extrair ID e nome do tunel selecionado
    local selected
    selected=$(echo "$tunnels_json" | python3 -c "
import sys, json
tunnels = json.load(sys.stdin)
idx = int(sys.argv[1]) - 2  # argv[1] is the user's choice, but we need to adjust — actually let me fix this
" 2>/dev/null)

    # Melhor abordagem: usar awk/line number
    local tid tname
    tid=$(echo "$tunnels_json" | python3 -c "
import sys, json
tunnels = json.load(sys.stdin)
t = tunnels[int('$TUNNEL_IDX') - 1]
print(t['id'])
" 2>/dev/null)
    tname=$(echo "$tunnels_json" | python3 -c "
import sys, json
tunnels = json.load(sys.stdin)
t = tunnels[int('$TUNNEL_IDX') - 1]
print(t['name'])
" 2>/dev/null)

    if [ -z "$tid" ] || [ -z "$tname" ]; then
        echo "❌ Selecao invalida."
        return
    fi

    # --- Listar rotas DNS do tunel ---
    echo
    echo "=== ➡️ Rotas DNS do tunel '$tname' ==="
    local routes_json
    routes_json=$(cloudflared tunnel route list --output json 2>/dev/null || echo "[]")
    local route_hostnames
    route_hostnames=$(echo "$routes_json" | python3 -c "
import sys, json
routes = json.load(sys.stdin)
for r in routes:
    if r.get('tunnel_id') == '$tid' or r.get('tunnel_name') == '$tname':
        print(r.get('value', r.get('dns_name', '')))
" 2>/dev/null)

    if [ -z "$route_hostnames" ]; then
        echo "   Nenhuma rota DNS associada."
    else
        echo "$route_hostnames" | while read -r hostname; do
            [ -n "$hostname" ] && echo "   - $hostname"
        done
    fi

    # --- Aviso e confirmacao ---
    echo
    echo "=============================================="
    echo "  ⚠️  Resumo da exclusao:"
    echo "  Tunel      : $tname ($tid)"
    echo "  Rotas DNS  : $(echo "$route_hostnames" | wc -l)"
    echo "  Config local: $HOME/.cloudflared/"
    echo "  Servico    : cloudflared (systemd)"
    echo "=============================================="
    echo
    echo "⚠️  ATENCAO: Apenas o tunel '$tname' e suas rotas serao excluidos."
    echo "   Outros tuneis na conta NAO serao afetados."
    echo
    read -r -p "Digite 'DELETAR' para confirmar: " CONFIRM
    [ "$CONFIRM" != "DELETAR" ] && { echo "Cancelado."; return; }

    # --- Executar exclusao ---
    echo

    # Deletar rotas DNS do tunel
    echo "=> Removendo rotas DNS..."
    echo "$route_hostnames" | while read -r hostname; do
        if [ -n "$hostname" ]; then
            echo "   -> $hostname"
            cloudflared tunnel route delete "$tid" "$hostname" 2>/dev/null || \
            cloudflared tunnel route delete -f "$tid" "$hostname" 2>/dev/null || \
            echo "   ⚠️  Nao foi possivel deletar: $hostname"
        fi
    done
    echo "   Rotas DNS removidas."

    # Deletar Access Apps (se token salvo)
    if [ -f "$HOME/.cloudflared/access_token" ]; then
        local saved_token
        saved_token=$(cat "$HOME/.cloudflared/access_token" 2>/dev/null || true)
        if [ -n "${saved_token:-}" ]; then
            echo "=> Removendo Cloudflare Access Apps..."
            local acct_id
            acct_id=$(curl -s https://api.cloudflare.com/client/v4/accounts \
                -H "Authorization: Bearer $saved_token" \
                -H "Content-Type: application/json" | \
                grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

            if [ -n "$acct_id" ]; then
                echo "$route_hostnames" | while read -r hostname; do
                    [ -z "$hostname" ] && continue
                    # Buscar Access App por dominio
                    local app_id
                    app_id=$(curl -s "https://api.cloudflare.com/client/v4/accounts/$acct_id/access/apps" \
                        -H "Authorization: Bearer $saved_token" \
                        -H "Content-Type: application/json" | \
                        python3 -c "
import sys, json
data = json.load(sys.stdin)
for app in data.get('result', []):
    if app.get('domain') == '$hostname':
        print(app['id'])
" 2>/dev/null)
                    if [ -n "$app_id" ]; then
                        curl -s -X DELETE \
                            "https://api.cloudflare.com/client/v4/accounts/$acct_id/access/apps/$app_id" \
                            -H "Authorization: Bearer $saved_token" > /dev/null && \
                            echo "   Access App $hostname removido."
                    fi
                done
            fi
        fi
    fi

    # Deletar o tunel
    echo "=> Excluindo tunel '$tname'..."
    if cloudflared tunnel delete -f "$tid" 2>&1; then
        echo "✅ Tunel '$tname' excluido do Cloudflare."
    else
        echo "⚠️  Falha ao excluir tunel '$tname'."
        echo "   Tente manualmente: cloudflared tunnel delete $tid"
    fi

    # --- Limpeza local (apenas se era o unico tunel ativo) ---
    local remaining
    remaining=$(cloudflared tunnel list --output json 2>/dev/null | python3 -c "import sys,json;print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    if [ "$remaining" -eq 0 ]; then
        echo
        echo "=> Nenhum tunel restante. Removendo configuracao local..."
        systemctl stop cloudflared 2>/dev/null || true
        systemctl disable cloudflared 2>/dev/null || true
        rm -f /etc/systemd/system/cloudflared*.service
        rm -f /lib/systemd/system/cloudflared*.service
        systemctl daemon-reload 2>/dev/null || true
        rm -rf "$HOME/.cloudflared" 2>/dev/null || true
        echo "   Configuracao local removida."

        read -r -p "Desinstalar o cloudflared? [s/N]: " UNINSTALL
        if [ "$UNINSTALL" = "s" ] || [ "$UNINSTALL" = "S" ]; then
            rm -f /etc/apt/sources.list.d/cloudflared.list
            sudo apt remove -y cloudflared 2>/dev/null || true
            echo "   cloudflared removido."
        fi
    else
        echo
        echo "Ainda existem $remaining tunel(s) na conta. Configuracao local mantida."
    fi

    # --- Verificacao ---
    echo
    echo "=== ➡️ Verificando ==="
    echo "Tuneis restantes:"
    cloudflared tunnel list 2>/dev/null || echo "   Nenhum."
    echo
    echo "✅ Tunel '$tname' excluido."
}

# ============================================================
# MENU PRINCIPAL
# ============================================================

while true; do
    echo
    echo "=============================================="
    echo "  🔧 $appNome"
    echo "=============================================="
    echo
    echo "  1) Instalar o túnel"
    echo "  2) Criar os registros DNS"
    echo "  3) Excluir um túnel"
    echo "  4) Status do túnel"
    echo "  5) Sair"
    echo
    read -r -p "Opcao [1-5]: " MAIN_OPT

    case "$MAIN_OPT" in
        1)
            # --- INSTALAR O TUNEL ---
            read -r -p "Dominio no Cloudflare (ex: meudominio.com): " DOMINIO
            [ -z "$DOMINIO" ] && { echo "❌ Dominio nao informado."; continue; }

            read -r -p "Nome do tunel (padrao: homelab): " TUNNEL_NAME
            TUNNEL_NAME="${TUNNEL_NAME:-homelab}"

            echo
            read -r -p "API Token Cloudflare para Access/Zero Trust (ou Enter para pular): " API_TOKEN

            # Salvar token para uso futuro
            if [ -n "$API_TOKEN" ]; then
                mkdir -p "$HOME/.cloudflared"
                echo "$API_TOKEN" > "$HOME/.cloudflared/access_token"
                chmod 600 "$HOME/.cloudflared/access_token"
            fi

            # 1. Instalar cloudflared
            if ! command -v cloudflared &>/dev/null; then
                install_cloudflared
            else
                echo "✅ cloudflared ja esta instalado."
            fi

            # 2. Autenticar
            authenticate

            # 3. Criar tunel
            echo
            echo "=== ➡️ Criando tunel: $TUNNEL_NAME ==="
            TUNNEL_ID=$(get_tunnel_id "$TUNNEL_NAME")
            if [ -n "$TUNNEL_ID" ]; then
                echo "   Tunel '$TUNNEL_NAME' ja existe (ID: $TUNNEL_ID)."
            else
                cloudflared tunnel create "$TUNNEL_NAME"
                TUNNEL_ID=$(get_tunnel_id "$TUNNEL_NAME")
                echo "✅ Tunel criado (ID: $TUNNEL_ID)."
            fi

            CREDENTIALS_FILE=$(ls "$HOME/.cloudflared/"*.json 2>/dev/null | head -1)

            # 4. Configurar servicos
            if ! configure_services; then
                echo "Configuracao cancelada."
                continue
            fi

            # 5. Gerar config.yml
            generate_config "$TUNNEL_ID" "$CREDENTIALS_FILE"

            # 6. Criar registros DNS
            create_dns_records "$TUNNEL_NAME"
            list_dns_routes

            # 7. Instalar servico
            install_service

            # 8. Firewall
            configure_firewall

            # 9. Access (opcional)
            configure_access "$API_TOKEN"

            # 10. Verificacao
            verify_status "$TUNNEL_NAME"

            echo
            echo "=============================================="
            echo "✅ Tunel instalado com sucesso!"
            echo "   Tunel   : $TUNNEL_NAME"
            echo "   Dominio : $DOMINIO"
            echo "   Config  : $CONFIG_FILE"
            echo
            echo "   🌐 Servicos:"
            for srv in "${CLOUDFLARED_SERVICES[@]}"; do
                IFS='|' read -r proto host port <<< "$srv"
                echo "      https://$host -> $proto://localhost:$port"
            done
            echo
            echo "=============================================="
            echo "  💻 Como acessar da maquina cliente"
            echo "=============================================="
            echo
            for srv in "${CLOUDFLARED_SERVICES[@]}"; do
                IFS='|' read -r proto host port <<< "$srv"
                case "$proto" in
                    http|https)
                        echo "   🌍 $host"
                        echo "      Acesse direto no navegador: https://$host"
                        echo
                        ;;
                    ssh)
                        echo "   🔑 $host (SSH)"
                        echo "      Instale o cloudflared na maquina cliente:"
                        echo "      https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/"
                        echo
                        echo "      Acesse via:"
                        echo "      cloudflared access ssh --hostname $host"
                        echo
                        echo "      Ou adicione ao ~/.ssh/config:"
                        echo "      Host $host"
                        echo "          ProxyCommand cloudflared access ssh --hostname %h"
                        echo
                        ;;
                    rdp)
                        echo "   🖥️  $host (RDP)"
                        echo "      Instale o cloudflared na maquina cliente:"
                        echo "      https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/"
                        echo
                        echo "      Acesse via:"
                        echo "      cloudflared access rdp --hostname $host --url localhost:3389"
                        echo "      Depois conecte seu cliente RDP em: localhost:3389"
                        echo
                        ;;
                    tcp)
                        echo "   🔗 $host (TCP)"
                        echo "      Instale o cloudflared na maquina cliente."
                        echo
                        echo "      Acesse via:"
                        echo "      cloudflared access tcp --hostname $host --url localhost:$port"
                        echo "      Depois conecte seu cliente em: localhost:$port"
                        echo
                        ;;
                esac
            done
            echo "=============================================="
            echo "   🔍 Dashboard: https://one.dash.cloudflare.com/"
            echo "      Zero Trust > Networks > Tunnels"
            echo "=============================================="
            ;;

        2)
            # --- CRIAR REGISTROS DNS ---
            TUNNEL_NAME=$(select_tunnel)
            [ -z "$TUNNEL_NAME" ] && continue

            read -r -p "Dominio no Cloudflare (ex: meudominio.com): " DOMINIO
            [ -z "$DOMINIO" ] && { echo "❌ Dominio nao informado."; continue; }

            # Configurar servicos
            CLOUDFLARED_SERVICES=()
            INGRESS_RULES=""
            if ! configure_services; then
                echo "Cancelado."
                continue
            fi

            # Atualizar config.yml
            TUNNEL_ID=$(get_tunnel_id "$TUNNEL_NAME")
            CREDENTIALS_FILE=$(ls "$HOME/.cloudflared/"*.json 2>/dev/null | head -1)
            generate_config "$TUNNEL_ID" "$CREDENTIALS_FILE"

            # Criar DNS
            create_dns_records "$TUNNEL_NAME"
            list_dns_routes

            # Reiniciar servico
            echo
            echo "=== ➡️ Reiniciando servico ==="
            systemctl restart cloudflared 2>/dev/null || true
            echo "✅ Servico reiniciado."
            ;;

        3)
            # --- EXCLUIR TUDO ---
            delete_everything
            ;;

        4)
            # --- STATUS ---
            if ! list_tunnels; then
                continue
            fi
            read -r -p "Nome do tunel para ver status: " TUNNEL_NAME
            [ -z "$TUNNEL_NAME" ] && continue
            verify_status "$TUNNEL_NAME"
            ;;

        5)
            echo "Saindo..."
            exit 0
            ;;

        *)
            echo "❌ Opcao invalida."
            ;;
    esac
done
