#!/bin/bash
set -e

appNome="Cloudflare Tunnel"

echo "=============================================="
echo "  🔧 $appNome"
echo "=============================================="
echo

if [ "$EUID" -ne 0 ]; then
    echo "❌ Execute como root: sudo bash $0"
    exit 1
fi

# ============================================================
# 1. PRE-REQUISITOS
# ============================================================
echo "=== ➡️ Verificando pre-requisitos ==="
command -v curl &>/dev/null || { echo "❌ curl nao encontrado. Instale com: sudo apt install -y curl"; exit 1; }
echo "✅ curl OK"

# ============================================================
# 2. PERGUNTAR DADOS INICIAIS
# ============================================================
read -r -p "Dominio configurado no Cloudflare (ex: meudominio.com): " DOMINIO
if [ -z "$DOMINIO" ]; then
    echo "❌ Dominio nao informado."
    exit 1
fi

echo
echo "Para o Cloudflare Access, voce precisa de um API Token."
echo "Crie um em: https://dash.cloudflare.com/profile/api-tokens"
echo "Permissoes minimas:"
echo "  - Account:Cloudflare Tunnel:Edit"
echo "  - Zone:DNS:Edit"
echo "  - Account:Access:Edit"
echo
read -r -p "API Token (deixe em branco para pular Access): " API_TOKEN

# Nome do tunel
read -r -p "Nome do tunel (padrao: homelab): " TUNNEL_NAME
TUNNEL_NAME="${TUNNEL_NAME:-homelab}"

# ============================================================
# 3. INSTALAR CLOUDFLARED
# ============================================================
echo
echo "=== ➡️ Instalando cloudflared ==="

if ! command -v cloudflared &>/dev/null; then
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | \
        sudo gpg --dearmor -o /usr/share/keyrings/cloudflare-main.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | \
        sudo tee /etc/apt/sources.list.d/cloudflared.list > /dev/null
    sudo apt update -y
    sudo apt install -y cloudflared
else
    echo "   cloudflared ja instalado."
fi

CLOUDFLARED_VERSION=$(cloudflared version 2>/dev/null | head -1)
echo "✅ cloudflared $CLOUDFLARED_VERSION"

# ============================================================
# 4. AUTENTICAR
# ============================================================
echo
echo "=== ➡️ Autenticando no Cloudflare ==="
echo "   Um navegador sera aberto para fazer login."
echo "   Se nao abrir, copie a URL exibida abaixo."
echo

cloudflared tunnel login

# ============================================================
# 5. CRIAR O TUNEL
# ============================================================
echo
echo "=== ➡️ Criando tunel: $TUNNEL_NAME ==="

if cloudflared tunnel list | grep -q "$TUNNEL_NAME"; then
    echo "   Tunel '$TUNNEL_NAME' ja existe."
else
    cloudflared tunnel create "$TUNNEL_NAME"
    echo "✅ Tunel '$TUNNEL_NAME' criado."
fi

TUNNEL_ID=$(cloudflared tunnel list --output json 2>/dev/null | grep -o "\"id\":\"[^\"]*\"" | head -1 | cut -d'"' -f4)
CREDENTIALS_FILE=$(ls "$HOME/.cloudflared/"*.json 2>/dev/null | head -1)

# ============================================================
# 6. CONFIGURAR SERVICOS (INTERATIVO)
# ============================================================
CONFIG_FILE="$HOME/.cloudflared/config.yml"
INGRESS_RULES=""

echo
echo "=============================================="
echo "  📋 Configurar servicos expostos"
echo "=============================================="

add_service() {
    local proto host port
    read -r -p "   Protocolo (http/tcp/ssh/rdp): " proto
    read -r -p "   Subdominio (ex: ssh.$DOMINIO): " host
    read -r -p "   Porta local (ex: 22): " port

    if [ -z "$proto" ] || [ -z "$host" ] || [ -z "$port" ]; then
        echo "   ⚠️  Dados incompletos, ignorando."
        return
    fi

    case "$proto" in
        ssh)   SERVICE_URL="ssh://localhost:$port" ;;
        rdp)   SERVICE_URL="rdp://localhost:$port" ;;
        tcp)   SERVICE_URL="tcp://localhost:$port" ;;
        http)  SERVICE_URL="http://localhost:$port" ;;
        https) SERVICE_URL="https://localhost:$port" ;;
        *)     SERVICE_URL="tcp://localhost:$port" ;;
    esac

    INGRESS_RULES+="  - hostname: $host
    service: $SERVICE_URL
"
    CLOUDFLARED_SERVICES+=("$proto|$host|$port")
    echo "   ✅ $host -> $SERVICE_URL"
}

