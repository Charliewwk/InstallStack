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

TIMESTAMP=$(date +%F_%H%M%S)
WORKDIR="${BACKUPS_DIR}/backup_${COMPOSE_PROJECT_NAME}_${TIMESTAMP}"
ARCHIVE="${BACKUPS_DIR}/backup_${COMPOSE_PROJECT_NAME}_${TIMESTAMP}.tar.gz"

mkdir -p "$WORKDIR"

cd "$BASE_DIR"

echo "💾 Exportando bases PostgreSQL..."
docker compose exec -T db pg_dumpall -U "${POSTGRES_USER}" > "${WORKDIR}/postgres_all.sql"

echo "💾 Copiando metadata..."
cp "$BASE_DIR/.env" "${WORKDIR}/.env"
cp "$BASE_DIR/docker-compose.yml" "${WORKDIR}/docker-compose.yml"

echo "💾 Copiando directorios..."
cp -a "$ODOO_DIR" "${WORKDIR}/odoo"
cp -a "$NGINX_DIR" "${WORKDIR}/nginx"
cp -a "$ONLYOFFICE_DIR" "${WORKDIR}/onlyoffice"
cp -a "$OPENCLAW_DIR" "${WORKDIR}/openclaw"
cp -a "$OLLAMA_DIR" "${WORKDIR}/ollama"

echo "🧾 Generando manifest..."
cat > "${WORKDIR}/manifest.txt" <<EOF
backup_created_at=$(date --iso-8601=seconds)
timezone=${TZ}
compose_project=${COMPOSE_PROJECT_NAME}
postgres_db=${POSTGRES_DB}
postgres_user=${POSTGRES_USER}
odoo_host=${ODOO_HOST}
docs_host=${DOCS_HOST}
claw_host=${CLAW_HOST}
ollama_model=${OLLAMA_MODEL}
EOF

echo "📦 Comprimiendo backup..."
tar -czf "$ARCHIVE" -C "$BACKUPS_DIR" "$(basename "$WORKDIR")"

echo "🧹 Limpiando staging..."
rm -rf "$WORKDIR"

echo "✅ Backup completo creado:"
echo "$ARCHIVE"
