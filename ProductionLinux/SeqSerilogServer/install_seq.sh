#!/bin/bash
# Seq Log Server Ultimate Installation Script for Ubuntu 22.04+
# - Idempotent: safe to re-run after a previous attempt
# - Adds/uses Apache vhost (installs Apache if missing)
# - Runs Seq via Docker with persistent data volume
# - FIX: always supplies SEQ_FIRSTRUN_ADMINPASSWORD (Seq ignores it after initialization)
# Author: Production Deployment Script
# Version: 1.2 (First-run admin password baked in)
# Date: August 2025
set -euo pipefail

# =========================
# Defaults
# =========================
DEFAULT_HOSTNAME="logs.sivargpt.com"
DEFAULT_DATA_DIR="/var/lib/seq"
DEFAULT_BACKEND_PORT="5342"       # host port -> container 80 (UI + HTTP ingestion)
DEFAULT_TCP_INGEST_PORT="5341"    # host port -> container 5341 (raw TCP ingestion)
DEFAULT_ACCEPT_EULA="Y"
DEFAULT_OPEN_TCP_INGEST="N"
DEFAULT_TCP_INGEST_CIDR="10.0.0.0/24" # only used if OPEN_TCP_INGEST=Y
DEFAULT_SEQ_IMAGE="datalust/seq:latest"
DEFAULT_SEQ_ADMIN_PASSWORD="ChangeMe!123"  # used on first run; safe to always pass
DEFAULT_ENABLE_SSL="N"                     # prompt anyway

# =========================
# Runtime variables
# =========================
HOSTNAME=""
DATA_DIR=""
BACKEND_PORT=""
TCP_INGEST_PORT=""
ACCEPT_EULA=""
OPEN_TCP_INGEST=""
TCP_INGEST_CIDR=""
SEQ_IMAGE=""
SEQ_ADMIN_PASSWORD=""
ENABLE_SSL=""

