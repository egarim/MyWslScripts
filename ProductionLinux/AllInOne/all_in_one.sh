#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="$(pwd)/setup.log"
: > "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

RED="\033[0;31m"; GRN="\033[0;32m"; YEL="\033[1;33m"; BLU="\033[0;34m"; NC="\033[0m"
say() { echo -e "${BLU}==>${NC} $*"; }
ok()  { echo -e "${GRN}[OK]${NC} $*"; }
warn(){ echo -e "${YEL}[WARN]${NC} $*"; }
err() { echo -e "${RED}[ERR]${NC} $*"; }

if [[ $EUID -ne 0 ]]; then err "Run as root (sudo)."; exit 1; fi

gen_pass () { tr -dc 'A-Za-z0-9!@#%^&*()-_=+' </dev/urandom | head -c 20; }

# --------------------- INPUTS ---------------------
say "Collecting settings (press Enter for defaults)."

PUBLIC_HOST_DEFAULT="$(hostname -f)"
read -r -p "Server public hostname [${PUBLIC_HOST_DEFAULT}]: " PUBLIC_HOST
PUBLIC_HOST="${PUBLIC_HOST:-$PUBLIC_HOST_DEFAULT}"

# TLS (Caddy / Let's Encrypt)
read -r -p "ACME email for TLS certificates (renewal notices) [admin@${PUBLIC_HOST}]: " ACME_EMAIL
ACME_EMAIL="${ACME_EMAIL:-admin@${PUBLIC_HOST}}"

read -r -p "Webmin domain (e.g., webmin.example.com) [webmin.${PUBLIC_HOST}]: " WEBMIN_DOMAIN
WEBMIN_DOMAIN="${WEBMIN_DOMAIN:-webmin.${PUBLIC_HOST}}"

read -r -p "Seq UI domain (e.g., seq.example.com) [seq.${PUBLIC_HOST}]: " SEQ_DOMAIN
SEQ_DOMAIN="${SEQ_DOMAIN:-seq.${PUBLIC_HOST}}"

read -r -p "Keycloak domain (e.g., sso.example.com) [sso.${PUBLIC_HOST}]: " KC_DOMAIN
KC_DOMAIN="${KC_DOMAIN:-sso.${PUBLIC_HOST}}"

# Webmin
read -r -p "Install Webmin? [Y/n]: " DO_WEBMIN; DO_WEBMIN="${DO_WEBMIN:-Y}"
read -r -p "Webmin port (internal) [10000]: " WEBMIN_PORT; WEBMIN_PORT="${WEBMIN_PORT:-10000}"

# Seq
read -r -p "Install Seq? [Y/n]: " DO_SEQ; DO_SEQ="${DO_SEQ:-Y}"
read -r -p "Seq UI port (internal host port) [5342]: " SEQ_HTTP_PORT; SEQ_HTTP_PORT="${SEQ_HTTP_PORT:-5342}"
read -r -p "Seq ingestion port (host) [5341]: " SEQ_INGEST_PORT; SEQ_INGEST_PORT="${SEQ_INGEST_PORT:-5341}"
read -r -p "Seq admin password (blank=auto): " SEQ_ADMIN_PASS; SEQ_ADMIN_PASS="${SEQ_ADMIN_PASS:-$(gen_pass)}"
read -r -p "Seq ingestion API key (blank=auto): " SEQ_INGEST_KEY; SEQ_INGEST_KEY="${SEQ_INGEST_KEY:-$(gen_pass)}"
read -r -p "Seq license key (optional, blank=skip): " SEQ_LICENSE; SEQ_LICENSE="${SEQ_LICENSE:-}"

# Keycloak
read -r -p "Install Keycloak? [Y/n]: " DO_KC; DO_KC="${DO_KC:-Y}"
read -r -p "Keycloak internal HTTP port (host) [8080]: " KC_HTTP_PORT; KC_HTTP_PORT="${KC_HTTP_PORT:-8080}"
read -r -p "Keycloak admin username [admin]: " KC_ADMIN; KC_ADMIN="${KC_ADMIN:-admin}"
read -r -p "Keycloak admin password (blank=auto): " KC_ADMIN_PASS; KC_ADMIN_PASS="${KC_ADMIN_PASS:-$(gen_pass)}"

