#!/usr/bin/env bash
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

usage() {
  cat <<'EOF'
Uso: ./destroy-coolify.sh [opções]

Remove o Coolify self-hosted DESTA máquina.
Execute este script dentro do servidor (via console/terminal do provedor).

Opções:
  -y, --yes         Não pedir confirmação
  --with-images     Remover também as imagens do Coolify
  --purge-docker    Remover Docker, todos os containers e volumes (perigoso)
  -h, --help        Mostrar esta ajuda

Padrão: remove containers, volumes, rede e /data/coolify.
Não faz backup de /data/coolify/source/.env.
EOF
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

collect_state() {
  if command -v docker >/dev/null 2>&1; then
    printf 'CONTAINERS=%s\n' "$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -E '^(coolify|coolify-db|coolify-redis|coolify-realtime|coolify-sentinel|coolify-proxy)(_|$)' | paste -sd, - || true)"
    printf 'VOLUMES=%s\n' "$(docker volume ls -q 2>/dev/null | grep -E '^(coolify-db|coolify-redis)$' | paste -sd, - || true)"
    printf 'NETWORK=%s\n' "$(docker network ls --format '{{.Name}}' 2>/dev/null | grep -x 'coolify' | paste -sd, - || true)"
    printf 'IMAGES=%s\n' "$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -E 'coollabsio' | paste -sd, - || true)"
    printf 'SWARM=%s\n' "$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || printf 'unknown')"
  else
    printf 'CONTAINERS=\nVOLUMES=\nNETWORK=\nIMAGES=\nSWARM=unknown\n'
  fi
  if [[ -d /data/coolify ]]; then
    printf 'DATADIR=1\n'
  else
    printf 'DATADIR=0\n'
  fi
  if command -v cloudflared >/dev/null 2>&1; then
    printf 'CLOUDFLARED=1\n'
  else
    printf 'CLOUDFLARED=0\n'
  fi
}

remove_containers() {
  local c
  for c in coolify coolify-db coolify-redis coolify-sentinel coolify-realtime; do
    if [[ ",${CONTAINERS}," == *",${c},"* ]]; then
      docker rm -f "$c" >/dev/null 2>&1 || true
    fi
  done
  if [[ ",${CONTAINERS}," == *",coolify-proxy,"* ]]; then
    if [[ "$SWARM" == "active" ]]; then
      docker stack rm coolify-proxy >/dev/null 2>&1 || true
    else
      docker rm -f coolify-proxy >/dev/null 2>&1 || true
    fi
  fi
}

remove_images() {
  docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -E 'coollabsio' | while IFS= read -r img; do
    docker rmi -f "$img" >/dev/null 2>&1 || true
  done
}

network_endpoints() {
  docker network inspect coolify --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null | xargs -r || true
}

purge_docker() {
  info "Removendo todos os containers, volumes e redes..."
  if command -v docker >/dev/null 2>&1; then
    docker ps -aq | xargs -r docker rm -f >/dev/null 2>&1 || true
    docker volume ls -q | xargs -r docker volume rm >/dev/null 2>&1 || true
    docker network ls --format '{{.Name}}' | grep -vE '^(bridge|host|none)$' | xargs -r docker network rm >/dev/null 2>&1 || true
  fi
  info "Removendo Docker e containerd..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker.io docker-compose >/dev/null 2>&1 || true
  apt-get autoremove -y >/dev/null 2>&1 || true
  rm -rf /var/lib/docker /var/lib/containerd /etc/docker
}

ORIGINAL_ARGS=("$@")
ASSUME_YES=0
WITH_IMAGES=0
PURGE_DOCKER=0
SHOW_HELP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)
      ASSUME_YES=1; shift ;;
    --with-images)
      WITH_IMAGES=1; shift ;;
    --purge-docker)
      PURGE_DOCKER=1; shift ;;
    -h|--help)
      SHOW_HELP=1; shift ;;
    *)
      erro "Opção inválida: $1"
      usage
      exit 1 ;;
  esac
done

if (( SHOW_HELP )); then
  usage
  exit 0
fi

if [[ "$EUID" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    info "Elevando privilégios com sudo..."
    exec sudo -- bash "$0" "${ORIGINAL_ARGS[@]}"
  fi
  erro "Execute como root: sudo ./destroy-coolify.sh"
  exit 1
fi

STATE="$(collect_state)"

CONTAINERS=""
VOLUMES=""
NETWORK=""
IMAGES=""
SWARM="unknown"
DATADIR=0
CLOUDFLARED=0

while IFS='=' read -r chave valor; do
  case "$chave" in
    CONTAINERS) CONTAINERS="$valor" ;;
    VOLUMES) VOLUMES="$valor" ;;
    NETWORK) NETWORK="$valor" ;;
    IMAGES) IMAGES="$valor" ;;
    SWARM) SWARM="$valor" ;;
    DATADIR) DATADIR="$valor" ;;
    CLOUDFLARED) CLOUDFLARED="$valor" ;;
  esac