CLOUDFLARED_SERVICES=()
while true; do
    echo
    echo "Servicos atuais: ${#CLOUDFLARED_SERVICES[@]}"
    echo "  1) Adicionar servico"
    echo "  2) Remover ultimo servico"
    echo "  3) Concluir configuracao"
    echo "  4) Cancelar"
    read -r -p "Opcao [1-4]: " MENU_OPT

    case "$MENU_OPT" in
        1) add_service ;;
        2)
            if [ ${#CLOUDFLARED_SERVICES[@]} -gt 0 ]; then
                removed="${CLOUDFLARED_SERVICES[-1]}"
                unset 'CLOUDFLARED_SERVICES[-1]'
                # Rebuild INGRESS_RULES
                INGRESS_RULES=""
                for srv in "${CLOUDFLARED_SERVICES[@]}"; do
                    IFS='|' read -r p h po <<< "$srv"
                    case "$p" in
                        ssh) url="ssh://localhost:$po" ;;
                        rdp) url="rdp://localhost:$po" ;;
                        tcp) url="tcp://localhost:$po" ;;
                        http) url="http://localhost:$po" ;;
                        https) url="https://localhost:$po" ;;
                        *) url="tcp://localhost:$po" ;;
                    esac
                    INGRESS_RULES+="  - hostname: $h
    service: $url
"
                done
                echo "   Removido: $removed"
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
        4) echo "Cancelado."; exit 0 ;;
        *) echo "❌ Opcao invalida." ;;
    esac
done

# ============================================================
# 7. GERAR CONFIG.YML
# ============================================================
echo
echo "=== ➡️ Gerando $CONFIG_FILE ==="

cat > "$CONFIG_FILE" <<EOF
tunnel: $TUNNEL_ID
credentials-file: $CREDENTIALS_FILE

ingress:
${INGRESS_RULES}  - service: http_status:404
EOF

echo "✅ config.yml gerado."

# ============================================================
# 8. CRIAR REGISTROS DNS
# ============================================================
echo
echo "=== ➡️ Criando registros DNS ==="

for srv in "${CLOUDFLARED_SERVICES[@]}"; do
    IFS='|' read -r proto host port <<< "$srv"
    echo "   DNS: $host -> tunel $TUNNEL_NAME"
    cloudflared tunnel route dns "$TUNNEL_NAME" "$host" 2>/dev/null || \
        echo "   ⚠️  Registro DNS para $host pode ja existir ou falhou."
done

# ============================================================
# 9. INSTALAR COMO SERVICO SYSTEMD
# ============================================================
echo
echo "=== ➡️ Instalando servico systemd ==="
cloudflared service install
systemctl enable cloudflared
systemctl restart cloudflared

# ============================================================
# 10. SEGURANCA - FIREWALL E BIND LOCALHOST
# ============================================================
echo
echo "=== ➡️ Reforcando seguranca local ==="

echo
echo "   🔒 Bloqueando acesso externo as portas dos servicos:"
for srv in "${CLOUDFLARED_SERVICES[@]}"; do
    IFS='|' read -r proto host port <<< "$srv"
    if command -v ufw &>/dev/null; then
        sudo ufw deny "$port/tcp" 2>/dev/null || true
        echo "   Porta $port bloqueada no firewall."
    fi
done

if command -v ufw &>/dev/null; then
    sudo ufw reload 2>/dev/null || true
fi

echo
echo "   ⚠️  IMPORTANTE: Configure cada servico para escutar apenas localhost."
echo "   Exemplos:"
echo "   - SSH: edite /etc/ssh/sshd_config e adicione 'ListenAddress 127.0.0.1'"
echo "   - Web/App: configure bind para 127.0.0.1 em vez de 0.0.0.0"
echo