read -r -p "Use PostgreSQL for Keycloak? [Y/n]: " USE_PG; USE_PG="${USE_PG:-Y}"
if [[ "${USE_PG,,}" == "y" ]]; then
  read -r -p "PostgreSQL version [16]: " PG_VER; PG_VER="${PG_VER:-16}"
  read -r -p "PostgreSQL DB for Keycloak [keycloak_prod]: " KC_DB; KC_DB="${KC_DB:-keycloak_prod}"
  read -r -p "PostgreSQL user for Keycloak [keycloak]: " KC_DB_USER; KC_DB_USER="${KC_DB_USER:-keycloak}"
  read -r -p "PostgreSQL password (blank=auto): " KC_DB_PASS; KC_DB_PASS="${KC_DB_PASS:-$(gen_pass)}"
  read -r -p "PostgreSQL host [localhost]: " PG_HOST; PG_HOST="${PG_HOST:-localhost}"
  read -r -p "PostgreSQL port [5432]: " PG_PORT; PG_PORT="${PG_PORT:-5432}"

  # Remote access controls
  read -r -p "CIDR allowed to reach PostgreSQL (e.g., 203.0.113.0/24 or 0.0.0.0/0) [0.0.0.0/0]: " PG_ALLOW_CIDR
  PG_ALLOW_CIDR="${PG_ALLOW_CIDR:-0.0.0.0/0}"
fi

say "Starting in 3 seconds…"; sleep 3

# --------------------- PREREQS ---------------------
apt-get update -y
apt-get install -y curl wget gnupg ca-certificates lsb-release ufw jq unzip

ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    say "Installing Docker…"
    apt-get remove -y docker docker-engine docker.io containerd runc || true
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    ok "Docker installed."
  fi
}

# --------------------- WEBMIN ---------------------
install_webmin() {
  say "Installing Webmin…"
  if ! apt-cache policy | grep -q 'download.webmin.com'; then
    wget -qO- http://www.webmin.com/jcameron-key.asc | gpg --dearmor -o /usr/share/keyrings/webmin.gpg
    echo "deb [signed-by=/usr/share/keyrings/webmin.gpg] http://download.webmin.com/download/repository sarge contrib" \
      > /etc/apt/sources.list.d/webmin.list
  fi
  apt-get update -y
  apt-get install -y webmin
  sed -i "s/^port=.*/port=$WEBMIN_PORT/" /etc/webmin/miniserv.conf
  sed -i "s/^ssl=.*/ssl=0/" /etc/webmin/miniserv.conf   # disable internal SSL; Caddy will handle TLS
  systemctl restart webmin || true
  ok "Webmin ready on http://127.0.0.1:${WEBMIN_PORT} (proxied via Caddy)"
}

# --------------------- SEQ ---------------------
install_seq() {
  ensure_docker
  say "Installing Seq (Docker)…"
  mkdir -p /opt/seq
  docker pull datalust/seq:latest
  docker rm -f seq >/dev/null 2>&1 || true

  ENV_FLAGS=(-e SEQ_FIRSTRUN_ADMINPASSWORD="$SEQ_ADMIN_PASS" -e SEQ_ACCEPT_EULA=Y)
  [[ -n "$SEQ_LICENSE" ]] && ENV_FLAGS+=(-e SEQ_LICENSE="$SEQ_LICENSE")

  # Map UI to SEQ_HTTP_PORT (host), ingestion exposed on SEQ_INGEST_PORT (host)
  docker run -d --name seq --restart unless-stopped \
    -p "${SEQ_HTTP_PORT}:80" \
    -p "${SEQ_INGEST_PORT}:5341" \
    -v /opt/seq:/data \
    "${ENV_FLAGS[@]}" \
    datalust/seq:latest

  sleep 5
  docker exec seq seqcli apikey create -t "IngestionKey" -s "http://localhost" -k "$SEQ_INGEST_KEY" >/dev/null 2>&1 || true

  # UFW: allow ingestion port (optionally lock later)
  ufw allow "${SEQ_INGEST_PORT}"/tcp || true
  ok "Seq UI on http://127.0.0.1:${SEQ_HTTP_PORT} (proxied via Caddy); ingestion on tcp/${SEQ_INGEST_PORT}"
}

