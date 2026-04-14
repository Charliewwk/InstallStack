#!/bin/bash
set -euo pipefail

USER_NAME="ENTER YOUR USERNAME HERE"
SOURCE_ENV="/home/$USER_NAME/.env.stack"
TARGET_ENV="/srv/.env"

if [ ! -f "$SOURCE_ENV" ]; then
  echo "❌ No existe $SOURCE_ENV"
  exit 1
fi

sudo mkdir -p /srv
sudo cp "$SOURCE_ENV" "$TARGET_ENV"
sudo chown "$USER_NAME:$USER_NAME" "$TARGET_ENV"
sudo chmod 600 "$TARGET_ENV"
sudo sed -i 's/\r$//' "$TARGET_ENV"

set -a
source "$TARGET_ENV"
set +a

if ! systemctl is-active --quiet docker; then
  echo "🐳 Docker no está activo. Iniciándolo..."
  sudo systemctl start docker
fi

cd "$BASE_DIR"

echo "🧪 Validando docker-compose.yml..."
docker compose config >/dev/null

echo "🏗️ Construyendo imagen custom de Odoo..."
docker compose build odoo

echo "⬆️ Levantando stack..."
docker compose up -d

echo "📋 Estado de servicios:"
docker compose ps

echo ""
echo "🌐 URLs:"
echo "   Odoo:       https://${ODOO_HOST}"
echo "   OnlyOffice: https://${DOCS_HOST}"
echo "   OpenClaw:   https://${CLAW_HOST}"
echo "   Ollama API: http://127.0.0.1:${OLLAMA_PORT}"
echo ""
echo "ℹ️ Si todavía no bajaste el modelo local:"
echo "   docker compose exec ollama ollama pull ${OLLAMA_MODEL}"