# ============================================================
# 11. CLOUDFLARE ACCESS (se token informado)
# ============================================================
if [ -n "$API_TOKEN" ]; then
    echo "=== ➡️ Configurando Cloudflare Access (Zero Trust) ==="

    # Obter Account ID
    echo "   Obtendo Account ID..."
    ACCOUNT_ID=$(curl -s https://api.cloudflare.com/client/v4/accounts \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" | \
        grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ -z "$ACCOUNT_ID" ]; then
        echo "❌ Falha ao obter Account ID. Verifique seu API Token."
        echo "   Continuando sem Cloudflare Access..."
    else
        echo "   Account ID: $ACCOUNT_ID"

        echo
        echo "Escolha o metodo de autenticacao para o Access:"
        echo "  1) One-time PIN (enviado por email)"
        echo "  2) Google OAuth"
        read -r -p "Opcao [1-2]: " ACCESS_METHOD

        read -r -p "Emails autorizados (separados por virgula): " ACCESS_EMAILS
        IFS=',' read -ra EMAIL_ARRAY <<< "$ACCESS_EMAILS"

        # Dependendo do método
        if [ "$ACCESS_METHOD" = "2" ]; then
            read -r -p "Google Client ID: " GOOGLE_CLIENT_ID
            read -r -p "Google Client Secret: " GOOGLE_CLIENT_SECRET
        fi

        # Criar Access Application e Policy para cada servico
        for srv in "${CLOUDFLARED_SERVICES[@]}"; do
            IFS='|' read -r proto host port <<< "$srv"

            echo "   Criando Access para: $host"

            # --- Session duration: 24h ---
            SESSION_DUR="24h"

            # --- Criar Access Application ---
            APP_PAYLOAD=$(cat <<APPDATA
{
  "name": "$host",
  "domain": "$host",
  "session_duration": "$SESSION_DUR",
  "type": "self_hosted",
  "allowed_idps": []
}
APPDATA
)

            APP_RESPONSE=$(curl -s -X POST \
                "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/access/apps" \
                -H "Authorization: Bearer $API_TOKEN" \
                -H "Content-Type: application/json" \
                -d "$APP_PAYLOAD")

            APP_ID=$(echo "$APP_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

            if [ -z "$APP_ID" ]; then
                echo "   ⚠️  Falha ao criar Access App para $host"
                echo "   Resposta: $APP_RESPONSE"
                continue
            fi

            echo "   Access App ID: $APP_ID"

            # --- Montar regra de email ---
            EMAIL_RULE=""
            for email in "${EMAIL_ARRAY[@]}"; do
                email=$(echo "$email" | xargs)  # trim
                if [ -n "$EMAIL_RULE" ]; then
                    EMAIL_RULE+=" or "
                fi
                EMAIL_RULE+="\"$email\""
            done

            # --- Criar Access Policy ---
            if [ "$ACCESS_METHOD" = "2" ]; then
                POLICY_PAYLOAD=$(cat <<POLICY
{
  "name": "$host - Google Auth",
  "decision": "allow",
  "include": [
    {
      "login_method": {
        "id": "$GOOGLE_CLIENT_ID"
      }
    },
    {
      "email": {
        "email": [$EMAIL_RULE]
      }
    }
  ],
  "precedence": 1
}
POLICY
)
            else
                POLICY_PAYLOAD=$(cat <<POLICY
{
  "name": "$host - Email PIN",
  "decision": "allow",
  "include": [
    {
      "email": {
        "email": [$EMAIL_RULE]
      }
    }
  ],
  "precedence": 1
}
POLICY
)
            fi

            POLICY_RESPONSE=$(curl -s -X POST \
                "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/access/apps/$APP_ID/policies" \
                -H "Authorization: Bearer $API_TOKEN" \
                -H "Content-Type: application/json" \
                -d "$POLICY_PAYLOAD")

            POLICY_RESPONSE_OK=$(echo "$POLICY_RESPONSE" | grep -o '"success":true')

            if [ -n "$POLICY_RESPONSE_OK" ]; then
                echo "   ✅ Access configurado para $host"
            else
                echo "   ⚠️  Falha ao criar politica de acesso:"
                echo "   $POLICY_RESPONSE"
            fi

        done

        echo
        echo "✅ Cloudflare Access configurado."
        echo "   Antes de acessar, o usuario precisara autenticar."
    fi
else
    echo
    echo "⚠️  Cloudflare Access NAO configurado (API Token nao informado)."
    echo "   Configure manualmente no dashboard: https://one.dash.cloudflare.com/"
fi

# ============================================================
# 12. VERIFICACAO FINAL
# ============================================================
echo
echo "=============================================="
echo "  📊 Status do Tunel"
echo "=============================================="
echo
cloudflared tunnel info "$TUNNEL_NAME"
echo

echo "✅ $appNome configurado com sucesso!"
echo
echo "   Tunel      : $TUNNEL_NAME"
echo "   Dominio    : $DOMINIO"
echo "   Config     : $CONFIG_FILE"
echo
echo "   🌐 Servicos disponiveis:"
for srv in "${CLOUDFLARED_SERVICES[@]}"; do
    IFS='|' read -r proto host port <<< "$srv"
    echo "      https://$host -> localhost:$port"
done
echo
echo "   📝 Comandos uteis:"
echo "      cloudflared tunnel list"
echo "      cloudflared tunnel info $TUNNEL_NAME"
echo "      systemctl status cloudflared"
echo "      journalctl -u cloudflared -f"
echo
if [ -n "$API_TOKEN" ] && [ -n "$ACCOUNT_ID" ]; then
    echo "   🔐 Access dashboard: https://one.dash.cloudflare.com/"
fi
echo "=============================================="
