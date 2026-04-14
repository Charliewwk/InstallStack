#!/bin/bash
set -euo pipefail

HOME_DIR="/home/$LINUX_USER"

SOURCE_ENV="$HOME_DIR/.env.stack"
TARGET_ENV="/srv/.env"

if [ ! -f "$SOURCE_ENV" ]; then
  echo "❌ No existe $SOURCE_ENV"
  exit 1
fi

sudo mkdir -p /srv
sudo cp "$SOURCE_ENV" "$TARGET_ENV"
sudo chown "$LINUX_USER:$LINUX_GROUP" "$TARGET_ENV"
sudo chmod 600 "$TARGET_ENV"
sudo sed -i 's/\r$//' "$TARGET_ENV"

set -a
source "$TARGET_ENV"
set +a

echo "🕒 Configurando zona horaria del sistema: $TZ"
sudo timedatectl set-timezone "$TZ"

echo "📦 Removiendo paquetes Docker conflictivos"
sudo apt-get update
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  sudo apt-get remove -y "$pkg" 2>/dev/null || true
done

echo "📦 Instalando Docker desde repo oficial"
sudo install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
fi
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

sudo apt-get update
sudo apt-get install -y \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
  git curl wget unzip build-essential jq \
  python3 python3-pip python3-venv python3-jwt \
  ca-certificates gnupg lsb-release \
  tesseract-ocr poppler-utils ffmpeg

echo "🐳 Habilitando Docker"
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker "LINUX_USER" || true

echo "🔎 Verificando versiones"
sudo docker version
sudo docker compose version

echo "📁 Creando estructura"
sudo mkdir -p "$ODOO_DIR/config" "$ODOO_DIR/extra-addons" "$ODOO_DIR/logs" "$ODOO_DIR/odoo-data"
sudo mkdir -p "$NGINX_DIR/ssl" "$NGINX_DIR/logs"
sudo mkdir -p "$POSTGRES_DIR/postgresql-data"
sudo mkdir -p "$ONLYOFFICE_DIR/data" "$ONLYOFFICE_DIR/logs" "$ONLYOFFICE_DIR/lib" "$ONLYOFFICE_DIR/db" "$ONLYOFFICE_DIR/fonts"
sudo mkdir -p "$OPENCLAW_DIR/config" "$OPENCLAW_DIR/data" "$OPENCLAW_DIR/logs" "$OPENCLAW_DIR/workspace"
sudo mkdir -p "$OLLAMA_DIR"
sudo mkdir -p "$BACKUPS_DIR"

