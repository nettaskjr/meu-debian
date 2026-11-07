#!/usr/bin/env bash
#
# backup-coolify.sh - Backup completo da instância Coolify para Cloudflare R2
#
# Inclui o que o backup nativo do Coolify NÃO cobre:
#   - dump do PostgreSQL (coolify-db)
#   - /data/coolify (source/.env/APP_KEY, ssh/keys, storage de recursos)
#   - authorized_keys do host (necessário ao restaurar em outra máquina)
#
# O pacote é criptografado com AES-256 antes de ir para o R2.
#
set -euo pipefail

COR_CYAN='\033[0;36m'
COR_VERDE='\033[0;32m'
COR_AMARELA='\033[0;33m'
COR_VERMELHA='\033[0;31m'
COR_RESET='\033[0m'

info() { printf '%b%s%b\n' "$COR_CYAN" "$*" "$COR_RESET"; }
ok()   { printf '%b%s%b\n' "$COR_VERDE" "$*" "$COR_RESET"; }
warn() { printf '%b%s%b\n' "$COR_AMARELA" "$*" "$COR_RESET"; }
erro() { printf '%b%s%b\n' "$COR_VERMELHA" "$*" "$COR_RESET" >&2; }

CONFIG_FILE="/etc/coolify-backup.env"
LOCAL_BACKUP_DIR="/var/backups/coolify"
LOCAL_RETENTION_DAYS=7
RETENTION_DAYS=30
R2_PREFIX="coolify"
ENCRYPT=1
UPLOAD=1
PASSPHRASE_FILE="/etc/coolify-backup.passphrase"

R2_BUCKET="${R2_BUCKET:-}"
RCLONE_REMOTE="${RCLONE_REMOTE:-}"
R2_ENDPOINT="${R2_ENDPOINT:-}"
R2_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID:-}"
R2_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY:-}"

OPT_CONFIG=""
OPT_LOCAL_DIR=""
OPT_RETENTION=""
OPT_PREFIX=""
OPT_PASSPHRASE_FILE=""
OPT_NO_UPLOAD=0
OPT_NO_ENCRYPT=0
OPT_INIT_CONFIG=0
OPT_FORCE=0
SHOW_HELP=0

