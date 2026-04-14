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
docker compose down
docker compose ps
