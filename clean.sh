#!/bin/bash
set -euo pipefail

MODE="${1:-}"
TARGET_ENV="/srv/.env"
SOURCE_ENV="/home/ENTER YOUR JWT SECRET HERE/.env.stack"

if [ -f "$TARGET_ENV" ]; then
  set -a
  source "$TARGET_ENV"
  set +a
elif [ -f "$SOURCE_ENV" ]; then
  set -a
  source "$SOURCE_ENV"
  set +a
else
  BASE_DIR="/srv"
fi

if [[ -z "$MODE" ]]; then
  echo "Uso: $0 --soft | --deep | --nuke"
  exit 1
fi

soft_cleanup() {
  cd "$BASE_DIR" 2>/dev/null || return 0
  docker compose down --volumes --remove-orphans 2>/dev/null || true
  docker rm -f postgres15 odoo nginx_proxy onlyoffice_docs openclaw ollama 2>/dev/null || true
  docker image rm odoo:19.0-custom 2>/dev/null || true
  docker system prune -a --volumes -f || true
  docker builder prune -a -f || true
}

deep_cleanup() {
  soft_cleanup || true
  sudo rm -rf "${BASE_DIR}/odoo" "${BASE_DIR}/nginx" "${BASE_DIR}/postgres" \
              "${BASE_DIR}/onlyoffice" "${BASE_DIR}/openclaw" "${BASE_DIR}/ollama" \
              "${BASE_DIR}/backups"
  sudo rm -f "${BASE_DIR}/docker-compose.yml" "${BASE_DIR}/.env"
}

nuke_cleanup() {
  soft_cleanup || true
  sudo systemctl stop docker || true
  sudo systemctl stop containerd || true
  sudo rm -rf /var/lib/docker /var/lib/containerd /run/docker /run/containerd
  sudo rm -rf "${BASE_DIR}/odoo" "${BASE_DIR}/nginx" "${BASE_DIR}/postgres" \
              "${BASE_DIR}/onlyoffice" "${BASE_DIR}/openclaw" "${BASE_DIR}/ollama" \
              "${BASE_DIR}/backups"
  sudo rm -f "${BASE_DIR}/docker-compose.yml" "${BASE_DIR}/.env"
  sudo systemctl start containerd || true
  sudo systemctl start docker || true
}

case "$MODE" in
  --soft) soft_cleanup ;;
  --deep) deep_cleanup ;;
  --nuke) nuke_cleanup ;;
  *)
    echo "Uso: $0 --soft | --deep | --nuke"
    exit 1
    ;;
esac

echo "✅ Limpieza finalizada"
