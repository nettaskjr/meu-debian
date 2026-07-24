#!/bin/bash
set -e

appNome="Cloudflare Tunnel (Terraform)"

echo "=============================================="
echo "  🔧 $appNome"
echo "=============================================="
echo

if [ "$EUID" -ne 0 ]; then
    echo "❌ Execute como root: sudo bash $0"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"

# ============================================================
# 1. PRE-REQUISITOS
# ============================================================
echo "=== ➡️ Verificando pre-requisitos ==="
command -v curl &>/dev/null || { echo "❌ Instale curl: sudo apt install -y curl"; exit 1; }
echo "✅ curl OK"

# ============================================================
# 2. INSTALAR TERRAFORM (se nao estiver)
# ============================================================
if ! command -v terraform &>/dev/null; then
    echo
    echo "=== ➡️ Instalando Terraform ==="
    sudo apt install -y gnupg software-properties-common
    wget -q -O- https://apt.releases.hashicorp.com/gpg | \
        sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
        sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt update -y && sudo apt install -y terraform
    echo "✅ Terraform: $(terraform version -json | grep -o '"terraform_version":"[^"]*"' | cut -d'"' -f4)"
else
    echo "✅ Terraform ja instalado."
fi

# ============================================================
# 3. INSTALAR CLOUDFLARED
# ============================================================
echo
echo "=== ➡️ Verificando cloudflared ==="

if ! command -v cloudflared &>/dev/null; then
    CODENAME=$(lsb_release -cs)
    echo "   Codename detectado: $CODENAME"

    if [ -f /etc/apt/sources.list.d/cloudflared.list ]; then
        rm -f /etc/apt/sources.list.d/cloudflared.list
    fi

    SUPPORTED="bookworm bullseye jammy noble"
    if echo "$SUPPORTED" | grep -qw "$CODENAME"; then
        REPO_CODENAME="$CODENAME"
    else
        REPO_CODENAME="bookworm"
        echo "   Fallback para repositorio: $REPO_CODENAME"
    fi

    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | \
        sudo gpg --dearmor -o /usr/share/keyrings/cloudflare-main.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $REPO_CODENAME main" | \
        sudo tee /etc/apt/sources.list.d/cloudflared.list > /dev/null
    sudo apt update -y
    sudo apt install -y cloudflared
fi

echo "✅ cloudflared: $(cloudflared version 2>/dev/null | head -1)"

# ============================================================
# 4. AUTENTICAR (cert.pem)
# ============================================================
echo
echo "=== ➡️ Autenticando no Cloudflare ==="
echo "   Um navegador sera aberto. Se nao abrir, copie a URL."
echo
if [ ! -f /root/.cloudflared/cert.pem ]; then
    cloudflared tunnel login
else
    echo "✅ Certificado ja existe."
fi

# ============================================================
# 5. COLETAR VARIAVEIS DO USUARIO
# ============================================================
echo
echo "=============================================="
echo "  📋 Configuracao do tunel"
echo "=============================================="
echo

read -r -p "API Token Cloudflare: " API_TOKEN
[ -z "$API_TOKEN" ] && { echo "❌ API Token obrigatorio."; exit 1; }
export TF_VAR_api_token="$API_TOKEN"

read -r -p "Account ID (dashboard Cloudflare): " ACCOUNT_ID
[ -z "$ACCOUNT_ID" ] && { echo "❌ Account ID obrigatorio."; exit 1; }

read -r -p "Dominio (ex: nettask.com.br): " DOMAIN
[ -z "$DOMAIN" ] && { echo "❌ Dominio obrigatorio."; exit 1; }

if [ ! -f "$TF_DIR/terraform.tfvars" ]; then
    echo
    echo "=== ➡️ Criando terraform.tfvars ==="
    read -r -p "Nome do tunel (padrao: homelab): " TUNNEL_NAME
    TUNNEL_NAME="${TUNNEL_NAME:-homelab}"

    TUNNEL_SECRET=$(openssl rand -base64 32)

    cat > "$TF_DIR/terraform.tfvars" <<EOF
domain       = "$DOMAIN"
tunnel_name  = "$TUNNEL_NAME"
account_id   = "$ACCOUNT_ID"
tunnel_secret = "$TUNNEL_SECRET"

services = {}

access_enabled = true
access_emails  = []
EOF
    echo "   terraform.tfvars criado."
    echo
    echo "   ⚠️  Edite o arquivo para configurar os servicos:"
    echo "      nano $TF_DIR/terraform.tfvars"
    echo
    echo "   Exemplo de servicos:"
    echo "   services = {"
    echo "     ssh = { hostname = \"ssh\", proto = \"ssh\", port = 22 }"
    echo "     app = { hostname = \"app\", proto = \"http\", port = 8080 }"
    echo "   }"
    echo
    read -r -p "Pressione Enter apos editar o arquivo... " _
fi

# ============================================================
# 6. TERRAFORM
# ============================================================
echo
echo "=== ➡️ Terraform init ==="
cd "$TF_DIR"
terraform init

echo
echo "=== ➡️ Terraform plan ==="
terraform plan

echo
read -r -p "Aplicar as mudancas? [s/N]: " APPLY
if [ "$APPLY" != "s" ] && [ "$APPLY" != "S" ]; then
    echo "Cancelado. Execute manualmente: cd $TF_DIR && terraform apply"
    exit 0
fi

echo
echo "=== ➡️ Terraform apply ==="
terraform apply -auto-approve

# ============================================================
# 7. CONFIGURAR CLOUDFLARED LOCAL
# ============================================================
echo
echo "=== ➡️ Configurando cloudflared local ==="

TUNNEL_ID=$(terraform output -raw tunnel_id)
TUNNEL_SECRET_VAL=$(grep tunnel_secret terraform.tfvars | cut -d'"' -f2)
CREDENTIALS_FILE="/root/.cloudflared/${TUNNEL_ID}.json"

if [ ! -f "$CREDENTIALS_FILE" ]; then
    cat > "$CREDENTIALS_FILE" <<EOF
{
  "AccountTag": "$ACCOUNT_ID",
  "TunnelID": "$TUNNEL_ID",
  "TunnelName": "$(terraform output -raw tunnel_name)",
  "TunnelSecret": "$(echo -n "$TUNNEL_SECRET_VAL" | base64 -d | xxd -p | tr -d '\n')"
}
EOF
fi

CONFIG_FILE="/root/.cloudflared/config.yml"
cat > "$CONFIG_FILE" <<EOF
tunnel: $TUNNEL_ID
credentials-file: $CREDENTIALS_FILE
EOF

echo "✅ Configuracao local criada."

# ============================================================
# 8. INSTALAR SERVICO SYSTEMD
# ============================================================
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
    echo "   Verifique: journalctl -u cloudflared -n 20"
fi

# ============================================================
# 9. VERIFICACAO
# ============================================================
echo
echo "=============================================="
echo "  ✅ $appNome configurado!"
echo "=============================================="
echo
echo "   Tunel       : $(terraform output -raw tunnel_name)"
echo "   Tunnel ID   : $(terraform output -raw tunnel_id)"

if terraform output -raw services 2>/dev/null | grep -q "https"; then
    echo
    echo "   🌐 Servicos:"
    terraform output -json services 2>/dev/null | python3 -c "
import sys, json
svcs = json.load(sys.stdin)
for k, v in sorted(svcs.items()):
    print(f\"      {v}\")
" 2>/dev/null || terraform output services
fi

echo
echo "   📝 Comandos:"
echo "      cd $TF_DIR"
echo "      terraform plan           # ver mudancas"
echo "      terraform apply          # aplicar"
echo "      terraform destroy        # excluir tudo"
echo "      systemctl status cloudflared"
echo "      journalctl -u cloudflared -f"
echo
echo "   🔍 Dashboard: https://one.dash.cloudflare.com/"
echo "=============================================="