usage() {
  cat <<'EOF'
Uso: ./backup-coolify.sh [opções]

Gera um backup completo da instância Coolify (banco + /data/coolify + chaves SSH),
criptografa e envia para um bucket Cloudflare R2.

Opções:
  -h, --help                 Mostra esta ajuda
  --init-config              Cria /etc/coolify-backup.env e a passphrase (se faltarem)
  --force                    Sobrescreve o arquivo de configuração no --init-config
  --config ARQUIVO           Configuração alternativa (padrão: /etc/coolify-backup.env)
  --local-dir DIR            Diretório local dos pacotes (padrão: /var/backups/coolify)
  --retention DIAS           Retenção no R2 em dias (padrão: 30)
  --prefix PREFIXO           Prefixo/caminho no bucket (padrão: coolify)
  --passphrase-file ARQUIVO  Arquivo com a passphrase de criptografia
  --no-upload                Gera o pacote local, sem enviar ao R2
  --no-encrypt               NÃO criptografa o pacote (não recomendado)

Conteúdo do pacote:
  coolify-db.dmp      Dump pg_dump --format=custom do banco do Coolify
  coolify-data.tar    /data/coolify (sem backups nativos, logs e mux)
  coolify.env         Cópia de /data/coolify/source/.env (contém APP_KEY)
  authorized_keys.*   authorized_keys do root (e do usuário que rodou o sudo)
  manifest.txt        Versões, tamanhos e instruções de restauração

Configuração (variáveis em /etc/coolify-backup.env):
  R2_BUCKET              Nome do bucket (obrigatório)
  R2_PREFIX              Prefixo dentro do bucket (padrão: coolify)
  RCLONE_REMOTE          Nome do remote rclone (ex.: r2). Opção 1 de upload.
  R2_ENDPOINT            Ex.: https://<ACCOUNT_ID>.r2.cloudflarestorage.com. Opção 2.
  R2_ACCESS_KEY_ID       Access key do token R2. Opção 2.
  R2_SECRET_ACCESS_KEY   Secret key do token R2. Opção 2.
  RETENTION_DAYS         Retenção no R2 (padrão: 30)
  LOCAL_BACKUP_DIR       Diretório local (padrão: /var/backups/coolify)
  LOCAL_RETENTION_DAYS   Retenção local (padrão: 7)
  ENCRYPT                1 = criptografa, 0 = não (padrão: 1)
  PASSPHRASE_FILE        Arquivo da passphrase (padrão: /etc/coolify-backup.passphrase)

Exemplo de uso em cron (/etc/cron.d/coolify-backup):
  0 3 * * * root /caminho/backup-coolify.sh >> /var/log/coolify-backup.log 2>&1

Restauração (resumo):
  1) Instale o Coolify na máquina de destino (de preferência na mesma versão).
  2) Baixe o .tar.gz.enc e o .sha256 do R2 e confira: sha256sum -c <arquivo>.sha256
  3) Descriptografe:
       openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
         -in coolify-backup-XXXX.tar.gz.enc -out coolify-backup-XXXX.tar.gz \
         -pass file:/etc/coolify-backup.passphrase
  4) Extraia para um diretório temporário:
       mkdir -p /tmp/coolify-restore
       tar -xzf coolify-backup-XXXX.tar.gz -C /tmp/coolify-restore
  5) Pare o painel: docker stop coolify coolify-redis
  6) Restaure o banco:
       docker exec -i coolify-db pg_restore --clean --if-exists --exit-on-error \
         --no-acl --no-owner --username=coolify --dbname=coolify \
         < /tmp/coolify-restore/coolify-db.dmp
  7) Máquina NOVA: NÃO extraia coolify-data.tar sobre /. Copie apenas o
     APP_KEY de coolify.env para o .env atual (mantenha DB_PASSWORD e
     REDIS_PASSWORD da instalação nova). Copie do backup para o destino:
       /data/coolify/ssh/keys/
       /data/coolify/applications|databases|services/ (se existirem)
     Mesma máquina: pode extrair coolify-data.tar sobre / e ajustar o dono:
       chown -R 9999:root /data/coolify
  8) Rode o instalador novamente para subir os containers.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        SHOW_HELP=1; shift ;;
      --init-config)
        OPT_INIT_CONFIG=1; shift ;;
      --force)
        OPT_FORCE=1; shift ;;
      --no-upload)
        OPT_NO_UPLOAD=1; shift ;;
      --no-encrypt)
        OPT_NO_ENCRYPT=1; shift ;;
      --config)
        [[ $# -ge 2 ]] || { erro "Faltou o valor de --config"; exit 1; }
        OPT_CONFIG="$2"; shift 2 ;;
      --config=*)
        OPT_CONFIG="${1#*=}"; shift ;;
      --local-dir)
        [[ $# -ge 2 ]] || { erro "Faltou o valor de --local-dir"; exit 1; }
        OPT_LOCAL_DIR="$2"; shift 2 ;;
      --local-dir=*)
        OPT_LOCAL_DIR="${1#*=}"; shift ;;
      --retention)
        [[ $# -ge 2 ]] || { erro "Faltou o valor de --retention"; exit 1; }
        OPT_RETENTION="$2"; shift 2 ;;
      --retention=*)
        OPT_RETENTION="${1#*=}"; shift ;;
      --prefix)
        [[ $# -ge 2 ]] || { erro "Faltou o valor de --prefix"; exit 1; }
        OPT_PREFIX="$2"; shift 2 ;;
      --prefix=*)
        OPT_PREFIX="${1#*=}"; shift ;;
      --passphrase-file)
        [[ $# -ge 2 ]] || { erro "Faltou o valor de --passphrase-file"; exit 1; }
        OPT_PASSPHRASE_FILE="$2"; shift 2 ;;
      --passphrase-file=*)
        OPT_PASSPHRASE_FILE="${1#*=}"; shift ;;
      *)
        erro "Opção inválida: $1"
        usage
        exit 1 ;;
    esac
  done
}

