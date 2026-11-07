#!/usr/bin/env bash
#
# instala-backup-instancia.sh - instala o backup do plano de controle do Coolify
#
# Instala e configura:
#   /usr/local/bin/coolify-backup.sh     script de backup (backup-instancia.sh)
#   /etc/coolify-backup.env              configuracao do Cloudflare R2 (600)
#   /etc/coolify-backup.passphrase       chave de criptografia AES-256 (600)
#   /etc/cron.d/coolify-backup           execucao diaria com flock
#   /etc/logrotate.d/coolify-backup      rotacao do log de backup
#
# O script e idempotente: rodar de novo atualiza script/cron/logrotate, mas
# preserva a configuracao e a passphrase existentes (use --force para o .env).
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SRC="$SCRIPT_DIR/backup-instancia.sh"
RESTORE_SRC="$SCRIPT_DIR/restore-instancia.sh"
ENV_EXAMPLE="$SCRIPT_DIR/coolify-backup.env.example"

DEST_SCRIPT="/usr/local/bin/coolify-backup.sh"
DEST_RESTORE="/usr/local/bin/coolify-restore.sh"
CONFIG_FILE="/etc/coolify-backup.env"
PASSPHRASE_FILE="/etc/coolify-backup.passphrase"
CRON_FILE="/etc/cron.d/coolify-backup"
LOGROTATE_FILE="/etc/logrotate.d/coolify-backup"
LOG_FILE="/var/log/coolify-backup.log"
LOCK_FILE="/var/lock/coolify-backup.lock"
CRON_SCHEDULE="30 3 * * *"
CRON_USER="root"
LOGROTATE_ROTATE=8

ORIGINAL_ARGS=("$@")

ASSUME_YES=0
FORCE=0
INSTALL_DEPS=1
INSTALL_CRON=1
INSTALL_LOGROTATE=1
RUN_TEST=0
SHOW_HELP=0

usage() {
  cat <<'EOF'
Uso: ./instala-backup-instancia.sh [opções]

Instala o backup do plano de controle do Coolify para Cloudflare R2.

O que é instalado:
  /usr/local/bin/coolify-backup.sh     script de backup
  /usr/local/bin/coolify-restore.sh    script de restauração
  /etc/coolify-backup.env              configuração do R2 (modo 600)
  /etc/coolify-backup.passphrase       chave de criptografia (modo 600)
  /etc/cron.d/coolify-backup           execução diária com flock
  /etc/logrotate.d/coolify-backup      rotação do log de backup

Opções:
  -y, --yes          Não pedir confirmação nem perguntar dados do R2
  --force            Sobrescrever /etc/coolify-backup.env existente
  --config ARQUIVO   Configuração alternativa (padrão: /etc/coolify-backup.env)
  --dest CAMINHO     Destino do script (padrão: /usr/local/bin/coolify-backup.sh)
  --schedule "CRON"  Agendamento do cron (padrão: "30 3 * * *")
  --skip-deps        Não instalar dependências via apt
  --no-cron          Não criar/atualizar o cron
  --no-logrotate     Não criar/atualizar o logrotate
  --test             Rodar um backup de teste ao final
  -h, --help         Mostrar esta ajuda

Exemplo:
  sudo ./instala-backup-instancia.sh
  sudo ./instala-backup-instancia.sh -y --test
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes)
        ASSUME_YES=1; shift ;;
      --force)
        FORCE=1; shift ;;
      --skip-deps)
        INSTALL_DEPS=0; shift ;;
      --no-cron)
        INSTALL_CRON=0; shift ;;
      --no-logrotate)
        INSTALL_LOGROTATE=0; shift ;;
      --test)
        RUN_TEST=1; shift ;;
      --config)
        [[ $# -ge 2 ]] || { erro "Faltou o valor de --config"; exit 1; }
        CONFIG_FILE="$2"; shift 2 ;;
      --config=*)
        CONFIG_FILE="${1#*=}"; shift ;;
      --dest)
        [[ $# -ge 2 ]] || { erro "Faltou o valor de --dest"; exit 1; }
        DEST_SCRIPT="$2"; shift 2 ;;
      --dest=*)
        DEST_SCRIPT="${1#*=}"; shift ;;
      --schedule)
        [[ $# -ge 2 ]] || { erro "Faltou o valor de --schedule"; exit 1; }
        CRON_SCHEDULE="$2"; shift 2 ;;
      --schedule=*)
        CRON_SCHEDULE="${1#*=}"; shift ;;
      -h|--help)
        SHOW_HELP=1; shift ;;
      *)
        erro "Opção inválida: $1"
        usage
        exit 1 ;;
    esac
  done
}

