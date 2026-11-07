#!/usr/bin/env bash
#
# restore-instancia.sh - restaura o plano de controle do Coolify
#
# Restaura o pacote gerado por backup-instancia.sh:
#   - baixa do Cloudflare R2 (ou usa um arquivo local)
#   - confere o SHA-256
#   - descriptografa com a passphrase
#   - restaura o banco interno (coolify-db) via pg_restore
#   - restaura /data/coolify (mesma maquina ou maquina nova)
#   - sobe os containers com docker compose
#
# ATENCAO: sobrescreve o banco e os arquivos atuais do Coolify.
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

DATA_DIR="/data/coolify"
ENV_FILE="$DATA_DIR/source/.env"

CONFIG_FILE="/etc/coolify-backup.env"
PASSPHRASE_FILE="/etc/coolify-backup.passphrase"
OPT_PASSPHRASE_FILE=""

SOURCE_FILE=""
DOWNLOAD=0
R2_KEY=""
MODE="same"
WORK=""
KEEP=0
START=1
SKIP_VERIFY=0
ASSUME_YES=0
SHOW_HELP=0

ORIGINAL_ARGS=("$@")

usage() {
  cat <<'EOF'
Uso: ./restore-instancia.sh [opções] [ARQUIVO.tar.enc]

Restaura um backup do plano de controle do Coolify.

ATENÇÃO: sobrescreve o banco e os arquivos do Coolify atual. Use com cuidado.

Origem do pacote (escolha uma):
  --file ARQUIVO       Pacote .tar.enc local (ou informe como argumento)
  --download           Baixa o backup mais recente do R2
  --r2-key CHAVE       Baixa uma chave específica do R2

Opções:
  --config ARQUIVO     Configuração do backup (padrão: /etc/coolify-backup.env)
  --passphrase-file ARQUIVO  Arquivo da passphrase
  --mode same|new      same = mesma máquina (padrão), new = máquina nova
  --work-dir DIR       Diretório de trabalho (padrão: mktemp)
  --keep               Mantém os arquivos extraídos ao final
  --no-start           Não sobe os containers depois do restore
  --skip-verify        Continua mesmo sem o arquivo .sha256
  --yes                Não pedir confirmação
  -h, --help           Mostrar esta ajuda

Modos:
  same  copia todo o /data/coolify do backup por cima do atual
  new   não sobrescreve source/.env; restaura ssh/keys, applications,
        databases e services, e copia apenas o APP_KEY para o .env atual

Exemplos:
  sudo ./restore-instancia.sh --download
  sudo ./restore-instancia.sh --download --mode new
  sudo ./restore-instancia.sh --file /root/coolify-instancia-20261107.tar.enc
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file)
        [[ $# -ge 2 ]] || { erro "Faltou o valor de --file"; exit 1; }
        SOURCE_FILE="$2"; shift 2 ;;
      --file=*)
        SOURCE_FILE="${1#*=}"; shift ;;
      --download)
        DOWNLOAD=1; shift ;;
      --r2-key)
        [[ $# -ge 2 ]] || { erro "Faltou o valor de --r2-key"; exit 1; }
        DOWNLOAD=1; R2_KEY="$2"; shift 2 ;;
      --r2-key=*)
        DOWNLOAD=1; R2_KEY="${1#*=}"; shift ;;
      --config)
        [[ $# -ge 2 ]] || { erro "Faltou o valor de --config"; exit 1; }
        CONFIG_FILE="$2"; shift 2 ;;
      --config=*)
        CONFIG_FILE="${1#*=}"; shift ;;
      --passphrase-file)
        [[ $# -ge 2 ]] || { erro "Faltou o valor de --passphrase-file"; exit 1; }
        OPT_PASSPHRASE_FILE="$2"; shift 2 ;;
      --passphrase-file=*)
        OPT_PASSPHRASE_FILE="${1#*=}"; shift ;;
      --mode)
        [[ $# -ge 2 ]] || { erro "Faltou o valor de --mode"; exit 1; }
        MODE="$2"; shift 2 ;;
      --mode=*)
        MODE="${1#*=}"; shift ;;
      --work-dir)
        [[ $# -ge 2 ]] || { erro "Faltou o valor de --work-dir"; exit 1; }
        WORK="$2"; shift 2 ;;
      --work-dir=*)
        WORK="${1#*=}"; shift ;;
      --keep)
        KEEP=1; shift ;;
      --no-start)
        START=0; shift ;;
      --skip-verify)
        SKIP_VERIFY=1; shift ;;
      --yes|-y)
        ASSUME_YES=1; shift ;;
      -h|--help)
        SHOW_HELP=1; shift ;;
      -*)
        erro "Opção inválida: $1"
        usage
        exit 1 ;;
      *)
        if [[ -z "$SOURCE_FILE" ]]; then
          SOURCE_FILE="$1"; shift
        else
          erro "Argumento inesperado: $1"
          exit 1
        fi ;;
    esac
  done
}

