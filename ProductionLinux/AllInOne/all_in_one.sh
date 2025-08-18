#!/usr/bin/env bash
set -euo pipefail

# ============================================
# Combined Installer: Webmin + Seq + Keycloak
# Compatible: Ubuntu 22.04/24.04
# Logs EVERYTHING (including passwords) to setup.log (as requested).
# ============================================

LOG_FILE="$(pwd)/setup.log"
: > "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# ---------- styling ----------
RED="\033[0;31m"; GRN="\033[0;32m"; YEL="\033[1;33m"; BLU="\033[0;34m"; NC="\033[0m"
say() { echo -e "${BLU}==>${NC} $*"; }
ok()  { echo -e "${GRN}[OK]${NC} $*"; }
warn(){ echo -e "${YEL}[WARN]${NC} $*"; }
err() { echo -e "${RED}[ERR]${NC} $*"; }

# ---------- root check ----------
if [[ $EUID -ne 0 ]]; then
  err "Please run as root (e.g., sudo $0)"
  exit 1
fi

# ---------- helpers ----------
confirm () {
  local prompt="${1:-Proceed?} [Y/n]: "
  read -r -p "$prompt" ans || true
  [[ -z "${ans:-}" || "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}
gen_pass () {
  tr -dc 'A-Za-z0-9!@#%^&*()-_=+' </dev/urandom | head -c 20
}

require_cmd () {
  if ! command -v "$1" >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y "$2"
  fi
}

# ---------- gather inputs ----------
say "Let's collect a few settings. Press Enter to accept defaults."

# General
read -r -p "Public hostname or domain (for services) [$(hostname -f)]: " PUBLIC_HOST
PUBLIC_HOST="${PUBLIC_HOST:-$(hostname -f)}"

# Webmin
read -r -p "Install Webmin? [Y/n]: " DO_WEBMIN
DO_WEBMIN="${DO_WEBMIN:-Y}"
read -r -p "Webmin port [10000]: " WEBMIN_PORT
WEBMIN_PORT="${WEBMIN_PORT:-10000}"

# Seq
read -r -p "Install Seq (Datalust)? [Y/n]: " DO_SEQ
DO_SEQ="${DO_SEQ:-Y}"
read -r -p "Seq HTTP port [5341]: " SEQ_HTTP_PORT
SEQ_HTTP_PORT="${SEQ_HTTP_PORT:-5341}"
read -r -p "Seq ingestion (HTTP) port [5341]: " SEQ_INGEST_PORT
SEQ_INGEST_PORT="${SEQ_INGEST_PORT:-5341}"
read -r -p "Provide a Seq admin password (leave blank to auto-generate): " SEQ_ADMIN_PASS
SEQ_ADMIN_PASS="${SEQ_ADMIN_PASS:-$(gen_pass)}"
read -r -p "Provide a Seq API key/ingestion key (leave blank to auto-generate): " SEQ_INGEST_KEY
SEQ_INGEST_KEY="${SEQ_INGEST_KEY:-$(gen_pass)}"
read -r -p "Provide a Seq license key (optional, press Enter to skip): " SEQ_LICENSE
SEQ_LICENSE="${SEQ_LICENSE:-}"

# Keycloak
read -r -p "Install Keycloak? [Y/n]: " DO_KC
DO_KC="${DO_KC:-Y}"
read -r -p "Keycloak HTTP port [8080]: " KC_HTTP_PORT
KC_HTTP_PORT="${KC_HTTP_PORT:-8080}"
read -r -p "Keycloak admin username [admin]: " KC_ADMIN
KC_ADMIN="${KC_ADMIN:-admin}"
read -r -p "Keycloak admin password (leave blank to auto-generate): " KC_ADMIN_PASS
KC_ADMIN_PASS="${KC_ADMIN_PASS:-$(gen_pass)}"

read -r -p "Use PostgreSQL for Keycloak persistence? [Y/n]: " USE_PG
USE_PG="${USE_PG:-Y}"
if [[ "${USE_PG,,}" == "y" || -z "$USE_PG" ]]; then
  read -r -p "PostgreSQL version [16]: " PG_VER
  PG_VER="${PG_VER:-16}"
  read -r -p "PostgreSQL database name for Keycloak [keycloak_prod]: " KC_DB
  KC_DB="${KC_DB:-keycloak_prod}"
  read -r -p "PostgreSQL username for Keycloak [keycloak]: " KC_DB_USER
  KC_DB_USER="${KC_DB_USER:-keycloak}"
  read -r -p "PostgreSQL password for Keycloak (leave blank to auto-generate): " KC_DB_PASS
  KC_DB_PASS="${KC_DB_PASS:-$(gen_pass)}"
  read -r -p "PostgreSQL host [localhost]: " PG_HOST
  PG_HOST="${PG_HOST:-localhost}"
  read -r -p "PostgreSQL port [5432]: " PG_PORT
  PG_PORT="${PG_PORT:-5432}"
else
  PG_VER=""
  KC_DB=""
  KC_DB_USER=""
  KC_DB_PASS=""
  PG_HOST=""
  PG_PORT=""
fi

say "Thanks. Starting install in 5 seconds. Ctrl+C to abort."
sleep 5

# ---------- prerequisites ----------
say "Installing prerequisites..."
apt-get update -y
apt-get install -y curl wget apt-transport-https gnupg ca-certificates lsb-release ufw jq unzip

# ---------- WEBMIN ----------
install_webmin () {
  say "Installing Webmin..."
  # Add repo & key
  if ! apt-cache policy | grep -q 'download.webmin.com'; then
    wget -qO- http://www.webmin.com/jcameron-key.asc | gpg --dearmor -o /usr/share/keyrings/webmin.gpg
    echo "deb [signed-by=/usr/share/keyrings/webmin.gpg] http://download.webmin.com/download/repository sarge contrib" > /etc/apt/sources.list.d/webmin.list
  fi
  apt-get update -y
  apt-get install -y webmin

  # Adjust port if needed
  if [[ -n "$WEBMIN_PORT" ]]; then
    sed -i "s/^port=.*/port=$WEBMIN_PORT/" /etc/webmin/miniserv.conf
    systemctl restart webmin || true
  fi

  # Firewall allow
  if command -v ufw >/dev/null 2>&1; then
    ufw allow "$WEBMIN_PORT"/tcp || true
  fi

  ok "Webmin installed on port $WEBMIN_PORT"
  say "Access: https://$PUBLIC_HOST:$WEBMIN_PORT/"
}

# ---------- Docker engine ----------
ensure_docker () {
  if ! command -v docker >/dev/null 2>&1; then
    say "Installing Docker..."
    apt-get remove -y docker docker-engine docker.io containerd runc || true
    apt-get install -y ca-certificates curl
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      | tee /etc/apt/sources.list.d/docker.list >/dev/null
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    ok "Docker installed."
  fi
}

# ---------- SEQ (Docker) ----------
install_seq () {
  ensure_docker
  say "Installing Seq (Docker)..."

  mkdir -p /opt/seq
  docker pull datalust/seq:latest

  # Create / update container
  if docker ps -a --format '{{.Names}}' | grep -q '^seq$'; then
    warn "Seq container already exists. Recreating..."
    docker rm -f seq || true
  fi

  # Environment configuration
  # - SEQ_FIRSTRUN_ADMINPASSWORD sets admin account.
  # - SEQ_ACCEPT_EULA must be set to Y.
  # - SEQ_LICENSE accepted if provided.
  ENV_FLAGS=(-e SEQ_FIRSTRUN_ADMINPASSWORD="$SEQ_ADMIN_PASS" -e SEQ_ACCEPT_EULA=Y)
  if [[ -n "$SEQ_LICENSE" ]]; then
    ENV_FLAGS+=(-e SEQ_LICENSE="$SEQ_LICENSE")
  fi

  docker run -d \
    --name seq \
    --restart unless-stopped \
    -p "${SEQ_HTTP_PORT}:80" \
    -p "${SEQ_INGEST_PORT}:5341" \
    -v /opt/seq:/data \
    "${ENV_FLAGS[@]}" \
    datalust/seq:latest

  # Create an API key for ingestion
  say "Creating Seq ingestion API key..."
  sleep 5
  # Try to create a default API key (best-effort)
  docker exec seq seqcli apikey create -t "IngestionKey" -s "http://localhost" -k "$SEQ_INGEST_KEY" >/dev/null 2>&1 || true

  # Firewall
  ufw allow "${SEQ_HTTP_PORT}"/tcp || true
  ufw allow "${SEQ_INGEST_PORT}"/tcp || true

  ok "Seq running on http://$PUBLIC_HOST:${SEQ_HTTP_PORT}"
  say "Ingestion endpoint: http://$PUBLIC_HOST:${SEQ_INGEST_PORT}"
}

# ---------- PostgreSQL ----------
install_postgres () {
  say "Installing PostgreSQL $PG_VER..."
  if ! command -v psql >/dev/null 2>&1; then
    # Official PGDG
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/pgdg.gpg
    echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
    apt-get update -y
    apt-get install -y "postgresql-$PG_VER" "postgresql-client-$PG_VER"
  fi
  systemctl enable --now "postgresql@$PG_VER-main" || systemctl enable --now postgresql || true

  # Create DB/user if needed
  sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${KC_DB}'" | grep -q 1 || sudo -u postgres createdb "$KC_DB"
  sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${KC_DB_USER}'" | grep -q 1 || sudo -u postgres psql -c "CREATE USER ${KC_DB_USER} WITH PASSWORD '${KC_DB_PASS}';"
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${KC_DB} TO ${KC_DB_USER};" || true

  ok "PostgreSQL ready. DB=${KC_DB}, USER=${KC_DB_USER}"
}

# ---------- KEYCLOAK (Docker) ----------
install_keycloak () {
  ensure_docker
  say "Installing Keycloak (Docker)..."
  docker pull quay.io/keycloak/keycloak:latest

  if docker ps -a --format '{{.Names}}' | grep -q '^keycloak$'; then
    warn "Keycloak container already exists. Recreating..."
    docker rm -f keycloak || true
  fi

  mkdir -p /opt/keycloak
  KC_ENV=(-e KEYCLOAK_ADMIN="$KC_ADMIN" -e KEYCLOAK_ADMIN_PASSWORD="$KC_ADMIN_PASS")

  if [[ "${USE_PG,,}" == "y" || -z "$USE_PG" ]]; then
    # Use external PostgreSQL
    KC_DB_URL="jdbc:postgresql://${PG_HOST}:${PG_PORT}/${KC_DB}"
    KC_ENV+=(
      -e KC_DB=postgres
      -e KC_DB_URL="$KC_DB_URL"
      -e KC_DB_USERNAME="$KC_DB_USER"
      -e KC_DB_PASSWORD="$KC_DB_PASS"
    )
  else
    KC_ENV+=(-e KC_DB=dev-file) # demo/dev mode storage
  fi

  docker run -d \
    --name keycloak \
    --restart unless-stopped \
    -p "${KC_HTTP_PORT}:8080" \
    -v /opt/keycloak:/opt/keycloak/data \
    "${KC_ENV[@]}" \
    quay.io/keycloak/keycloak:latest \
    start --http-enabled=true --hostname="${PUBLIC_HOST}" --proxy=edge

  ufw allow "${KC_HTTP_PORT}"/tcp || true
  ok "Keycloak running at: http://${PUBLIC_HOST}:${KC_HTTP_PORT}"
}

# ---------- RUN ----------
WEBMIN_URL=""
SEQ_URL=""
KC_URL=""
PG_SUMMARY=""

if [[ "${DO_WEBMIN,,}" == "y" || -z "$DO_WEBMIN" ]]; then
  install_webmin
  WEBMIN_URL="https://${PUBLIC_HOST}:${WEBMIN_PORT}/"
fi

if [[ "${DO_SEQ,,}" == "y" || -z "$DO_SEQ" ]]; then
  install_seq
  SEQ_URL="http://${PUBLIC_HOST}:${SEQ_HTTP_PORT}"
fi

if [[ "${DO_KC,,}" == "y" || -z "$DO_KC" ]]; then
  if [[ "${USE_PG,,}" == "y" || -z "$USE_PG" ]]; then
    install_postgres
    PG_SUMMARY="PostgreSQL: host=${PG_HOST}, port=${PG_PORT}, db=${KC_DB}, user=${KC_DB_USER}"
  fi
  install_keycloak
  KC_URL="http://${PUBLIC_HOST}:${KC_HTTP_PORT}"
fi

# ---------- SUMMARY ----------
say "Writing final summary to ${LOG_FILE} ..."
cat <<EOF | tee -a "$LOG_FILE"

========================================
 INSTALLATION SUMMARY (SECRETS INCLUDED)
========================================
Host:               ${PUBLIC_HOST}

[Webmin]
  Installed:        $([[ -n "$WEBMIN_URL" ]] && echo "Yes" || echo "No")
  URL:              ${WEBMIN_URL}
  Port:             ${WEBMIN_PORT}

[Seq]
  Installed:        $([[ -n "$SEQ_URL" ]] && echo "Yes" || echo "No")
  URL (UI):         ${SEQ_URL}
  HTTP Port:        ${SEQ_HTTP_PORT}
  Ingest Port:      ${SEQ_INGEST_PORT}
  Admin Password:   ${SEQ_ADMIN_PASS}
  Ingestion API Key:${SEQ_INGEST_KEY}
  License:          $([[ -n "$SEQ_LICENSE" ]] && echo "(provided)" || echo "(not provided)")}
  Example .NET Serilog config:
    WriteTo: Seq serverUrl=http://${PUBLIC_HOST}:${SEQ_HTTP_PORT} apiKey=${SEQ_INGEST_KEY}
    Ingestion endpoint: http://${PUBLIC_HOST}:${SEQ_INGEST_PORT}

[Keycloak]
  Installed:        $([[ -n "$KC_URL" ]] && echo "Yes" || echo "No")
  URL:              ${KC_URL}
  Port:             ${KC_HTTP_PORT}
  Admin User:       ${KC_ADMIN}
  Admin Password:   ${KC_ADMIN_PASS}
  DB Backend:       $([[ "${USE_PG,,}" == "y" || -z "$USE_PG" ]] && echo "PostgreSQL" || echo "Embedded (dev-file)")}
  ${PG_SUMMARY:+$PG_SUMMARY}
  DB Password:      ${KC_DB_PASS:-N/A}

[Firewall/Ports opened]
  - Webmin: ${WEBMIN_PORT:+$WEBMIN_PORT} (TCP)
  - Seq UI: ${SEQ_HTTP_PORT:+$SEQ_HTTP_PORT} (TCP)
  - Seq Ingestion: ${SEQ_INGEST_PORT:+$SEQ_INGEST_PORT} (TCP)
  - Keycloak: ${KC_HTTP_PORT:+$KC_HTTP_PORT} (TCP)

[Diagnostics]
  Docker containers:
$(docker ps --format '    - {{.Names}} ({{.Status}}) -> {{.Ports}}' 2>/dev/null || echo "    (Docker not installed or no containers)")

  Systemd services:
    - webmin: $(systemctl is-active webmin 2>/dev/null || echo "n/a")

Security Note:
  This log contains passwords and secrets. To securely remove:
    shred -u "${LOG_FILE}"

========================================
EOF

ok "Done!"
say "Access URLs:"
[[ -n "$WEBMIN_URL" ]] && echo "  • Webmin  : $WEBMIN_URL"
[[ -n "$SEQ_URL"    ]] && echo "  • Seq     : $SEQ_URL"
[[ -n "$KC_URL"     ]] && echo "  • Keycloak: $KC_URL"

say "As requested, passwords and usernames are saved in: $LOG_FILE"
say "When you no longer need it, delete securely with: shred -u \"$LOG_FILE\""