# --------------------- POSTGRES ---------------------
install_postgres() {
  say "Installing PostgreSQL $PG_VER…"
  if ! command -v psql >/dev/null 2>&1; then
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/pgdg.gpg
    echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list
    apt-get update -y
    apt-get install -y "postgresql-$PG_VER" "postgresql-client-$PG_VER"
  fi
  systemctl enable --now "postgresql@$PG_VER-main" || systemctl enable --now postgresql || true

  PGDATA_DIR="/etc/postgresql/${PG_VER}/main"
  if [[ ! -d "$PGDATA_DIR" ]]; then
    # Fallback try to find dir
    PGDATA_DIR=$(dirname "$(find /etc/postgresql -type f -name postgresql.conf | head -n1)")
  fi

  # 1) Listen on all interfaces
  sed -ri "s|^[#\s]*listen_addresses\s*=\s*.*|listen_addresses = '*'|" "${PGDATA_DIR}/postgresql.conf"

  # 2) Allow md5 auth from chosen CIDR
  HBA="${PGDATA_DIR}/pg_hba.conf"
  if ! grep -q "host\s\+all\s\+all\s\+${PG_ALLOW_CIDR//\//\\/}\s\+md5" "$HBA"; then
    echo "host    all             all             ${PG_ALLOW_CIDR}           md5" >> "$HBA"
  fi

  systemctl restart "postgresql@$PG_VER-main" || systemctl restart postgresql

  # DB/user for Keycloak
  sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${KC_DB}'" | grep -q 1 || sudo -u postgres createdb "$KC_DB"
  sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${KC_DB_USER}'" | grep -q 1 || sudo -u postgres psql -c "CREATE USER ${KC_DB_USER} WITH PASSWORD '${KC_DB_PASS}';"
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${KC_DB} TO ${KC_DB_USER};" || true

  # UFW: allow 5432 from CIDR
  if [[ "$PG_ALLOW_CIDR" == "0.0.0.0/0" ]]; then
    ufw allow 5432/tcp || true
  else
    ufw allow from "$PG_ALLOW_CIDR" to any port 5432 proto tcp || true
  fi

  ok "PostgreSQL configured for remote access on tcp/5432 (CIDR: ${PG_ALLOW_CIDR})"
}

# --------------------- KEYCLOAK ---------------------
install_keycloak() {
  ensure_docker
  say "Installing Keycloak (Docker)…"
  docker pull quay.io/keycloak/keycloak:latest
  docker rm -f keycloak >/dev/null 2>&1 || true
  mkdir -p /opt/keycloak

  KC_ENV=(-e KEYCLOAK_ADMIN="$KC_ADMIN" -e KEYCLOAK_ADMIN_PASSWORD="$KC_ADMIN_PASS")
  if [[ "${USE_PG,,}" == "y" ]]; then
    KC_DB_URL="jdbc:postgresql://${PG_HOST}:${PG_PORT}/${KC_DB}"
    KC_ENV+=(-e KC_DB=postgres -e KC_DB_URL="$KC_DB_URL" -e KC_DB_USERNAME="$KC_DB_USER" -e KC_DB_PASSWORD="$KC_DB_PASS")
  else
    KC_ENV+=(-e KC_DB=dev-file)
  fi

  docker run -d --name keycloak --restart unless-stopped \
    -p "${KC_HTTP_PORT}:8080" \
    -v /opt/keycloak:/opt/keycloak/data \
    "${KC_ENV[@]}" \
    quay.io/keycloak/keycloak:latest \
    start --http-enabled=true --hostname="${KC_DOMAIN}" --proxy=edge

  ok "Keycloak internal on http://127.0.0.1:${KC_HTTP_PORT} (proxied via Caddy)"
}

# --------------------- CADDY (TLS + Reverse Proxy) ---------------------
install_caddy() {
  say "Installing Caddy (automatic HTTPS)…"
  apt-get install -y debian-keyring debian-archive-keyring || true
  curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt | tee /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -y
  apt-get install -y caddy

  # Global email + 3 sites
  cat > /etc/caddy/Caddyfile <<EOF
{
  email ${ACME_EMAIL}
}

${WEBMIN_DOMAIN} {
  reverse_proxy 127.0.0.1:${WEBMIN_PORT}
}

${SEQ_DOMAIN} {
  reverse_proxy 127.0.0.1:${SEQ_HTTP_PORT}
  @health path /health
  respond @health 200
}

${KC_DOMAIN} {
  reverse_proxy 127.0.0.1:${KC_HTTP_PORT}
}
EOF

  systemctl enable --now caddy
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true

  ok "Caddy is handling HTTPS with auto-renew for:"
  echo "  - https://${WEBMIN_DOMAIN}"
  echo "  - https://${SEQ_DOMAIN}"
  echo "  - https://${KC_DOMAIN}"
}