echo "📋 Generando docker-compose.yml"
sudo tee "$BASE_DIR/docker-compose.yml" > /dev/null <<'COMPOSEEOF'
services:
  db:
    image: postgres:15
    container_name: postgres15
    command: >
      postgres
      -c timezone=${TZ}
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      TZ: ${TZ}
    volumes:
      - ${POSTGRES_DIR}/postgresql-data:/var/lib/postgresql/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    restart: always
    networks:
      - backend_net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5

  odoo:
    build:
      context: ${ODOO_DIR}
      dockerfile: Dockerfile
    image: odoo:19.0-custom
    container_name: odoo
    depends_on:
      db:
        condition: service_healthy
    environment:
      HOST: ${ODOO_DB_HOST}
      USER: ${ODOO_DB_USER}
      PASSWORD: ${ODOO_DB_PASSWORD}
      TZ: ${TZ}
    volumes:
      - ${ODOO_DIR}/extra-addons:/mnt/extra-addons
      - ${ODOO_DIR}/config/odoo.conf:/etc/odoo/odoo.conf:ro
      - ${ODOO_DIR}/logs:/var/log/odoo
      - ${ODOO_DIR}/odoo-data:/var/lib/odoo
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    restart: always
    networks:
      - backend_net

  nginx:
    image: nginx:latest
    container_name: nginx_proxy
    depends_on:
      - odoo
      - onlyoffice
      - openclaw
    environment:
      TZ: ${TZ}
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ${NGINX_DIR}/nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - ${NGINX_DIR}/ssl:/etc/nginx/ssl:ro
      - ${NGINX_DIR}/logs:/var/log/nginx
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    restart: always
    networks:
      - backend_net
        - ${ODOO_HOST}
        - ${DOCS_HOST}
        - ${CLAW_HOST}
        
  onlyoffice:
    image: onlyoffice/documentserver:latest
    container_name: onlyoffice_docs
    environment:
      TZ: ${TZ}
      JWT_ENABLED: "${ONLYOFFICE_JWT_ENABLED}"
      JWT_SECRET: ${ONLYOFFICE_JWT_SECRET}
      JWT_HEADER: ${ONLYOFFICE_JWT_HEADER}
      USE_UNAUTHORIZED_STORAGE: "${ONLYOFFICE_USE_UNAUTHORIZED_STORAGE}"
    volumes:
      - ${ONLYOFFICE_DIR}/data:/var/www/onlyoffice/Data
      - ${ONLYOFFICE_DIR}/logs:/var/log/onlyoffice
      - ${ONLYOFFICE_DIR}/lib:/var/lib/onlyoffice
      - ${ONLYOFFICE_DIR}/db:/var/lib/postgresql
      - ${ONLYOFFICE_DIR}/fonts:/usr/share/fonts/truetype/custom
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    restart: always
    networks:
      - backend_net

  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    environment:
      TZ: ${TZ}
    ports:
      - "127.0.0.1:${OLLAMA_PORT}:11434"
    volumes:
      - ${OLLAMA_DIR}:/root/.ollama
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    restart: always
    networks:
      - backend_net

  openclaw:
    image: ghcr.io/openclaw/openclaw:latest
    container_name: openclaw
    environment:
      HOME: /home/node
      TERM: xterm-256color
      TZ: ${TZ}
      OPENCLAW_GATEWAY_TOKEN: ${OPENCLAW_GATEWAY_TOKEN}
      TELEGRAM_BOT_TOKEN: ${TELEGRAM_BOT_TOKEN}
    volumes:
      - ${OPENCLAW_DIR}/config:/home/node/.openclaw
      - ${OPENCLAW_DIR}/workspace:/home/node/.openclaw/workspace
      - ${OPENCLAW_DIR}/data:/srv/openclaw/data
      - ${OPENCLAW_DIR}/logs:/srv/openclaw/logs
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    command:
      [
        "node",
        "dist/index.js",
        "gateway",
        "--bind",
        "${OPENCLAW_BIND}",
        "--port",
        "${OPENCLAW_PORT}"
      ]
    init: true
    restart: unless-stopped
    ports:
      - "127.0.0.1:${OPENCLAW_PORT}:${OPENCLAW_PORT}"
    networks:
      - backend_net

networks:
  backend_net:
    driver: bridge
COMPOSEEOF

echo "📋 Generando odoo.conf"
sudo tee "$ODOO_DIR/config/odoo.conf" > /dev/null <<ODOOEOF
[options]
admin_passwd = ${ODOO_ADMIN_PASSWORD}

db_host = ${ODOO_DB_HOST}
db_port = ${ODOO_DB_PORT}
db_user = ${ODOO_DB_USER}
db_password = ${ODOO_DB_PASSWORD}

addons_path = /usr/lib/python3/dist-packages/odoo/addons,/mnt/extra-addons
data_dir = /var/lib/odoo

log_level = info
proxy_mode = True
gevent_port = 8072
http_interface = 0.0.0.0
dbfilter = ${ODOO_DBFILTER}

workers = ${ODOO_WORKERS}
max_cron_threads = ${ODOO_MAX_CRON_THREADS}
limit_memory_hard = ${ODOO_LIMIT_MEMORY_HARD}
limit_memory_soft = ${ODOO_LIMIT_MEMORY_SOFT}
limit_request = ${ODOO_LIMIT_REQUEST}
limit_time_cpu = ${ODOO_LIMIT_TIME_CPU}
limit_time_real = ${ODOO_LIMIT_TIME_REAL}
ODOOEOF

echo "📋 Generando openssl-san.cnf"
sudo tee "$NGINX_DIR/ssl/openssl-san.cnf" > /dev/null <<SSLEOF
[req]
default_bits = 4096
prompt = no
default_md = sha256
x509_extensions = v3_req
distinguished_name = dn

