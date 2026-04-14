#!/bin/bash
set -euo pipefail

TARGET_ENV="/srv/.env"

if [ ! -f "$TARGET_ENV" ]; then
  echo "❌ No existe $TARGET_ENV"
  exit 1
fi

set -a
source "$TARGET_ENV"
set +a

cd "$BASE_DIR"

if [ $# -eq 0 ]; then
  docker compose logs -f --tail=200
else
  docker compose logs -f --tail=200 "$1"
fi