confirm() {
  local pergunta="$1" resp
  if (( ASSUME_YES )); then
    return 0
  fi
  printf '%b?%b %s (S/n): ' "$COR_AMARELA" "$COR_RESET" "$pergunta"
  read -r resp
  [[ -z "$resp" || "$resp" =~ ^[Ss]$ ]]
}

require_root() {
  if [[ "$EUID" -eq 0 ]]; then
    return 0
  fi
  if command -v sudo >/dev/null 2>&1; then
    info "Elevando privilégios com sudo..."
    exec sudo -- bash "$0" "${ORIGINAL_ARGS[@]}"
  fi
  erro "Execute como root: sudo ./instala-backup-instancia.sh"
  exit 1
}

check_environment() {
  if ! command -v docker >/dev/null 2>&1; then
    erro "Docker não encontrado. Este script deve rodar no host com o Coolify."
    exit 1
  fi

  if [[ ! -r /data/coolify/source/.env ]]; then
    erro "Arquivo não encontrado: /data/coolify/source/.env"
    erro "Este servidor não parece ter uma instalação do Coolify."
    exit 1
  fi

  if [[ ! -f "$BACKUP_SRC" ]]; then
    erro "Script de backup não encontrado: $BACKUP_SRC"
    exit 1
  fi

  if [[ ! -f "$ENV_EXAMPLE" ]]; then
    erro "Modelo de configuração não encontrado: $ENV_EXAMPLE"
    exit 1
  fi

  if [[ ! -f "$RESTORE_SRC" ]]; then
    warn "Script de restauração não encontrado: $RESTORE_SRC (será ignorado)."
  fi

  if [[ "$(docker inspect -f '{{.State.Running}}' coolify-db 2>/dev/null || true)" != "true" ]]; then
    warn "O container coolify-db não está rodando; o backup só funcionará depois que o Coolify subir."
  else
    ok "coolify-db em execução."
  fi
}

