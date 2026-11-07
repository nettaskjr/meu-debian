#!/usr/bin/env bash
#
# backup-instancia.sh - backup do plano de controle do Coolify para Cloudflare R2
#
# Inclui:
#   - dump pg_dump --format=custom do PostgreSQL do Coolify (coolify-db)
#   - /data/coolify (source/.env, chaves SSH, aplicacoes/bancos/servicos, proxy)
#     sem backups nativos, logs e mux
#
# Nao inclui:
#   - bancos e volumes das aplicacoes (esses vao pelo backup nativo do Coolify)
#
# O pacote e criptografado com AES-256-CBC antes de ir para o R2.
# Configuracao: /etc/coolify-backup.env (veja coolify-backup.env.example).
#
set -euo pipefail

export PATH=/usr/local/bin:/usr/bin:/bin
umask 077

CONFIG="${COOLIFY_BACKUP_CONFIG:-/etc/coolify-backup.env}"

[[ $EUID -eq 0 ]] || { echo "execute como root" >&2; exit 1; }
[[ -r "$CONFIG" ]] || { echo "configuracao ausente: $CONFIG" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$CONFIG"
set +a

WORK_BASE="${WORK_BASE:-/var/backups/coolify}"
KEEP_LOCAL="${KEEP_LOCAL:-0}"
R2_PREFIX="${R2_PREFIX:-instancia}"
PASSPHRASE_FILE="${PASSPHRASE_FILE:-/etc/coolify-backup.passphrase}"

: "${R2_BUCKET:?defina R2_BUCKET em $CONFIG}"
: "${R2_ENDPOINT:?defina R2_ENDPOINT em $CONFIG}"
: "${AWS_ACCESS_KEY_ID:?defina AWS_ACCESS_KEY_ID em $CONFIG}"
: "${AWS_SECRET_ACCESS_KEY:?defina AWS_SECRET_ACCESS_KEY em $CONFIG}"

R2_PREFIX="${R2_PREFIX#/}"
R2_PREFIX="${R2_PREFIX%/}"
R2_PREFIX="${R2_PREFIX:-instancia}"

for cmd in docker tar openssl sha256sum aws stat; do
  command -v "$cmd" >/dev/null || { echo "comando ausente: $cmd" >&2; exit 1; }
done

[[ -r "$PASSPHRASE_FILE" ]] || { echo "passphrase ausente: $PASSPHRASE_FILE" >&2; exit 1; }
[[ -r /data/coolify/source/.env ]] || { echo "Coolify nao encontrado em /data/coolify" >&2; exit 1; }
[[ "$(docker inspect -f '{{.State.Running}}' coolify-db 2>/dev/null || true)" == "true" ]] \
  || { echo "o container coolify-db nao esta rodando" >&2; exit 1; }

DB_USER="$(docker exec coolify-db printenv POSTGRES_USER 2>/dev/null || true)"
DB_NAME="$(docker exec coolify-db printenv POSTGRES_DB 2>/dev/null || true)"
DB_USER="${DB_USER:-coolify}"
DB_NAME="${DB_NAME:-coolify}"

mkdir -p "$WORK_BASE"
WORK="$(mktemp -d "$WORK_BASE/run.XXXXXX")"

cleanup() {
  local rc=$?
  if [[ $rc -eq 0 && "$KEEP_LOCAL" != "1" ]]; then
    rm -rf "$WORK"
  else
    echo "[!] backup incompleto (rc=$rc); arquivos mantidos em $WORK" >&2
  fi
}
trap cleanup EXIT

echo "[*] gerando dump do PostgreSQL (coolify-db)..."
docker exec coolify-db pg_dump --format=custom --no-acl --no-owner \
  --username="$DB_USER" "$DB_NAME" > "$WORK/db.dmp"
[[ -s "$WORK/db.dmp" ]] || { echo "dump vazio; abortando" >&2; exit 1; }

echo "[*] arquivando /data/coolify..."
set +e
tar -czf "$WORK/data.tar.gz" -C /data \
  --exclude='coolify/backups' \
  --exclude='coolify/source/*.log' \
  --exclude='coolify/source/.upgrade-status' \
  --exclude='coolify/ssh/mux' \
  coolify
tar_rc=$?
set -e

if (( tar_rc > 1 )); then
  echo "falha ao arquivar /data/coolify (tar rc=$tar_rc)" >&2
  exit 1
elif (( tar_rc == 1 )); then
  echo "[!] aviso: arquivos mudaram durante a leitura; seguindo"
fi

echo "[*] empacotando e criptografando..."
tar -cf "$WORK/instancia.tar" -C "$WORK" db.dmp data.tar.gz
DATE="$(date +%Y%m%d_%H%M%S)"
ENC="coolify-instancia-$DATE.tar.enc"

openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt \
  -in "$WORK/instancia.tar" -out "$WORK/$ENC" \
  -pass "file:$PASSPHRASE_FILE"

rm -f "$WORK/instancia.tar" "$WORK/db.dmp" "$WORK/data.tar.gz"
(cd "$WORK" && sha256sum "$ENC" > "$ENC.sha256")

echo "[*] enviando para s3://$R2_BUCKET/$R2_PREFIX/ ..."
aws --region auto --endpoint-url "$R2_ENDPOINT" --only-show-errors \
  s3 cp "$WORK/$ENC" "s3://$R2_BUCKET/$R2_PREFIX/$ENC"
aws --region auto --endpoint-url "$R2_ENDPOINT" --only-show-errors \
  s3 cp "$WORK/$ENC.sha256" "s3://$R2_BUCKET/$R2_PREFIX/$ENC.sha256"

echo "[*] verificando upload..."
remote_size="$(aws --region auto --endpoint-url "$R2_ENDPOINT" \
  s3api head-object --bucket "$R2_BUCKET" --key "$R2_PREFIX/$ENC" \
  --query ContentLength --output text)"
local_size="$(stat -c %s "$WORK/$ENC")"

[[ "$remote_size" == "$local_size" ]] \
  || { echo "tamanho remoto ($remote_size) difere do local ($local_size)" >&2; exit 1; }

echo "[ok] $R2_PREFIX/$ENC ($local_size bytes)"