require_root() {
  if [[ "$EUID" -eq 0 ]]; then
    return 0
  fi
  if command -v sudo >/dev/null 2>&1; then
    info "Elevando privilégios com sudo..."
    exec sudo -- bash "$0" "${ORIGINAL_ARGS[@]}"
  fi
  erro "Execute como root: sudo ./restore-instancia.sh"
  exit 1
}

validate_options() {
  if [[ "$MODE" != "same" && "$MODE" != "new" ]]; then
    erro "--mode deve ser 'same' ou 'new' (recebido: $MODE)"
    exit 1
  fi
  if (( DOWNLOAD )) && [[ -n "$SOURCE_FILE" ]]; then
    erro "Use --file OU --download/--r2-key, não os dois."
    exit 1
  fi
  if (( ! DOWNLOAD )) && [[ -z "$SOURCE_FILE" ]]; then
    erro "Informe o pacote com --file, --download ou --r2-key."
    usage
    exit 1
  fi
}

load_config() {
  if [[ -r "$CONFIG_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    set +a
    ok "Configuração carregada: $CONFIG_FILE"
  else
    warn "Configuração não encontrada: $CONFIG_FILE"
    warn "Isso é normal ao restaurar apenas com --file sem usar o R2."
  fi
  if [[ -n "$OPT_PASSPHRASE_FILE" ]]; then
    PASSPHRASE_FILE="$OPT_PASSPHRASE_FILE"
  fi
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || { erro "Comando não encontrado: $cmd"; exit 1; }
}

check_environment() {
  require_cmd docker
  require_cmd openssl
  require_cmd tar
  require_cmd sha256sum

  if [[ ! -r "$ENV_FILE" ]]; then
    erro "Arquivo não encontrado: $ENV_FILE"
    erro "Instale o Coolify (na mesma versão do backup) antes de restaurar."
    exit 1
  fi

  if [[ "$(docker inspect -f '{{.State.Running}}' coolify-db 2>/dev/null || true)" != "true" ]]; then
    erro "O container coolify-db não está rodando. Inicie-o antes do restore."
    exit 1
  fi

  if [[ ! -r "$PASSPHRASE_FILE" || ! -s "$PASSPHRASE_FILE" ]]; then
    erro "Passphrase ausente ou vazia: $PASSPHRASE_FILE"
    erro "Informe com --passphrase-file ou restaure o arquivo original."
    exit 1
  fi
}

download_package() {
  : "${R2_BUCKET:?defina R2_BUCKET em $CONFIG_FILE ou use --file}"
  : "${R2_ENDPOINT:?defina R2_ENDPOINT em $CONFIG_FILE ou use --file}"
  require_cmd aws

  local prefix key base
  prefix="${R2_PREFIX:+${R2_PREFIX}/}"
  key="$R2_KEY"

  if [[ -z "$key" ]]; then
    info "Buscando o backup mais recente em s3://$R2_BUCKET/$prefix ..."
    key="$(aws --region auto --endpoint-url "$R2_ENDPOINT" \
      s3api list-objects-v2 --bucket "$R2_BUCKET" --prefix "$prefix" \
      --query 'Contents[].Key' --output text 2>/dev/null \
      | tr '\t' '\n' | grep -E '\.tar\.enc$' | sort | tail -n 1 || true)"
    if [[ -z "$key" ]]; then
      erro "Nenhum arquivo .tar.enc encontrado em s3://$R2_BUCKET/$prefix"
      exit 1
    fi
  fi

  base="$(basename "$key")"
  info "Baixando $key ..."
  aws --region auto --endpoint-url "$R2_ENDPOINT" --only-show-errors \
    s3 cp "s3://$R2_BUCKET/$key" "$WORK/$base"
  if ! aws --region auto --endpoint-url "$R2_ENDPOINT" --only-show-errors \
      s3 cp "s3://$R2_BUCKET/$key.sha256" "$WORK/$base.sha256" 2>/dev/null; then
    warn "Checksum não encontrado no R2: $key.sha256"
  fi
  SOURCE_FILE="$WORK/$base"
}

prepare_source() {
  umask 077
  if [[ -z "$WORK" ]]; then
    WORK="$(mktemp -d "${TMPDIR:-/tmp}/coolify-restore.XXXXXX")"
  else
    mkdir -p "$WORK"
  fi

  if (( DOWNLOAD )); then
    download_package
    return 0
  fi

  if [[ ! -f "$SOURCE_FILE" ]]; then
    erro "Arquivo não encontrado: $SOURCE_FILE"
    exit 1
  fi

  local base
  base="$(basename "$SOURCE_FILE")"
  if [[ "$(cd "$(dirname "$SOURCE_FILE")" && pwd)" != "$WORK" ]]; then
    info "Copiando pacote para $WORK ..."
    cp -a "$SOURCE_FILE" "$WORK/$base"
    if [[ -f "$SOURCE_FILE.sha256" ]]; then
      cp -a "$SOURCE_FILE.sha256" "$WORK/$base.sha256"
    fi
  fi
  SOURCE_FILE="$WORK/$base"
}

verify_checksum() {
  local base
  base="$(basename "$SOURCE_FILE")"

  if [[ -f "$SOURCE_FILE.sha256" ]]; then
    info "Conferindo SHA-256..."
    if ! (cd "$WORK" && sha256sum -c "$base.sha256"); then
      erro "Checksum inválido: pacote corrompido ou incompleto."
      exit 1
    fi
    ok "Checksum OK."
  elif (( SKIP_VERIFY )); then
    warn "Checksum não encontrado; continuando por causa de --skip-verify."
  else
    erro "Checksum não encontrado: $SOURCE_FILE.sha256"
    erro "Use --skip-verify para continuar mesmo assim (não recomendado)."
    exit 1
  fi
}

decrypt_package() {
  info "Descriptografando pacote..."
  if ! openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
      -in "$SOURCE_FILE" -out "$WORK/instancia.tar" \
      -pass "file:$PASSPHRASE_FILE"; then
    erro "Falha ao descriptografar. Passphrase incorreta ou pacote inválido."
    exit 1
  fi

  rm -rf "$WORK/files" "$WORK/db.dmp" "$WORK/data.tar.gz"
  tar -xf "$WORK/instancia.tar" -C "$WORK"
  rm -f "$WORK/instancia.tar"

  [[ -s "$WORK/db.dmp" ]] || { erro "db.dmp ausente ou vazio no pacote."; exit 1; }
  [[ -s "$WORK/data.tar.gz" ]] || { erro "data.tar.gz ausente ou vazio no pacote."; exit 1; }
  ok "Pacote extraído."
}

extract_files() {
  info "Extraindo arquivos de /data/coolify..."
  mkdir -p "$WORK/files"
  tar -xzf "$WORK/data.tar.gz" -C "$WORK/files"
  if [[ ! -d "$WORK/files/coolify" ]]; then
    erro "Estrutura inesperada: diretório 'coolify' não encontrado no pacote."
    exit 1
  fi
  ok "Arquivos extraídos."
}

validate_dump() {
  info "Validando dump do PostgreSQL..."
  if ! docker exec -i coolify-db pg_restore --list < "$WORK/db.dmp" >/dev/null 2>&1; then
    erro "Dump inválido: pg_restore --list falhou. Nada foi alterado."
    exit 1
  fi
  ok "Dump válido."
}

confirm_restore() {
  if (( ASSUME_YES )); then
    return 0
  fi

  local resp
  printf '\n'
  warn "ATENÇÃO: o banco e os arquivos atuais do Coolify serão sobrescritos."
  printf '  Pacote:  %s\n' "$(basename "$SOURCE_FILE")"
  printf '  Modo:    %s\n' "$MODE"
  printf '  Destino: %s\n' "$DATA_DIR"
  printf '%b?%b Digite "RESTAURAR" para confirmar: ' "$COR_VERMELHA" "$COR_RESET"
  read -r resp
  [[ "$resp" == "RESTAURAR" ]]
}

stop_panel() {
  info "Parando coolify e coolify-redis (coolify-db permanece)..."
  docker stop coolify coolify-redis >/dev/null 2>&1 || true
}

restore_database() {
  local db_user db_name
  db_user="$(docker exec coolify-db printenv POSTGRES_USER 2>/dev/null || true)"
  db_name="$(docker exec coolify-db printenv POSTGRES_DB 2>/dev/null || true)"
  db_user="${db_user:-coolify}"
  db_name="${db_name:-coolify}"

  info "Restaurando banco '$db_name' (usuário '$db_user')..."
  if ! docker exec -i coolify-db pg_restore \
      --clean --if-exists --exit-on-error --no-acl --no-owner \
      --username="$db_user" --dbname="$db_name" < "$WORK/db.dmp"; then
    erro "Falha ao restaurar o banco. O painel permanece parado; investigue antes de subir."
    return 1
  fi
  ok "Banco restaurado."
}

patch_app_key() {
  local origem="$WORK/files/coolify/source/.env"
  local destino="$ENV_FILE"
  local app_key tmp linha

  if [[ ! -r "$origem" ]]; then
    erro "APP_KEY não encontrada: $origem ausente no backup."
    return 1
  fi

  app_key="$(grep -E '^APP_KEY=' "$origem" | tail -n 1 | cut -d= -f2- || true)"
  app_key="${app_key%\"}"
  app_key="${app_key#\"}"
  if [[ -z "$app_key" ]]; then
    erro "APP_KEY vazia no .env do backup."
    return 1
  fi

  tmp="$(mktemp)"
  while IFS= read -r linha || [[ -n "$linha" ]]; do
    if [[ "$linha" =~ ^APP_KEY= ]]; then
      printf 'APP_KEY=%s\n' "$app_key"
    else
      printf '%s\n' "$linha"
    fi
  done < "$destino" > "$tmp"
  cat "$tmp" > "$destino"
  rm -f "$tmp"
  ok "APP_KEY restaurada (DB_PASSWORD e REDIS_PASSWORD mantidos)."
}

restore_files_same() {
  info "Copiando $DATA_DIR do backup sobre a instalação atual..."
  cp -a "$WORK/files/coolify/." "$DATA_DIR/"
  chown -R 9999:root "$DATA_DIR"
  ok "Arquivos restaurados (modo same)."
}

restore_files_new() {
  local origem="$WORK/files/coolify" destino="$DATA_DIR" d
  info "Restaurando arquivos para uma instalação nova (modo new)..."

  if [[ -d "$origem/ssh/keys" ]]; then
    mkdir -p "$destino/ssh/keys"
    cp -a "$origem/ssh/keys/." "$destino/ssh/keys/"
    ok "Chaves SSH restauradas."
  else
    warn "ssh/keys não encontrado no backup."
  fi

  for d in applications databases services; do
    if [[ -d "$origem/$d" ]]; then
      mkdir -p "$destino/$d"
      cp -a "$origem/$d/." "$destino/$d/"
      ok "Diretório $d restaurado."
    fi
  done

  patch_app_key
  chown -R 9999:root "$destino"
  ok "Arquivos restaurados (source/.env preservado)."
}

start_panel() {
  if (( ! START )); then
    warn "Containers não iniciados (--no-start)."
    return 0
  fi

  info "Subindo containers..."
  if (cd "$DATA_DIR/source" && docker compose up -d); then
    ok "Containers iniciados."
    return 0
  fi

  if command -v docker-compose >/dev/null 2>&1 && \
     (cd "$DATA_DIR/source" && docker-compose up -d); then
    ok "Containers iniciados (docker-compose)."
    return 0
  fi

  erro "Falha ao subir os containers."
  erro "Rode manualmente: cd $DATA_DIR/source && docker compose up -d"
  return 1
}

show_status() {
  printf '\n'
  info "Containers do Coolify:"
  docker ps --filter 'name=coolify' --format '  {{.Names}}\t{{.Status}}' 2>/dev/null || true
}

print_summary() {
  printf '\n'
  ok "=== Restore concluído ==="
  printf '  Pacote: %s\n' "$(basename "$SOURCE_FILE")"
  printf '  Modo:   %s\n' "$MODE"
  printf '\n'
  info "Confira o login, os recursos e rode um deploy de teste."
  if (( KEEP )); then
    info "Arquivos mantidos em: $WORK"
  fi
}

cleanup() {
  local rc=$?
  if [[ -n "$WORK" && -d "$WORK" ]]; then
    if (( rc == 0 && ! KEEP )); then
      rm -rf "$WORK"
    else
      warn "Arquivos mantidos para análise: $WORK"
    fi
  fi
}

main() {
  local start_failed=0

  parse_args "$@"

  if (( SHOW_HELP )); then
    usage
    exit 0
  fi

  require_root
  validate_options
  load_config
  check_environment

  trap cleanup EXIT
  prepare_source

  verify_checksum
  decrypt_package
  extract_files
  validate_dump

  if ! confirm_restore; then
    warn "Cancelado."
    exit 0
  fi

  stop_panel

  if ! restore_database; then
    exit 1
  fi

  if [[ "$MODE" == "same" ]]; then
    restore_files_same
  else
    restore_files_new
  fi

  if ! start_panel; then
    start_failed=1
  fi

  show_status
  print_summary

  if (( start_failed )); then
    erro "Restore concluído, mas os containers não subiram. Verifique antes de usar."
    exit 1
  fi
}

main "$@"