install_dependencies() {
  if ! command -v apt-get >/dev/null 2>&1; then
    warn "apt-get não encontrado; pule a instalação de dependências com --skip-deps."
    return 0
  fi

  local -a pkgs=()
  command -v aws >/dev/null 2>&1      || pkgs+=(awscli)
  command -v openssl >/dev/null 2>&1  || pkgs+=(openssl)
  command -v flock >/dev/null 2>&1    || pkgs+=(util-linux)
  command -v gzip >/dev/null 2>&1     || pkgs+=(gzip)
  command -v tar >/dev/null 2>&1      || pkgs+=(tar)
  command -v sha256sum >/dev/null 2>&1 || pkgs+=(coreutils)
  command -v logrotate >/dev/null 2>&1 || pkgs+=(logrotate)
  command -v crontab >/dev/null 2>&1  || pkgs+=(cron)

  if ((${#pkgs[@]} == 0)); then
    ok "Dependências já instaladas."
    return 0
  fi

  info "Instalando dependências: ${pkgs[*]}"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null
  apt-get install -y --no-install-recommends "${pkgs[@]}"

  if ! command -v aws >/dev/null 2>&1; then
    warn "AWS CLI não disponível no apt. Instale o AWS CLI v2 manualmente."
  fi
}

env_get() {
  local chave="$1" linha valor
  linha="$(grep -E "^${chave}=" "$CONFIG_FILE" 2>/dev/null | tail -n 1 || true)"
  [[ -n "$linha" ]] || return 1
  valor="${linha#*=}"
  valor="${valor%$'\r'}"
  if [[ "$valor" == \"*\" && "$valor" == *\" ]]; then
    valor="${valor:1:${#valor}-2}"
  elif [[ "$valor" == \'*\' ]]; then
    valor="${valor:1:${#valor}-2}"
  fi
  printf '%s' "$valor"
}

set_env_value() {
  local chave="$1" valor="$2" tmp encontrado=0 linha
  tmp="$(mktemp)"
  while IFS= read -r linha || [[ -n "$linha" ]]; do
    if [[ "$linha" =~ ^${chave}= ]]; then
      printf '%s="%s"\n' "$chave" "$valor"
      encontrado=1
    else
      printf '%s\n' "$linha"
    fi
  done < "$CONFIG_FILE" > "$tmp"

  if (( encontrado == 0 )); then
    printf '%s="%s"\n' "$chave" "$valor" >> "$tmp"
  fi

  cat "$tmp" > "$CONFIG_FILE"
  rm -f "$tmp"
}

install_backup_script() {
  mkdir -p "$(dirname "$DEST_SCRIPT")"
  install -m 700 "$BACKUP_SRC" "$DEST_SCRIPT"
  ok "Script instalado: $DEST_SCRIPT"
}

install_restore_script() {
  if [[ ! -f "$RESTORE_SRC" ]]; then
    warn "Script de restauração ausente; instale-o manualmente em $DEST_RESTORE."
    return 0
  fi
  mkdir -p "$(dirname "$DEST_RESTORE")"
  install -m 700 "$RESTORE_SRC" "$DEST_RESTORE"
  ok "Script de restauração instalado: $DEST_RESTORE"
}

install_config() {
  mkdir -p "$(dirname "$CONFIG_FILE")"
  if [[ -f "$CONFIG_FILE" && "$FORCE" -ne 1 ]]; then
    ok "Configuração existente preservada: $CONFIG_FILE"
  else
    install -m 600 "$ENV_EXAMPLE" "$CONFIG_FILE"
    ok "Configuração criada: $CONFIG_FILE"
  fi

  local -a obrigatorios=(R2_BUCKET R2_ENDPOINT AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY)
  local -a faltando=()
  local chave valor

  for chave in "${obrigatorios[@]}"; do
    valor="$(env_get "$chave" || true)"
    if [[ -z "$valor" || "$valor" == *"<"*">"* ]]; then
      faltando+=("$chave")
    fi
  done

  if ((${#faltando[@]} == 0)); then
    ok "Campos obrigatórios do R2 preenchidos."
    return 0
  fi

  if (( ASSUME_YES )) || [[ ! -t 0 ]]; then
    warn "Faltam campos em $CONFIG_FILE: ${faltando[*]}"
    warn "Edite o arquivo antes de confiar no cron: sudo editor $CONFIG_FILE"
    return 0
  fi

  info "Preencha os dados do Cloudflare R2 (Enter mantém o valor atual)."
  for chave in "${faltando[@]}"; do
    local resp
    read -r -p "  $chave: " resp
    if [[ -n "$resp" ]]; then
      set_env_value "$chave" "$resp"
    fi
  done

  faltando=()
  for chave in "${obrigatorios[@]}"; do
    valor="$(env_get "$chave" || true)"
    if [[ -z "$valor" || "$valor" == *"<"*">"* ]]; then
      faltando+=("$chave")
    fi
  done
  if ((${#faltando[@]} > 0)); then
    warn "Ainda faltam campos em $CONFIG_FILE: ${faltando[*]}"
    warn "Edite o arquivo antes de confiar no cron: sudo editor $CONFIG_FILE"
  else
    ok "Configuração do R2 preenchida."
  fi
}

install_passphrase() {
  local caminho
  caminho="$(env_get PASSPHRASE_FILE || true)"
  if [[ -n "$caminho" ]]; then
    PASSPHRASE_FILE="$caminho"
  fi
  mkdir -p "$(dirname "$PASSPHRASE_FILE")"

  if [[ -s "$PASSPHRASE_FILE" ]]; then
    ok "Passphrase existente preservada: $PASSPHRASE_FILE"
    return 0
  fi

  umask 077
  openssl rand -base64 48 > "$PASSPHRASE_FILE"
  chmod 600 "$PASSPHRASE_FILE"
  ok "Passphrase gerada: $PASSPHRASE_FILE"
  warn "Copie a passphrase para um gerenciador de senhas FORA deste servidor."
  warn "Sem ela os backups criptografados NÃO podem ser restaurados."
}

log_group() {
  if getent group adm >/dev/null 2>&1; then
    printf 'adm'
  else
    printf 'root'
  fi
}

create_log_file() {
  local grupo
  grupo="$(log_group)"
  if [[ ! -e "$LOG_FILE" ]]; then
    install -m 640 -o root -g "$grupo" /dev/null "$LOG_FILE"
    ok "Log criado: $LOG_FILE"
  else
    chmod 640 "$LOG_FILE" 2>/dev/null || true
    chown root:"$grupo" "$LOG_FILE" 2>/dev/null || true
    ok "Log existente preservado: $LOG_FILE"
  fi
}

install_logrotate() {
  local grupo
  grupo="$(log_group)"

  cat > "$LOGROTATE_FILE" <<EOF
# Rotacao do log do backup do Coolify (gerado por instala-backup-instancia.sh)
$LOG_FILE {
    weekly
    rotate $LOGROTATE_ROTATE
    compress
    missingok
    notifempty
    create 0640 root $grupo
}
EOF
  chmod 644 "$LOGROTATE_FILE"
  ok "Logrotate configurado: $LOGROTATE_FILE"

  if command -v logrotate >/dev/null 2>&1; then
    if logrotate -d "$LOGROTATE_FILE" >/dev/null 2>&1; then
      ok "Configuração do logrotate validada."
    else
      warn "logrotate reportou um problema; confira: sudo logrotate -d $LOGROTATE_FILE"
    fi
  else
    warn "logrotate não encontrado; instale com: sudo apt install -y logrotate"
  fi
}

install_cron() {
  mkdir -p "$(dirname "$CRON_FILE")"
  cat > "$CRON_FILE" <<EOF
# Backup do plano de controle do Coolify (gerado por instala-backup-instancia.sh)
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
$CRON_SCHEDULE $CRON_USER flock -n $LOCK_FILE $DEST_SCRIPT >> $LOG_FILE 2>&1
EOF
  chmod 644 "$CRON_FILE"
  chown root:root "$CRON_FILE" 2>/dev/null || true
  ok "Cron configurado: $CRON_FILE ($CRON_SCHEDULE)"

  if ! systemctl is-active --quiet cron 2>/dev/null && \
     ! systemctl is-active --quiet crond 2>/dev/null; then
    warn "O serviço cron parece inativo; verifique: systemctl status cron"
  fi
}

maybe_run_test() {
  local rodar=0 resp

  if (( RUN_TEST )); then
    rodar=1
  elif (( ! ASSUME_YES )) && [[ -t 0 ]]; then
    printf '%b?%b Rodar um backup de teste agora (envia ao R2)? (s/N): ' "$COR_AMARELA" "$COR_RESET"
    read -r resp
    if [[ "$resp" =~ ^[Ss]$ ]]; then
      rodar=1
    fi
  fi

  (( rodar )) || return 0

  info "Executando backup de teste..."
  if flock -n "$LOCK_FILE" "$DEST_SCRIPT"; then
    ok "Backup de teste concluído."
  else
    erro "Backup de teste falhou. Veja o log: $LOG_FILE"
    return 1
  fi
}

print_summary() {
  printf '\n'
  ok "=== Instalação concluída ==="
  printf '  Script:     %s\n' "$DEST_SCRIPT"
  if [[ -f "$DEST_RESTORE" ]]; then
    printf '  Restore:    %s\n' "$DEST_RESTORE"
  fi
  printf '  Config:     %s\n' "$CONFIG_FILE"
  printf '  Passphrase: %s\n' "$PASSPHRASE_FILE"
  printf '  Cron:       %s (%s)\n' "$CRON_FILE" "$CRON_SCHEDULE"
  if (( INSTALL_LOGROTATE )); then
    printf '  Logrotate:  %s\n' "$LOGROTATE_FILE"
  fi
  printf '  Log:        %s\n' "$LOG_FILE"
  printf '\n'
  info "Teste manual: sudo flock -n $LOCK_FILE $DEST_SCRIPT"
  info "Restaurar:    sudo $DEST_RESTORE --help"
  info "Acompanhar:   sudo tail -f $LOG_FILE"
  if (( INSTALL_LOGROTATE )); then
    info "Rotação:      sudo logrotate -d $LOGROTATE_FILE (simulação)"
  fi
  warn "Retenção no R2: crie a regra de lifecycle no painel da Cloudflare (prefixo R2_PREFIX)."
  warn "Guarde a passphrase FORA deste servidor; sem ela não há restore."
}

main() {
  local test_failed=0

  parse_args "$@"

  if (( SHOW_HELP )); then
    usage
    exit 0
  fi

  require_root

  check_environment

  if ! confirm "Instalar/atualizar o backup do Coolify"; then
    warn "Cancelado."
    exit 0
  fi

  if (( INSTALL_DEPS )); then
    install_dependencies
  fi

  install_backup_script
  install_restore_script
  install_config
  install_passphrase
  create_log_file

  if (( INSTALL_LOGROTATE )); then
    install_logrotate
  fi

  if (( INSTALL_CRON )); then
    install_cron
  fi

  if ! maybe_run_test; then
    test_failed=1
  fi

  print_summary

  if (( test_failed )); then
    erro "O backup de teste falhou; a instalação foi concluída, mas revise a configuração."
    exit 1
  fi
}

main "$@"