[dn]
C = ${SSL_COUNTRY}
ST = ${SSL_STATE}
L = ${SSL_CITY}
O = ${SSL_ORG}
OU = ${SSL_UNIT}
CN = ${SSL_COMMON_NAME}

[v3_req]
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${ODOO_HOST}
DNS.2 = ${DOCS_HOST}
DNS.3 = ${CLAW_HOST}
SSLEOF

echo "🔐 Generando certificado autofirmado"
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$NGINX_DIR/ssl/odoo.key" \
  -out "$NGINX_DIR/ssl/odoo.crt" \
  -config "$NGINX_DIR/ssl/openssl-san.cnf"

echo "📋 Copiando CA local al contexto de build de Odoo"
sudo cp "$NGINX_DIR/ssl/odoo.crt" "$ODOO_DIR/odoo-local-ca.crt"

echo "📋 Generando Dockerfile de Odoo"
sudo tee "$ODOO_DIR/Dockerfile" > /dev/null <<'DOCKEREOF'
FROM odoo:19.0

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3-jwt ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY odoo-local-ca.crt /usr/local/share/ca-certificates/odoo-local-ca.crt
RUN update-ca-certificates

USER odoo
DOCKEREOF

echo "📋 Generando nginx.conf"
sudo tee "$NGINX_DIR/nginx.conf" > /dev/null <<NGINXEOF
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

upstream odoo_backend {
    server odoo:8069;
}

upstream odoo_chat {
    server odoo:8072;
}

upstream onlyoffice_docs {
    server onlyoffice:80;
}

upstream openclaw_ui {
    server openclaw:18789;
}

server {
    listen 80;
    listen [::]:80;
    server_name ${ODOO_HOST};
    return 301 https://\$host\$request_uri;
}

server {
    listen 80;
    listen [::]:80;
    server_name ${DOCS_HOST};
    return 301 https://\$host\$request_uri;
}

server {
    listen 80;
    listen [::]:80;
    server_name ${CLAW_HOST};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${ODOO_HOST};

    ssl_certificate     /etc/nginx/ssl/odoo.crt;
    ssl_certificate_key /etc/nginx/ssl/odoo.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;

    access_log /var/log/nginx/odoo.access.log;
    error_log  /var/log/nginx/odoo.error.log warn;

    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;

    location /websocket {
        proxy_pass http://odoo_chat;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port 443;
    }

    location / {
        proxy_pass http://odoo_backend;
        proxy_http_version 1.1;
        proxy_redirect off;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port 443;
    }

    gzip_types text/css text/scss text/plain text/xml application/xml application/json application/javascript;
    gzip on;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${DOCS_HOST};

    ssl_certificate     /etc/nginx/ssl/odoo.crt;
    ssl_certificate_key /etc/nginx/ssl/odoo.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;

    access_log /var/log/nginx/onlyoffice.access.log;
    error_log  /var/log/nginx/onlyoffice.error.log warn;

    client_max_body_size 100M;

    proxy_read_timeout 3600s;
    proxy_connect_timeout 3600s;
    proxy_send_timeout 3600s;

    location ^~ /onlyoffice/file/ {
        proxy_pass http://odoo_backend;
        proxy_http_version 1.1;
        proxy_redirect off;
        proxy_set_header Host ${ODOO_HOST};
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port 443;
    }

    location / {
        proxy_pass http://onlyoffice_docs;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Host \$http_host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${CLAW_HOST};

    ssl_certificate     /etc/nginx/ssl/odoo.crt;
    ssl_certificate_key /etc/nginx/ssl/odoo.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;

    access_log /var/log/nginx/openclaw.access.log;
    error_log  /var/log/nginx/openclaw.error.log warn;

    proxy_read_timeout 3600s;
    proxy_connect_timeout 3600s;
    proxy_send_timeout 3600s;

    location / {
        proxy_pass http://openclaw_ui;
        proxy_http_version 1.1;
        proxy_redirect off;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port 443;
    }
}
NGINXEOF

echo "📋 Generando openclaw.json"
sudo tee "$OPENCLAW_DIR/config/openclaw.json" > /dev/null <<OPENCLAWEOF
{
  "gateway": {
    "mode": "local",
    "bind": "${OPENCLAW_BIND}",
    "controlUi": {
      "allowedOrigins": [
        "http://127.0.0.1:${OPENCLAW_PORT}",
        "http://localhost:${OPENCLAW_PORT}",
        "https://${CLAW_HOST}"
      ]
    }
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "${TELEGRAM_DM_POLICY}"
    }
  },
  "agents": {
    "defaults": {
      "workspace": "/home/node/.openclaw/workspace",
      "model": {
        "primary": "${OPENCLAW_DEFAULT_MODEL}",
        "fallbacks": [
          "${OPENCLAW_FALLBACK_MODEL}"
        ]
      }
    }
  },
  "models": {
    "providers": {
      "ollama": {
        "apiKey": "ollama-local",
        "baseUrl": "${OLLAMA_BASE_URL}",
        "api": "${OLLAMA_PROVIDER_API}",
        "models": [
          {
            "id": "${OLLAMA_MODEL}",
            "name": "${OLLAMA_MODEL}",
            "input": ["text"],
            "cost": {
              "input": 0,
              "output": 0,
              "cacheRead": 0,
              "cacheWrite": 0
            },
            "contextWindow": ${OLLAMA_CONTEXT_WINDOW},
            "maxTokens": ${OLLAMA_MAX_TOKENS}
          }
        ]
      }
    }
  }
}
OPENCLAWEOF