require_root() {
  if [[ "$EUID" -eq 0 ]]; then
    return 0
  fi
  if command -v sudo >/dev/null 2>&1; then
    info "Elevando privilégios com sudo..."
    exec sudo -- bash "$0" "$@"
  fi
  erro "Execute como root: sudo ./backup-coolify.sh"
  exit 1
}

create_config() {
  if [[ -e "$CONFIG_FILE" && "$OPT_FORCE" -ne 1 ]]; then
    erro "Já existe $CONFIG_FILE (use --force para sobrescrever)."
    exit 1
  fi

  umask 077
  mkdir -p "$(dirname "$CONFIG_FILE")"
  cat > "$CONFIG_FILE" <<'EOF'
# Configuração do backup da instância Coolify para Cloudflare R2.
# Arquivo com segredos: mantenha permissão 600 e fora do Git.

# Bucket de destino (obrigatório)
R2_BUCKET=""
R2_PREFIX="coolify"

# Opção 1 de upload: remote do rclone já configurado (ex.: r2)
RCLONE_REMOTE=""

# Opção 2 de upload: aws cli com endpoint S3 do R2
R2_ENDPOINT=""
R2_ACCESS_KEY_ID=""
R2_SECRET_ACCESS_KEY=""

# Retenção
RETENTION_DAYS=30
LOCAL_BACKUP_DIR="/var/backups/coolify"
LOCAL_RETENTION_DAYS=7

# Criptografia
ENCRYPT=1
PASSPHRASE_FILE="/etc/coolify-backup.passphrase"
EOF
  chmod 600 "$CONFIG_FILE"
  ok "Configuração criada: $CONFIG_FILE"

  if [[ ! -s "$PASSPHRASE_FILE" ]]; then
    if command -v openssl >/dev/null 2>&1; then
      umask 077
      openssl rand -base64 32 > "$PASSPHRASE_FILE"
      chmod 600 "$PASSPHRASE_FILE"
      ok "Passphrase gerada: $PASSPHRASE_FILE"
    else
      warn "openssl não encontrado; crie a passphrase manualmente em $PASSPHRASE_FILE"
    fi
  fi

  warn "Guarde a passphrase FORA deste servidor (gerenciador de senhas)."
  warn "Sem ela o backup criptografado NÃO pode ser restaurado."
  info "Edite $CONFIG_FILE e preencha R2_BUCKET e os dados de upload."
}

load_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    erro "Arquivo de configuração não encontrado: $CONFIG_FILE"
    info "Crie um modelo com: sudo ./backup-coolify.sh --init-config"
    exit 1
  fi
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
}

apply_overrides() {
  if [[ -n "$OPT_LOCAL_DIR" ]]; then
    LOCAL_BACKUP_DIR="$OPT_LOCAL_DIR"
  fi
  if [[ -n "$OPT_RETENTION" ]]; then
    RETENTION_DAYS="$OPT_RETENTION"
  fi
  if [[ -n "$OPT_PREFIX" ]]; then
    R2_PREFIX="$OPT_PREFIX"
  fi
  if [[ -n "$OPT_PASSPHRASE_FILE" ]]; then
    PASSPHRASE_FILE="$OPT_PASSPHRASE_FILE"
  fi
  if (( OPT_NO_UPLOAD )); then
    UPLOAD=0
  fi
  if (( OPT_NO_ENCRYPT )); then
    ENCRYPT=0
  fi
  R2_PREFIX="${R2_PREFIX#/}"
  R2_PREFIX="${R2_PREFIX%/}"
}

require_cmd() {
  local cmd="$1" pacote="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    erro "Comando '$cmd' não encontrado. Instale: $pacote"
    exit 1
  fi
}