# --------------------- RUN ---------------------
WEBMIN_URL=""; SEQ_UI_URL=""; KC_URL=""; PG_SUMMARY=""

if [[ "${DO_WEBMIN,,}" == "y" ]]; then
  install_webmin
  WEBMIN_URL="https://${WEBMIN_DOMAIN}"
fi

if [[ "${DO_SEQ,,}" == "y" ]]; then
  install_seq
  SEQ_UI_URL="https://${SEQ_DOMAIN}"
fi

if [[ "${DO_KC,,}" == "y" ]]; then
  if [[ "${USE_PG,,}" == "y" ]]; then
    install_postgres
    PG_SUMMARY="PostgreSQL: host=${PG_HOST}, port=${PG_PORT}, db=${KC_DB}, user=${KC_DB_USER}, allowed_cidr=${PG_ALLOW_CIDR}"
  fi
  install_keycloak
  KC_URL="https://${KC_DOMAIN}"
fi

install_caddy

# --------------------- SUMMARY ---------------------
cat <<EOF | tee -a "$LOG_FILE"

========================================
 INSTALLATION SUMMARY (SECRETS INCLUDED)
========================================
Server:             ${PUBLIC_HOST}

[TLS / HTTPS - Caddy]
  ACME email:       ${ACME_EMAIL}
  Auto-renew:       Enabled (managed by Caddy)
  Webmin URL:       ${WEBMIN_URL}
  Seq UI URL:       ${SEQ_UI_URL}
  Keycloak URL:     ${KC_URL}

[Webmin]
  Internal port:    ${WEBMIN_PORT}
  Proxied:          Yes (via Caddy over HTTPS)

[Seq]
  UI (HTTPS):       ${SEQ_UI_URL}
  UI internal:      http://127.0.0.1:${SEQ_HTTP_PORT}
  Ingestion port:   ${SEQ_INGEST_PORT} (HTTP)
  Admin password:   ${SEQ_ADMIN_PASS}
  Ingestion API key:${SEQ_INGEST_KEY}
  License:          $([[ -n "$SEQ_LICENSE" ]] && echo "(provided)" || echo "(not provided)")
  Serilog example:
    "WriteTo": [
      { "Name": "Seq", "Args": {
          "serverUrl": "${SEQ_UI_URL}",
          "apiKey": "${SEQ_INGEST_KEY}"
      }}]
    Ingestion endpoint (raw): http://${PUBLIC_HOST}:${SEQ_INGEST_PORT}

[Keycloak]
  URL (HTTPS):      ${KC_URL}
  Internal port:    ${KC_HTTP_PORT}
  Admin user:       ${KC_ADMIN}
  Admin password:   ${KC_ADMIN_PASS}
  DB backend:       $([[ "${USE_PG,,}" == "y" ]] && echo "PostgreSQL" || echo "Embedded (dev-file)") 
  ${PG_SUMMARY:+$PG_SUMMARY}
  DB password:      ${KC_DB_PASS:-N/A}

[Firewall]
  Opened: 80/tcp, 443/tcp
  Also open: 5432/tcp (per CIDR), ${SEQ_INGEST_PORT}/tcp (Seq ingestion)

Security Note:
  This file contains secrets. Securely remove when done:
    shred -u "${LOG_FILE}"

========================================
EOF

ok "All set."
echo "Access:"
[[ -n "$WEBMIN_URL" ]] && echo "  • Webmin  : $WEBMIN_URL"
[[ -n "$SEQ_UI_URL" ]] && echo "  • Seq UI  : $SEQ_UI_URL"
[[ -n "$KC_URL" ]] && echo "  • Keycloak: $KC_URL"
echo "Seq ingestion (HTTP): http://${PUBLIC_HOST}:${SEQ_INGEST_PORT}"
echo "Log with secrets saved to: $LOG_FILE"