done <<< "$STATE"

HAS_WORK=0
if [[ -n "$CONTAINERS" || -n "$VOLUMES" || -n "$NETWORK" || "$DATADIR" == "1" ]]; then
  HAS_WORK=1
fi
if (( WITH_IMAGES )) && [[ -n "$IMAGES" ]]; then
  HAS_WORK=1
fi
if (( PURGE_DOCKER )); then
  HAS_WORK=1
fi

if (( HAS_WORK == 0 )); then
  ok "Coolify não encontrado nesta máquina. Nada a remover."
  exit 0
fi

info "Será removido:"
printf '  - Containers: %s\n' "${CONTAINERS:-<nenhum>}"
printf '  - Volumes:    %s\n' "${VOLUMES:-<nenhum>}"
printf '  - Rede:       %s\n' "${NETWORK:-<nenhum>}"
if [[ -n "$NETWORK" ]]; then
  NET_ENDPOINTS="$(network_endpoints)"
  if [[ -n "$NET_ENDPOINTS" ]]; then
    printf '                (containers conectados: %s)\n' "$NET_ENDPOINTS"
  fi
fi
printf '  - Diretório:  %s\n' "$([[ "$DATADIR" == "1" ]] && printf '/data/coolify' || printf '<inexistente>')"
if (( WITH_IMAGES )); then
  printf '  - Imagens:    %s\n' "${IMAGES:-<nenhuma>}"
fi
if (( PURGE_DOCKER )); then
  warn "ATENÇÃO: --purge-docker removerá TODOS os containers, volumes e o Docker."
fi

if ! confirm "Confirmar remoção do Coolify"; then
  warn "Cancelado."
  exit 0
fi

if (( PURGE_DOCKER )); then
  printf '%b?%b Digite "APAGAR TUDO" para confirmar a remoção do Docker: ' "$COR_VERMELHA" "$COR_RESET"
  read -r CONFIRMACAO
  if [[ "$CONFIRMACAO" != "APAGAR TUDO" ]]; then
    erro "Confirmação incorreta. Cancelado."
    exit 1
  fi
fi

info "Removendo containers do Coolify..."
remove_containers

info "Removendo volumes..."
for v in coolify-db coolify-redis; do
  docker volume rm "$v" >/dev/null 2>&1 || true
done

if [[ -n "$NETWORK" ]]; then
  ENDPOINTS="$(network_endpoints)"
  if [[ -n "$ENDPOINTS" ]]; then
    warn "Containers ainda conectados à rede coolify: ${ENDPOINTS}"
    if (( PURGE_DOCKER )); then
      :
    elif (( ASSUME_YES )) || confirm "Desconectar esses containers da rede coolify para removê-la"; then
      printf '%s\n' "$ENDPOINTS" | xargs -r -n1 docker network disconnect -f coolify >/dev/null 2>&1 || true
    else
      warn "Rede coolify não será removida enquanto houver containers conectados."
    fi
  fi
  info "Removendo a rede coolify..."
  if ! NET_ERR="$(docker network rm coolify 2>&1)"; then
    warn "Não foi possível remover a rede coolify: ${NET_ERR}"
  fi
else
  info "Rede coolify não encontrada. Nada a remover."
fi

info "Removendo /data/coolify..."
rm -rf /data/coolify

if (( WITH_IMAGES )); then
  info "Removendo imagens do Coolify..."
  remove_images
fi

if (( PURGE_DOCKER )); then
  purge_docker
fi

info "Verificando..."
STATE="$(collect_state)"
if printf '%s\n' "$STATE" | grep -qE '^(CONTAINERS|VOLUMES|NETWORK)=.+'; then
  warn "Ainda existem recursos do Coolify:"
  printf '%s\n' "$STATE" | grep -E '^(CONTAINERS|VOLUMES|NETWORK)='
  if printf '%s\n' "$STATE" | grep -q '^NETWORK=coolify'; then
    ENDPOINTS="$(network_endpoints)"
    if [[ -n "$ENDPOINTS" ]]; then
      warn "Containers que impedem a remoção da rede: ${ENDPOINTS}"
    fi
  fi
else
  ok "Containers, volumes e rede do Coolify removidos."
fi
if printf '%s\n' "$STATE" | grep -q '^DATADIR=1'; then
  warn "/data/coolify ainda existe."
else
  ok "/data/coolify removido."
fi

if [[ "$CLOUDFLARED" == "1" ]]; then
  warn "cloudflared detectado: remova ou reaponte o hostname público no painel da Cloudflare."
fi

ok "Concluído."
