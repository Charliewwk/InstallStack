# 🚀 Deploy automático Odoo + Stack auxiliar

Script de aprovisionamiento y despliegue completo basado en Docker para un entorno productivo que incluye:
- Odoo 19 (custom build)
- PostgreSQL 15
- Nginx (reverse proxy + SSL)
- OnlyOffice Document Server
- OpenClaw (AI gateway)
- Ollama (modelos locales)

---

## 📦 Requisitos
- Ubuntu compatible (22.04+ recomendado)
- Usuario con permisos sudo
- Archivo de variables de entorno: `~/.env.stack`

---

## ⚙️ Variables requeridas
El script depende de múltiples variables definidas en:
~/.env.stack

Ejemplos:
- Sistema: `LINUX_USER`, `LINUX_GROUP`, `TZ`
- Odoo: `ODOO_DIR`, `ODOO_DB_*`, `ODOO_HOST`
- Nginx: `NGINX_DIR`
- PostgreSQL: `POSTGRES_*`
- OnlyOffice: `ONLYOFFICE_*`
- OpenClaw: `OPENCLAW_*`
- Ollama: `OLLAMA_*`
- SSL: `SSL_*`

## ▶️ Uso
Ejecutar:
```bash
chmod +x deploy.sh
./deploy.sh
```

## 🔧 Qué hace el script

1. Carga entorno
        •Copia .env.stack → /srv/.env
        •Exporta variables automáticamente
2. Configura sistema
        •Zona horaria
        •Limpieza de paquetes Docker previos
3. Instala dependencias
        •Docker + Compose (repo oficial)
        •Herramientas base (git, curl, python, etc.)
4. Provisiona estructura
        •Directorios para todos los servicios
        •Permisos y ownership
5. Genera configuración
        •docker-compose.yml
        •odoo.conf
        •nginx.conf
        •openclaw.json
        •Dockerfile custom de Odoo
6. SSL
        •Genera certificado autofirmado con SAN
7. Integraciones
        •OnlyOffice ↔ Odoo
        •OpenClaw ↔ Ollama
        •Reverse proxy multi-host

## 🐳 Servicios incluidos


| Servicio | Puerto | Descripción |
| :--- | :---: | ---: |
|Odoo | 8069 | ERP |
| PostgreSQL | 5432 | Base de datos |
| Nginx | 80/443 |Proxy + SSL |
| OnlyOffice | 80 | Edición documentos |
| OpenClaw | custom | Gateway IA |
| Ollama| 11434 | Modelos locales |

## 🚫 Importante
	•El script NO levanta el stack automáticamente

Ejecutar manualmente:
```bash
docker compose up -d
```
o wrapper:
```bash
~/up.sh
```

## 🌐 Hosts requeridos
Agregar en clientes:
<IP_SERVIDOR> odoo.local docs.local claw.local (usando valores reales de tus variables)

🔐 Seguridad
- Certificado SSL autofirmado (solo testing / interno)
- .env con permisos restrictivos (600)
- PostgreSQL aislado en red interna

⚠️ Consideraciones
- Requiere relogin si se agrega usuario a grupo docker
- No incluye backup automático (solo estructura)
- Pensado para entornos controlados o staging

🧩 Extensión
- Soporta:
        - Addons custom en /extra-addons
        - Integración con CI/CD
        - Reemplazo de SSL por Let’s Encrypt