# =========================
# Pretty logging
# =========================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log(){ echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
ok(){ echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] OK:${NC} $1"; }
warn(){ echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $1"; }
err(){ echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"; }

check_root(){ [[ $EUID -eq 0 ]] || { err "Run as root"; exit 1; }; }

prompt_inputs(){
  echo; log "=== Seq Log Server Installation Configuration ==="; echo
  echo -e "${YELLOW}Press Enter to accept defaults in [brackets]${NC}"
  read -p "Hostname [$DEFAULT_HOSTNAME]: " HOSTNAME; HOSTNAME=${HOSTNAME:-$DEFAULT_HOSTNAME}
  read -p "Data directory [$DEFAULT_DATA_DIR]: " DATA_DIR; DATA_DIR=${DATA_DIR:-$DEFAULT_DATA_DIR}
  read -p "Backend HTTP port (host -> container:80) [$DEFAULT_BACKEND_PORT]: " BACKEND_PORT; BACKEND_PORT=${BACKEND_PORT:-$DEFAULT_BACKEND_PORT}
  read -p "TCP ingestion port (host -> container:5341) [$DEFAULT_TCP_INGEST_PORT]: " TCP_INGEST_PORT; TCP_INGEST_PORT=${TCP_INGEST_PORT:-$DEFAULT_TCP_INGEST_PORT}
  read -p "Open TCP ingestion to a CIDR? (Y/N) [$DEFAULT_OPEN_TCP_INGEST]: " OPEN_TCP_INGEST; OPEN_TCP_INGEST=${OPEN_TCP_INGEST:-$DEFAULT_OPEN_TCP_INGEST}
  if [[ "$OPEN_TCP_INGEST" =~ ^[Yy]$ ]]; then
    read -p "CIDR allowed for TCP ingestion [$DEFAULT_TCP_INGEST_CIDR]: " TCP_INGEST_CIDR; TCP_INGEST_CIDR=${TCP_INGEST_CIDR:-$DEFAULT_TCP_INGEST_CIDR}
  else
    TCP_INGEST_CIDR=""
  fi
  read -p "Accept Seq EULA? (Y/N) [$DEFAULT_ACCEPT_EULA]: " ACCEPT_EULA; ACCEPT_EULA=${ACCEPT_EULA:-$DEFAULT_ACCEPT_EULA}
  read -p "Docker image [$DEFAULT_SEQ_IMAGE]: " SEQ_IMAGE; SEQ_IMAGE=${SEQ_IMAGE:-$DEFAULT_SEQ_IMAGE}
  read -p "Initial admin password (first run) [$DEFAULT_SEQ_ADMIN_PASSWORD]: " SEQ_ADMIN_PASSWORD; SEQ_ADMIN_PASSWORD=${SEQ_ADMIN_PASSWORD:-$DEFAULT_SEQ_ADMIN_PASSWORD}
  read -p "Run Let's Encrypt SSL setup now? (Y/N) [$DEFAULT_ENABLE_SSL]: " ENABLE_SSL; ENABLE_SSL=${ENABLE_SSL:-$DEFAULT_ENABLE_SSL}

  echo; log "Summary:"
  echo "  Hostname:          $HOSTNAME"
  echo "  Data dir:          $DATA_DIR"
  echo "  Backend port:      $BACKEND_PORT (host -> container:80)"
  echo "  TCP ingest port:   $TCP_INGEST_PORT (host -> container:5341) ${TCP_INGEST_CIDR:+(allowed: $TCP_INGEST_CIDR)}"
  echo "  Accept EULA:       $ACCEPT_EULA"
  echo "  Image:             $SEQ_IMAGE"
  echo "  SSL now:           $ENABLE_SSL"
  echo "  Admin password:    (hidden; Seq ignores after init)"
  echo
  read -p "Continue? (y/N): " confirm
  [[ $confirm =~ ^[Yy]$ ]] || { log "Cancelled."; exit 0; }
}

update_system(){ log "Updating apt..."; apt-get update -y && apt-get upgrade -y; ok "System packages updated"; }

ensure_base_packages(){
  log "Installing base packages..."
  apt-get install -y ca-certificates curl gnupg lsb-release ufw fail2ban jq
  ok "Base packages installed"
}

ensure_docker(){
  if ! command -v docker >/dev/null 2>&1; then
    log "Installing Docker CE..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    ok "Docker installed"
  else
    ok "Docker already installed"
  fi
}

ensure_apache(){
  if command -v apache2 >/dev/null 2>&1; then
    ok "Apache found; will add Seq vhost"
  else
    log "Installing Apache + certbot module..."
    apt-get install -y apache2 certbot python3-certbot-apache
    systemctl enable --now apache2
    ok "Apache installed"
  fi
  a2enmod proxy proxy_http headers rewrite ssl >/dev/null 2>&1 || true
}

prepare_dirs(){
  log "Preparing data dir $DATA_DIR ..."
  mkdir -p "$DATA_DIR"
  chown root:root "$DATA_DIR"
  chmod 755 "$DATA_DIR"
  ok "Data dir ready"
}

stop_existing_container(){
  if docker ps -a --format '{{.Names}}' | grep -q '^seq$'; then
    warn "Existing 'seq' container found; removing to re-create cleanly"
    docker rm -f seq || true
  fi
}

run_seq_container(){
  [[ "$ACCEPT_EULA" =~ ^[Yy]$ ]] || { err "EULA must be accepted (Y)"; exit 1; }

  log "Pulling image $SEQ_IMAGE ..."
  docker pull "$SEQ_IMAGE" >/dev/null || true

  # Always pass first-run admin password; Seq ignores it after initialization
  log "Starting Seq container..."
  docker run -d --name seq \
    -e ACCEPT_EULA=Y \
    -e SEQ_FIRSTRUN_ADMINPASSWORD="${SEQ_ADMIN_PASSWORD}" \
    -e SEQ_BASEURI="https://${HOSTNAME}/" \
    -p "127.0.0.1:${BACKEND_PORT}:80" \
    -p "${TCP_INGEST_PORT}:5341" \
    -v "${DATA_DIR}:/data" \
    --restart unless-stopped \
    "$SEQ_IMAGE"

  ok "Seq container launched"
}

wait_for_seq(){
  local port="$1"; local max=90; local n=1
  log "Waiting for Seq at http://127.0.0.1:${port}/ ..."
  until curl -fsS "http://127.0.0.1:${port}/" >/dev/null 2>&1; do
    if (( n >= max )); then
      warn "Seq didn’t respond after ~$((max*2))s; continuing (UI may 503 until ready)"
      return
    fi
    sleep 2; n=$((n+1))
  done
  ok "Seq backend is answering"
}

configure_apache_vhost(){
  log "Writing Apache vhost for $HOSTNAME ..."
  # headers include (you can add CSP frame-ancestors here later if embedding)
  cat > /etc/apache2/conf-available/seq-headers.conf <<'EOF'
<IfModule mod_headers.c>
    Header always set X-Content-Type-Options nosniff
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    # To allow embedding Seq in an iframe from specific origins, you can uncomment:
    # Header always unset X-Frame-Options
    # Header always set Content-Security-Policy "frame-ancestors 'self' https://your-shell.example.com"
</IfModule>
EOF
  a2enconf seq-headers.conf >/dev/null 2>&1 || true

  cat > /etc/apache2/sites-available/seq.conf <<EOF
<VirtualHost *:80>
    ServerName ${HOSTNAME}

    ProxyPreserveHost On
    ProxyRequests Off
    ProxyTimeout 300

    # ACME path
    ProxyPass /.well-known/acme-challenge/ !
    DocumentRoot /var/www/html

    # Forward headers reflect the real scheme/port dynamically
    RequestHeader set X-Forwarded-Proto expr=%{REQUEST_SCHEME}
    RequestHeader set X-Forwarded-Port  expr=%{SERVER_PORT}
    RequestHeader set X-Forwarded-Host  "%{HTTP_HOST}s"

    # Proxy all to Seq backend (UI + HTTP ingestion)
    ProxyPass        / http://127.0.0.1:${BACKEND_PORT}/ keepalive=On
    ProxyPassReverse / http://127.0.0.1:${BACKEND_PORT}/

    ErrorLog \${APACHE_LOG_DIR}/seq_error.log
    CustomLog \${APACHE_LOG_DIR}/seq_access.log combined
</VirtualHost>
EOF

  a2ensite seq.conf >/dev/null 2>&1 || true
  apache2ctl configtest
  systemctl reload apache2
  ok "Apache vhost enabled and reloaded"
}

configure_ufw(){
  log "Configuring UFW..."
  if ! ufw status | grep -q "Status: active"; then
    warn "UFW not active; enabling with sane defaults"
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
  fi
  ufw allow 80/tcp  comment 'HTTP'
  ufw allow 443/tcp comment 'HTTPS'
  if [[ "$OPEN_TCP_INGEST" =~ ^[Yy]$ ]]; then
    ufw allow from "$TCP_INGEST_CIDR" to any port "$TCP_INGEST_PORT" proto tcp comment 'Seq TCP ingest'
  else
    log "TCP ingest port $TCP_INGEST_PORT remains firewalled (recommended)"
  fi
  ufw --force enable
  ok "UFW configured"
}

configure_fail2ban(){
  systemctl enable --now fail2ban >/dev/null 2>&1 || true
  ok "fail2ban enabled"
}

ssl_step(){
  if [[ "$ENABLE_SSL" =~ ^[Yy]$ ]]; then
    log "Running Let's Encrypt for ${HOSTNAME} ..."
    apt-get install -y certbot python3-certbot-apache >/dev/null 2>&1 || true
    if certbot --apache -d "$HOSTNAME" --non-interactive --agree-tos --email admin@"$HOSTNAME" --redirect; then
      ok "SSL certificate installed; HTTP -> HTTPS redirect enabled"
      systemctl reload apache2
    else
      err "Certbot failed; you can retry later: certbot --apache -d $HOSTNAME"
    fi
  else
    warn "Skipping SSL; later: certbot --apache -d $HOSTNAME"
  fi
}

write_diag(){
  log "Writing diagnostic helper /root/seq-diagnostic.sh ..."
  cat > /root/seq-diagnostic.sh <<EOF
#!/bin/bash
echo "=== SEQ Diagnostic Report ==="
date
echo
echo "[Services]"
systemctl status apache2 --no-pager -l | head -12 || true
echo
echo "[Docker]"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || true
echo
echo "[Ports]"
ss -tulpen | grep -E ":(${BACKEND_PORT}|80|443|${TCP_INGEST_PORT})\\b" || true
echo
echo "[Proxy test]"
curl -s -o /dev/null -w "%{http_code}\\n" "http://${HOSTNAME}/"
echo
echo "[Backend test]"
curl -s -o /dev/null -w "%{http_code}\\n" "http://127.0.0.1:${BACKEND_PORT}/"
echo
echo "[Seq /api]"
curl -s -o /dev/null -w "%{http_code}\\n" "http://127.0.0.1:${BACKEND_PORT}/api"
echo
echo "[Container logs (last 100)]"
docker logs --tail 100 seq || true
EOF
  chmod +x /root/seq-diagnostic.sh
  ok "Diagnostic script ready: /root/seq-diagnostic.sh"
}

summary(){
  local ip=$(curl -s ifconfig.me 2>/dev/null || echo "Unknown")
  echo
  echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║            🎉 SEQ INSTALLATION COMPLETE! 🎉          ║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
  echo
  echo -e "${BLUE}📋 SUMMARY:${NC}"
  echo "  • Hostname:        $HOSTNAME"
  echo "  • UI via Apache:   http://$HOSTNAME/  (use HTTPS if enabled)"
  echo "  • Backend local:   http://127.0.0.1:${BACKEND_PORT}/"
  echo "  • TCP ingest port: $TCP_INGEST_PORT ${TCP_INGEST_CIDR:+(allowed: $TCP_INGEST_CIDR)}"
  echo "  • Data dir:        $DATA_DIR"
  echo "  • Image:           $SEQ_IMAGE"
  echo "  • Server IP:       $ip"
  echo
  echo -e "${YELLOW}🔑 Login (first run only):${NC}"
  echo "  • Username: admin"
  echo "  • Password: (the one you entered; ignored if data dir already initialized)"
  echo
  echo -e "${YELLOW}🛠 Useful:${NC}"
  echo "  • Restart:  docker restart seq"
  echo "  • Logs:     docker logs -f seq"
  echo "  • Remove:   docker rm -f seq"
  echo "  • Diagnose: /root/seq-diagnostic.sh"
  echo
}

main(){
  trap 'err "Install failed at line $LINENO"; exit 1' ERR
  check_root
  prompt_inputs
  update_system
  ensure_base_packages
  ensure_docker
  ensure_apache
  prepare_dirs
  stop_existing_container
  run_seq_container
  wait_for_seq "$BACKEND_PORT"
  configure_apache_vhost
  configure_ufw
  configure_fail2ban
  ssl_step
  write_diag
  summary
}

main "$@"
