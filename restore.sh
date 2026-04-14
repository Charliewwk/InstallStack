#!/bin/bash
set -euo pipefail

ARCHIVE="${1:-}"

if [ -z "$ARCHIVE" ]; then
  echo "Uso: $0 /ruta/al/backup.tar.gz"
  exit 1
fi

if [ ! -f "$ARCHIVE" ]; then
  echo "❌ No existe $ARCHIVE"
  exit 1
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "📦 Extrayendo backup..."
tar -xzf "$ARCHIVE" -C "$TMPDIR"
BACKUP_ROOT=$(find "$TMPDIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)

if [ -z "$BACKUP_ROOT" ]; then
  echo "❌ No se pudo identificar el contenido del backup"
  exit 1
fi

sudo mkdir -p /srv
sudo cp "$BACKUP_ROOT/.env" /srv/.env
sudo sed -i 's/\r$//' /srv/.env

set -a
source /srv/.env
set +a

cd "$BASE_DIR"

echo "🛑 Bajando stack actual si existe..."
docker compose down --volumes --remove-orphans 2>/dev/null || true

echo "🧹 Limpiando directorios actuales..."
sudo rm -rf "$ODOO_DIR" "$NGINX_DIR" "$POSTGRES_DIR" "$ONLYOFFICE_DIR" "$OPENCLAW_DIR" "$OLLAMA_DIR"

echo "📁 Restaurando directorios..."
sudo mkdir -p "$BASE_DIR"
sudo cp -a "$BACKUP_ROOT/odoo" "$ODOO_DIR"
sudo cp -a "$BACKUP_ROOT/nginx" "$NGINX_DIR"
sudo cp -a "$BACKUP_ROOT/onlyoffice" "$ONLYOFFICE_DIR"
sudo cp -a "$BACKUP_ROOT/openclaw" "$OPENCLAW_DIR"
sudo cp -a "$BACKUP_ROOT/ollama" "$OLLAMA_DIR"
sudo cp "$BACKUP_ROOT/docker-compose.yml" "$BASE_DIR/docker-compose.yml"

echo "👤 Restaurando ownership/permisos..."
sudo chown -R "${LINUX_USER}:${LINUX_GROUP}" "$BASE_DIR"
sudo mkdir -p "$POSTGRES_DIR/postgresql-data"
sudo chown -R 999:999 "$POSTGRES_DIR/postgresql-data"
sudo chmod -R 700 "$POSTGRES_DIR/postgresql-data"

echo "🐳 Iniciando solo PostgreSQL..."
docker compose up -d db

echo "⏳ Esperando PostgreSQL..."
for i in $(seq 1 60); do
  if docker compose exec -T db pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

echo "💾 Restaurando bases..."
cat "$BACKUP_ROOT/postgres_all.sql" | docker compose exec -T db psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}"

echo "🏗️ Reconstruyendo Odoo por el certificado local..."
docker compose build odoo

echo "⬆️ Levantando stack completo..."
docker compose up -d

echo "✅ Restore completo finalizado"
echo "🌐 URLs:"
echo "   Odoo:       https://${ODOO_HOST}"
echo "   OnlyOffice: https://${DOCS_HOST}"
echo "   OpenClaw:   https://${CLAW_HOST}"