echo "👤 Aplicando ownership"
sudo chown -R "$LINUX_USER:$LINUX_GROUP" "$BASE_DIR"
sudo chown -R 999:999 "$POSTGRES_DIR/postgresql-data"

echo "🔒 Aplicando permisos"
sudo chmod -R 755 "$BASE_DIR"

sudo chmod -R 775 "$ODOO_DIR/extra-addons"
sudo chmod -R 775 "$ODOO_DIR/logs"
sudo chmod -R 777 "$ODOO_DIR/odoo-data"
sudo chmod 644 "$ODOO_DIR/config/odoo.conf"
sudo chmod 644 "$ODOO_DIR/Dockerfile"
sudo chmod 644 "$ODOO_DIR/odoo-local-ca.crt"

sudo chmod -R 775 "$NGINX_DIR/logs"
sudo chmod -R 755 "$NGINX_DIR/ssl"
sudo chmod 644 "$NGINX_DIR/nginx.conf"
sudo chmod 644 "$NGINX_DIR/ssl/odoo.crt"
sudo chmod 600 "$NGINX_DIR/ssl/odoo.key"
sudo chmod 644 "$NGINX_DIR/ssl/openssl-san.cnf"

sudo chmod -R 700 "$POSTGRES_DIR/postgresql-data"

sudo chmod -R 775 "$ONLYOFFICE_DIR/data"
sudo chmod -R 775 "$ONLYOFFICE_DIR/logs"
sudo chmod -R 775 "$ONLYOFFICE_DIR/lib"
sudo chmod -R 775 "$ONLYOFFICE_DIR/db"
sudo chmod -R 775 "$ONLYOFFICE_DIR/fonts"

sudo chmod -R 775 "$OPENCLAW_DIR/config"
sudo chmod -R 775 "$OPENCLAW_DIR/data"
sudo chmod -R 775 "$OPENCLAW_DIR/logs"
sudo chmod -R 775 "$OPENCLAW_DIR/workspace"

sudo chmod -R 775 "$OLLAMA_DIR"

sudo chmod -R 775 "$BACKUPS_DIR"
find "$BACKUPS_DIR" -type f -exec chmod 644 {} \; 2>/dev/null || true

sudo chmod 644 "$BASE_DIR/docker-compose.yml"
sudo chmod 600 "$TARGET_ENV"

echo "✅ Deploy listo"
echo "ℹ️ No levanta el stack. Ejecutá: ~/up.sh"
echo "ℹ️ Agregá a /etc/hosts en cada cliente:"
echo "   <IP_DE_TU_SERVIDOR> ${ODOO_HOST} ${DOCS_HOST} ${CLAW_HOST}"
echo "ℹ️ Si recién agregaste el usuario al grupo docker, cerrá sesión y volvé a entrar."