upload_configurado() {
  if [[ -n "$RCLONE_REMOTE" ]]; then
    return 0
  fi
  if [[ -n "$R2_ENDPOINT" && -n "$R2_ACCESS_KEY_ID" && -n "$R2_SECRET_ACCESS_KEY" ]]; then
    return 0
  fi
  return 1
}

validate() {
  require_cmd docker "docker"
  require_cmd tar "tar"
  require_cmd gzip "gzip"
  require_cmd sha256sum "coreutils"
  require_cmd date "coreutils"
  require_cmd find "findutils"
  require_cmd getent "libc-bin"

  if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
    erro "RETENTION_DAYS inválido: $RETENTION_DAYS"
    exit 1
  fi
  if ! [[ "$LOCAL_RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
    erro "LOCAL_RETENTION_DAYS inválido: $LOCAL_RETENTION_DAYS"
    exit 1
  fi

  if (( UPLOAD )); then
    if ! upload_configurado; then
      erro "Upload habilitado, mas o R2 não está configurado."
      info "Preencha RCLONE_REMOTE ou R2_ENDPOINT/R2_ACCESS_KEY_ID/R2_SECRET_ACCESS_KEY em $CONFIG_FILE."
      exit 1
    fi
    if [[ -z "$R2_BUCKET" ]]; then
      erro "R2_BUCKET não definido em $CONFIG_FILE."
      exit 1
    fi
    if [[ -n "$RCLONE_REMOTE" ]]; then
      require_cmd rclone "rclone"
    else
      require_cmd aws "awscli"
    fi
  fi

  if (( ENCRYPT )); then
    require_cmd openssl "openssl"
    if [[ ! -s "$PASSPHRASE_FILE" ]]; then
      erro "Arquivo de passphrase ausente ou vazio: $PASSPHRASE_FILE"
      info "Gere com: sudo ./backup-coolify.sh --init-config"
      exit 1
    fi
  fi

  mkdir -p "$LOCAL_BACKUP_DIR"
}

env_get() {
  local chave="$1" linha valor
  linha="$(grep -E "^${chave}=" "$ENV_FILE" | tail -n 1 || true)"
  [[ -n "$linha" ]] || return 1
  valor="${linha#*=}"
  valor="${valor%$'\r'}"
  if [[ "$valor" == \"*\" && "$valor" == *\" ]]; then
    valor="${valor:1:${#valor}-2}"
  elif [[ "$valor" == \'*\' && "$valor" == *\' ]]; then
    valor="${valor:1:${#valor}-2}"
  fi
  printf '%s' "$valor"
}

check_coolify() {
  ENV_FILE="/data/coolify/source/.env"
  if [[ ! -r "$ENV_FILE" ]]; then
    erro "Arquivo não encontrado: $ENV_FILE"
    erro "Este servidor não parece ter uma instalação do Coolify."
    exit 1
  fi

  if [[ "$(docker inspect -f '{{.State.Running}}' coolify-db 2>/dev/null || printf 'false')" != "true" ]]; then
    erro "O container coolify-db não está rodando. Inicie o Coolify antes do backup."
    exit 1
  fi

  DB_USERNAME="$(env_get DB_USERNAME || true)"
  DB_USERNAME="${DB_USERNAME:-coolify}"
  DB_DATABASE="$(env_get DB_DATABASE || true)"
  DB_DATABASE="${DB_DATABASE:-coolify}"

  if ! docker exec coolify-db pg_isready -U "$DB_USERNAME" -d "$DB_DATABASE" >/dev/null 2>&1; then
    erro "PostgreSQL (coolify-db) não está aceitando conexões."
    exit 1
  fi

  if ! grep -q '^APP_KEY=.\+' "$ENV_FILE"; then
    warn "APP_KEY não encontrada em $ENV_FILE. O backup pode não restaurar credenciais."
  fi
}

dump_database() {
  local db_file="$1"
  info "Gerando dump do PostgreSQL (coolify-db)..."
  if ! docker exec coolify-db pg_dump \
      --format=custom --no-acl --no-owner \
      --username="$DB_USERNAME" "$DB_DATABASE" > "$db_file"; then
    erro "Falha ao executar pg_dump."
    exit 1
  fi
  if [[ ! -s "$db_file" ]]; then
    erro "Dump do banco vazio. Abortando."
    exit 1
  fi
  if ! docker exec -i coolify-db pg_restore --list < "$db_file" >/dev/null 2>&1; then
    erro "Dump gerado é inválido (pg_restore --list falhou)."
    exit 1
  fi
  ok "Banco: $(du -h "$db_file" | cut -f1)"
}

archive_data() {
  local data_tar="$1" status
  info "Arquivando /data/coolify (sem backups nativos, logs e mux)..."
  set +e
  tar -cf "$data_tar" -C / \
    --warning=no-file-changed \
    --exclude='data/coolify/backups' \
    --exclude='data/coolify/source/*.log' \
    --exclude='data/coolify/source/.upgrade-status' \
    --exclude='data/coolify/ssh/mux' \
    data/coolify
  status=$?
  set -e
  if (( status > 1 )); then
    erro "Falha ao arquivar /data/coolify (tar saiu com $status)."
    exit 1
  fi
  if (( status == 1 )); then
    warn "tar reportou avisos (arquivos alterados durante a cópia). Backup continuará."
  fi
  ok "Dados: $(du -h "$data_tar" | cut -f1)"
}

copy_authorized_keys() {
  local destino usuario home
  if [[ -f /root/.ssh/authorized_keys ]]; then
    cp -a /root/.ssh/authorized_keys "$WORK_DIR/authorized_keys.root"
    ok "authorized_keys do root incluído."
  else
    warn "/root/.ssh/authorized_keys não encontrado."
  fi

  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    usuario="$SUDO_USER"
    home="$(getent passwd "$usuario" | cut -d: -f6 || true)"
    if [[ -n "$home" && -f "$home/.ssh/authorized_keys" ]]; then
      destino="$WORK_DIR/authorized_keys.${usuario}"
      cp -a "$home/.ssh/authorized_keys" "$destino"
      ok "authorized_keys de $usuario incluído."
    fi
  fi
}

write_manifest() {
  local manifest="$1" coolify_image postgres_image
  coolify_image="$(docker inspect coolify --format '{{.Config.Image}}' 2>/dev/null || true)"
  postgres_image="$(docker inspect coolify-db --format '{{.Config.Image}}' 2>/dev/null || true)"

  {
    printf 'Backup da instância Coolify\n'
    printf 'Data: %s\n' "$(date -Is)"
    printf 'Host: %s\n' "$(hostname -f 2>/dev/null || hostname)"
    printf 'Coolify (imagem): %s\n' "${coolify_image:-desconhecida}"
    printf 'PostgreSQL (imagem): %s\n' "${postgres_image:-desconhecida}"
    printf 'Docker: %s\n' "$(docker --version 2>/dev/null || true)"
    printf '\n'
    printf 'Conteúdo:\n'
    printf '  coolify-db.dmp       dump pg_dump --format=custom do banco do Coolify\n'
    printf '  coolify-data.tar     /data/coolify (sem backups nativos, logs e mux)\n'
    printf '  coolify.env          cópia de /data/coolify/source/.env (contém APP_KEY)\n'
    printf '  authorized_keys.*    chaves públicas autorizadas do host\n'
    printf '\n'
    printf 'Observações:\n'
    printf '  - Redis não é incluído (cache/fila; recriado automaticamente).\n'
    printf '  - Dados de aplicações/bancos gerenciados exigem backup próprio.\n'
    printf '  - O APP_KEY está em coolify.env e dentro de coolify-data.tar.\n'
    printf '    Sem ele, credenciais criptografadas no banco não são legíveis.\n'
    printf '\n'
    printf 'Arquivos e tamanhos antes do empacotamento:\n'
    for arquivo in "$WORK_DIR"/*; do
      [[ -f "$arquivo" ]] || continue
      printf '  %-24s %s\n' "$(basename "$arquivo")" "$(du -h "$arquivo" | cut -f1)"
    done
  } > "$manifest"
}

upload_file() {
  local src="$1" key
  key="${R2_PREFIX:+${R2_PREFIX}/}$(basename "$src")"

  if [[ -n "$RCLONE_REMOTE" ]]; then
    rclone copyto "$src" "${RCLONE_REMOTE}:${R2_BUCKET}/${key}" \
      --retries 3 --low-level-retries 5 >/dev/null
  else
    AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" \
    AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" \
      aws s3 cp --endpoint-url "$R2_ENDPOINT" --region auto \
        "$src" "s3://${R2_BUCKET}/${key}" >/dev/null
  fi
}

verify_upload() {
  local src="$1" key tamanho_local tamanho_remoto
  key="${R2_PREFIX:+${R2_PREFIX}/}$(basename "$src")"
  tamanho_local="$(stat -c %s "$src")"

  if [[ -n "$RCLONE_REMOTE" ]]; then
    tamanho_remoto="$(rclone lsjson "${RCLONE_REMOTE}:${R2_BUCKET}/${key}" 2>/dev/null \
      | grep -o '"Size":[0-9]*' | head -n 1 | cut -d: -f2 || true)"
  else
    tamanho_remoto="$(AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" \
      AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" \
      aws s3api head-object --endpoint-url "$R2_ENDPOINT" --region auto \
        --bucket "$R2_BUCKET" --key "$key" \
        --query ContentLength --output text 2>/dev/null || true)"
  fi

  if [[ "$tamanho_remoto" != "$tamanho_local" ]]; then
    erro "Verificação falhou para $(basename "$src") (local=$tamanho_local remoto=${tamanho_remoto:-?})."
    return 1
  fi
}

apply_local_retention() {
  find "$LOCAL_BACKUP_DIR" -maxdepth 1 -type f \
    -name 'coolify-backup-*' -mtime +"$LOCAL_RETENTION_DAYS" -delete 2>/dev/null || true
}

apply_remote_retention() {
  if (( RETENTION_DAYS == 0 )); then
    return 0
  fi

  info "Aplicando retenção no R2 (${RETENTION_DAYS} dias)..."
  if [[ -n "$RCLONE_REMOTE" ]]; then
    local remote_path="${RCLONE_REMOTE}:${R2_BUCKET}"
    if [[ -n "$R2_PREFIX" ]]; then
      remote_path="${remote_path}/${R2_PREFIX}"
    fi
    rclone delete "$remote_path" --min-age "${RETENTION_DAYS}d" \
      --include 'coolify-backup-*' --retries 3 >/dev/null 2>&1 \
      || warn "Não foi possível aplicar retenção remota via rclone."
  else
    local cutoff_epoch linha key last last_epoch
    local -a linhas=()
    cutoff_epoch="$(date -u -d "-${RETENTION_DAYS} days" +%s)"
    mapfile -t linhas < <(
      AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" \
      AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" \
      aws s3api list-objects-v2 --endpoint-url "$R2_ENDPOINT" --region auto \
        --bucket "$R2_BUCKET" --prefix "${R2_PREFIX:+${R2_PREFIX}/}" \
        --query 'Contents[*].[Key,LastModified]' --output text 2>/dev/null || true
    )
    for linha in "${linhas[@]}"; do
      [[ -n "$linha" ]] || continue
      key="${linha%%$'\t'*}"
      last="${linha#*$'\t'}"
      [[ "$key" == *coolify-backup-* ]] || continue
      last_epoch="$(date -u -d "$last" +%s 2>/dev/null || printf '0')"
      if (( last_epoch > 0 && last_epoch < cutoff_epoch )); then
        AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" \
        AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" \
          aws s3 rm --endpoint-url "$R2_ENDPOINT" --region auto \
            "s3://${R2_BUCKET}/${key}" >/dev/null 2>&1 \
          || warn "Falha ao remover objeto antigo: $key"
      fi
    done
  fi
}

main() {
  parse_args "$@"

  if (( SHOW_HELP )); then
    usage
    exit 0
  fi

  if [[ -n "$OPT_CONFIG" ]]; then
    CONFIG_FILE="$OPT_CONFIG"
  fi

  require_root "$@"

  if (( OPT_INIT_CONFIG )); then
    create_config
    exit 0
  fi

  load_config
  apply_overrides
  validate

  info "=== Iniciando backup do Coolify ==="
  check_coolify

  WORK_DIR="$(mktemp -d)"
  trap 'rm -rf "$WORK_DIR"' EXIT

  local db_file="$WORK_DIR/coolify-db.dmp"
  local data_tar="$WORK_DIR/coolify-data.tar"
  local timestamp nome_base bundle upload_file_path checksum_file

  dump_database "$db_file"
  archive_data "$data_tar"

  cp -a "$ENV_FILE" "$WORK_DIR/coolify.env"
  chmod 600 "$WORK_DIR/coolify.env"
  ok "Arquivo .env (APP_KEY) incluído."

  copy_authorized_keys
  write_manifest "$WORK_DIR/manifest.txt"

  timestamp="$(date +%Y%m%d-%H%M%S)"
  nome_base="coolify-backup-${timestamp}"
  bundle="$LOCAL_BACKUP_DIR/${nome_base}.tar.gz"

  info "Empacotando backup..."
  if ! tar -czf "$bundle" -C "$WORK_DIR" .; then
    erro "Falha ao criar o pacote final."
    exit 1
  fi

  if (( ENCRYPT )); then
    upload_file_path="${bundle}.enc"
    info "Criptografando pacote (AES-256)..."
    if ! openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt \
        -in "$bundle" -out "$upload_file_path" -pass "file:$PASSPHRASE_FILE"; then
      erro "Falha ao criptografar o pacote."
      exit 1
    fi
    rm -f "$bundle"
    ok "Pacote criptografado."
  else
    upload_file_path="$bundle"
    warn "Pacote NÃO criptografado (--no-encrypt)."
  fi

  checksum_file="${upload_file_path}.sha256"
  (
    cd "$(dirname "$upload_file_path")"
    sha256sum "$(basename "$upload_file_path")" > "$(basename "$checksum_file")"
  )

  if (( UPLOAD )); then
    info "Enviando para o Cloudflare R2..."
    if ! upload_file "$upload_file_path"; then
      erro "Falha no upload do pacote para o R2."
      exit 1
    fi
    if ! upload_file "$checksum_file"; then
      erro "Falha no upload do checksum para o R2."
      exit 1
    fi
    if ! verify_upload "$upload_file_path"; then
      exit 1
    fi
    if ! verify_upload "$checksum_file"; then
      exit 1
    fi
    ok "Upload concluído."
  else
    warn "Upload desativado (--no-upload)."
  fi

  apply_local_retention
  if (( UPLOAD )); then
    apply_remote_retention
  fi

  printf '\n'
  ok "=== Backup concluído ==="
  info "Local:   $upload_file_path"
  info "SHA256:  $(cut -d' ' -f1 "$checksum_file")"
  if (( UPLOAD )); then
    info "R2:      ${RCLONE_REMOTE:+${RCLONE_REMOTE}:}${R2_BUCKET}/${R2_PREFIX:+${R2_PREFIX}/}$(basename "$upload_file_path")"
  fi
  printf '\n'
  if (( ENCRYPT )); then
    warn "Guarde a passphrase ($PASSPHRASE_FILE) FORA deste servidor."
    warn "Sem ela o backup NÃO pode ser restaurado."
  fi
  info "Restauração: consulte './backup-coolify.sh --help'."
}

main "$@"
