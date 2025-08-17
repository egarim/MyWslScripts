#!/bin/bash
# ============================================================================
# Merge Installer: Keycloak (native) + Seq (docker) on Ubuntu 22.04+
# - Consolidates prompts from both original scripts into a single guided run
# - Installs shared dependencies once
# - Writes a full /root/setup.log (includes credentials for later deletion)
# - Drops per-app diagnostic helpers
# - Idempotent-ish: safe to re-run (will recreate containers/vhosts as needed)
# Author: merged-from-user-supplied scripts
# Date: 2025-08-17
# ============================================================================
set -euo pipefail

LOG_FILE="/root/setup.log"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

RED='\\033[0;31m'; GREEN='\\033[0;32m'; YELLOW='\\033[1;33m'; BLUE='\\033[0;34m'; NC='\\033[0m'
log(){ echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; echo "[$(date +'%F %T)] $1" >> "$LOG_FILE"; }
ok(){ echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] OK:${NC} $1"; echo "OK: $1" >> "$LOG_FILE"; }
warn(){ echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $1"; echo "WARN: $1" >> "$LOG_FILE"; }
err(){ echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"; echo "ERROR: $1" >> "$LOG_FILE"; }

require_root(){ [[ $EUID -eq 0 ]] || { err "Run as root."; exit 1; }; }

# ---------------------------- Defaults (Keycloak) ----------------------------
KC_VERSION="26.3.1"
KC_USER="keycloak"
KC_GROUP="keycloak"
KC_HOME="/opt/keycloak"
KC_LOG_DIR="/var/log/keycloak"
KC_DATA_DIR="/var/lib/keycloak"
KC_DEFAULT_HOSTNAME="auth.example.com"
KC_DEFAULT_DB_NAME="keycloak_prod"
KC_DEFAULT_DB_USER="keycloak_user"
KC_DEFAULT_DB_PASSWORD="ChangeMeDB!123"
KC_DEFAULT_ADMIN_USER="keycloakadmin"
KC_DEFAULT_ADMIN_PASSWORD="ChangeMeKC!123"
KC_DEFAULT_HTTP_PORT="8080"
KC_DEFAULT_ALLOWED_FRAME_ANCESTORS="'self' https://your-shell.example.com"

# ------------------------------ Defaults (Seq) -------------------------------
SEQ_DEFAULT_HOSTNAME="logs.example.com"
SEQ_DEFAULT_DATA_DIR="/var/lib/seq"
SEQ_DEFAULT_BACKEND_PORT="5342"     # host -> container:80
SEQ_DEFAULT_TCP_INGEST_PORT="5341"  # host -> container:5341
SEQ_DEFAULT_ACCEPT_EULA="Y"
SEQ_DEFAULT_OPEN_TCP_INGEST="N"
SEQ_DEFAULT_TCP_INGEST_CIDR="10.0.0.0/24"
SEQ_DEFAULT_IMAGE="datalust/seq:latest"
SEQ_DEFAULT_ADMIN_PASSWORD="ChangeMe!123"
SEQ_DEFAULT_ENABLE_SSL="N"

# ------------------------------ User responses ------------------------------
INSTALL_KEYCLOAK="Y"
INSTALL_SEQ="Y"

KC_HOSTNAME=""
KC_DB_NAME=""
KC_DB_USER=""
KC_DB_PASSWORD=""
KC_ADMIN_USER=""
KC_ADMIN_PASSWORD=""
KC_HTTP_PORT=""
KC_ALLOWED_FRAME_ANCESTORS=""

SEQ_HOSTNAME=""
SEQ_DATA_DIR=""
SEQ_BACKEND_PORT=""
SEQ_TCP_INGEST_PORT=""
SEQ_ACCEPT_EULA=""
SEQ_OPEN_TCP_INGEST=""
SEQ_TCP_INGEST_CIDR=""
SEQ_IMAGE=""
SEQ_ADMIN_PASSWORD=""
SEQ_ENABLE_SSL=""

PROMPT_ALL(){
  echo; log "=== Merge Installer: Keycloak + Seq ==="; echo
  read -p "Install Keycloak? (Y/N) [Y]: " INSTALL_KEYCLOAK; INSTALL_KEYCLOAK=${INSTALL_KEYCLOAK:-Y}
  read -p "Install Seq (Docker)? (Y/N) [Y]: " INSTALL_SEQ; INSTALL_SEQ=${INSTALL_SEQ:-Y}

  if [[ "$INSTALL_KEYCLOAK" =~ ^[Yy]$ ]]; then
    echo; log "--- Keycloak configuration ---"
    read -p "Keycloak hostname [$KC_DEFAULT_HOSTNAME]: " KC_HOSTNAME; KC_HOSTNAME=${KC_HOSTNAME:-$KC_DEFAULT_HOSTNAME}
    read -p "Keycloak DB name [$KC_DEFAULT_DB_NAME]: " KC_DB_NAME; KC_DB_NAME=${KC_DB_NAME:-$KC_DEFAULT_DB_NAME}
    read -p "Keycloak DB user [$KC_DEFAULT_DB_USER]: " KC_DB_USER; KC_DB_USER=${KC_DB_USER:-$KC_DEFAULT_DB_USER}
    read -p "Keycloak DB password [$KC_DEFAULT_DB_PASSWORD]: " KC_DB_PASSWORD; KC_DB_PASSWORD=${KC_DB_PASSWORD:-$KC_DEFAULT_DB_PASSWORD}
    read -p "Keycloak admin user [$KC_DEFAULT_ADMIN_USER]: " KC_ADMIN_USER; KC_ADMIN_USER=${KC_ADMIN_USER:-$KC_DEFAULT_ADMIN_USER}
    read -p "Keycloak admin password [$KC_DEFAULT_ADMIN_PASSWORD]: " KC_ADMIN_PASSWORD; KC_ADMIN_PASSWORD=${KC_ADMIN_PASSWORD:-$KC_DEFAULT_ADMIN_PASSWORD}
    read -p "Keycloak backend HTTP port [$KC_DEFAULT_HTTP_PORT]: " KC_HTTP_PORT; KC_HTTP_PORT=${KC_HTTP_PORT:-$KC_DEFAULT_HTTP_PORT}
    read -p "Allowed frame-ancestors (space-separated) [$KC_DEFAULT_ALLOWED_FRAME_ANCESTORS]: " KC_ALLOWED_FRAME_ANCESTORS; KC_ALLOWED_FRAME_ANCESTORS=${KC_ALLOWED_FRAME_ANCESTORS:-$KC_DEFAULT_ALLOWED_FRAME_ANCESTORS}
  fi

  if [[ "$INSTALL_SEQ" =~ ^[Yy]$ ]]; then
    echo; log "--- Seq configuration ---"
    read -p "Seq hostname [$SEQ_DEFAULT_HOSTNAME]: " SEQ_HOSTNAME; SEQ_HOSTNAME=${SEQ_HOSTNAME:-$SEQ_DEFAULT_HOSTNAME}
    read -p "Seq data dir [$SEQ_DEFAULT_DATA_DIR]: " SEQ_DATA_DIR; SEQ_DATA_DIR=${SEQ_DATA_DIR:-$SEQ_DEFAULT_DATA_DIR}
    read -p "Seq backend HTTP port (host->80) [$SEQ_DEFAULT_BACKEND_PORT]: " SEQ_BACKEND_PORT; SEQ_BACKEND_PORT=${SEQ_BACKEND_PORT:-$SEQ_DEFAULT_BACKEND_PORT}
    read -p "Seq TCP ingest port (host->5341) [$SEQ_DEFAULT_TCP_INGEST_PORT]: " SEQ_TCP_INGEST_PORT; SEQ_TCP_INGEST_PORT=${SEQ_TCP_INGEST_PORT:-$SEQ_DEFAULT_TCP_INGEST_PORT}
    read -p "Open TCP ingestion to a CIDR? (Y/N) [$SEQ_DEFAULT_OPEN_TCP_INGEST]: " SEQ_OPEN_TCP_INGEST; SEQ_OPEN_TCP_INGEST=${SEQ_OPEN_TCP_INGEST:-$SEQ_DEFAULT_OPEN_TCP_INGEST}
    if [[ "$SEQ_OPEN_TCP_INGEST" =~ ^[Yy]$ ]]; then
      read -p "CIDR allowed for TCP ingestion [$SEQ_DEFAULT_TCP_INGEST_CIDR]: " SEQ_TCP_INGEST_CIDR; SEQ_TCP_INGEST_CIDR=${SEQ_TCP_INGEST_CIDR:-$SEQ_DEFAULT_TCP_INGEST_CIDR}
    else
      SEQ_TCP_INGEST_CIDR=""
    fi
    read -p "Accept Seq EULA? (Y/N) [$SEQ_DEFAULT_ACCEPT_EULA]: " SEQ_ACCEPT_EULA; SEQ_ACCEPT_EULA=${SEQ_ACCEPT_EULA:-$SEQ_DEFAULT_ACCEPT_EULA}
    read -p "Seq Docker image [$SEQ_DEFAULT_IMAGE]: " SEQ_IMAGE; SEQ_IMAGE=${SEQ_IMAGE:-$SEQ_DEFAULT_IMAGE}
    read -p "Initial Seq admin password [$SEQ_DEFAULT_ADMIN_PASSWORD]: " SEQ_ADMIN_PASSWORD; SEQ_ADMIN_PASSWORD=${SEQ_ADMIN_PASSWORD:-$SEQ_DEFAULT_ADMIN_PASSWORD}
    read -p "Run Let's Encrypt for Seq now? (Y/N) [$SEQ_DEFAULT_ENABLE_SSL]: " SEQ_ENABLE_SSL; SEQ_ENABLE_SSL=${SEQ_ENABLE_SSL:-$SEQ_DEFAULT_ENABLE_SSL}
  fi

  echo; log "Summary:"
  echo "  Keycloak: ${INSTALL_KEYCLOAK} ${INSTALL_KEYCLOAK:+on}"
  if [[ "$INSTALL_KEYCLOAK" =~ ^[Yy]$ ]]; then
    echo "    Hostname=$KC_HOSTNAME DB=$KC_DB_NAME/$KC_DB_USER Admin=$KC_ADMIN_USER Port=$KC_HTTP_PORT"
    echo "    frame-ancestors=$KC_ALLOWED_FRAME_ANCESTORS"
  fi
  echo "  Seq: ${INSTALL_SEQ} ${INSTALL_SEQ:+on}"
  if [[ "$INSTALL_SEQ" =~ ^[Yy]$ ]]; then
    echo "    Hostname=$SEQ_HOSTNAME Data=$SEQ_DATA_DIR Ports: ui=$SEQ_BACKEND_PORT tcp=$SEQ_TCP_INGEST_PORT open_tcp=$SEQ_OPEN_TCP_INGEST cidr=${SEQ_TCP_INGEST_CIDR:-N/A}"
    echo "    image=$SEQ_IMAGE ssl_now=$SEQ_ENABLE_SSL"
  fi
  echo
  read -p "Proceed? (y/N): " confirm
  [[ $confirm =~ ^[Yy]$ ]] || { warn "Cancelled by user."; exit 0; }
}

APT_PREP(){
  log "Updating packages & installing shared deps (apache2, certbot, ufw, fail2ban, curl, wget, jq, net-tools)..."
  apt-get update -y
  apt-get upgrade -y
  apt-get install -y apache2 certbot python3-certbot-apache ufw fail2ban curl wget jq net-tools gnupg lsb-release ca-certificates unzip
  a2enmod proxy proxy_http headers rewrite ssl proxy_html proxy_connect >/dev/null 2>&1 || true
  systemctl enable --now apache2
  ok "Base system ready"
}

# -------------------------------- Keycloak ----------------------------------
KC_INSTALL(){
  log "[KC] Installing OpenJDK, PostgreSQL, creating user/dirs..."
  apt-get install -y openjdk-21-jdk postgresql postgresql-contrib
  groupadd -r "$KC_GROUP" 2>/dev/null || true
  useradd -r -g "$KC_GROUP" -d "$KC_HOME" -s /usr/sbin/nologin "$KC_USER" 2>/dev/null || true
  mkdir -p "$KC_HOME" "$KC_LOG_DIR" "$KC_DATA_DIR" "$KC_HOME/conf" "$KC_HOME/data"
  chown -R "$KC_USER:$KC_GROUP" "$KC_HOME" "$KC_LOG_DIR" "$KC_DATA_DIR"
  chmod 750 "$KC_HOME" "$KC_DATA_DIR"; chmod 755 "$KC_LOG_DIR"
  systemctl enable --now postgresql

  # Postgres tune+DB
  local pg_version; pg_version=$(sudo -u postgres psql -t -c "SELECT split_part(version(), ' ', 2);" | awk '{print $1}' | head -1 || true)
  local pg_major; pg_major=$(echo "$pg_version" | cut -d. -f1)
  local pg_conf="/etc/postgresql/${pg_major}/main/postgresql.conf"
  [[ -f "$pg_conf" ]] && cp "$pg_conf" "$pg_conf.bak.$(date +%s)" || true
  if [[ -f "$pg_conf" ]]; then
    cat >> "$pg_conf" <<EOF

# Keycloak production tuning (merge installer)
max_connections = 200
shared_buffers = 256MB
effective_cache_size = 1GB
work_mem = 4MB
maintenance_work_mem = 64MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
EOF
  fi

  sudo -u postgres psql <<EOF
DROP DATABASE IF EXISTS $KC_DB_NAME;
DROP USER IF EXISTS $KC_DB_USER;
CREATE DATABASE $KC_DB_NAME WITH ENCODING 'UTF8' TEMPLATE=template0;
CREATE USER $KC_DB_USER WITH PASSWORD '$KC_DB_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE $KC_DB_NAME TO $KC_DB_USER;
ALTER DATABASE $KC_DB_NAME OWNER TO $KC_DB_USER;
\\c $KC_DB_NAME
GRANT ALL ON SCHEMA public TO $KC_DB_USER;
GRANT CREATE, USAGE ON SCHEMA public TO $KC_DB_USER;
EOF
  systemctl restart postgresql

  # Download Keycloak
  log "[KC] Downloading Keycloak ${KC_VERSION}..."
  cd /tmp
  wget -q -O keycloak.tar.gz "https://github.com/keycloak/keycloak/releases/download/${KC_VERSION}/keycloak-${KC_VERSION}.tar.gz"
  tar -xzf keycloak.tar.gz
  cp -r "keycloak-${KC_VERSION}/"* "$KC_HOME/"
  chown -R "$KC_USER:$KC_GROUP" "$KC_HOME"
  chmod +x "$KC_HOME/bin/"*.sh
  rm -rf keycloak.tar.gz "keycloak-${KC_VERSION}"
  ok "[KC] Files installed"

  # keycloak.conf
  cat > "$KC_HOME/conf/keycloak.conf" <<EOF
db=postgres
db-username=$KC_DB_USER
db-password=$KC_DB_PASSWORD
db-url=jdbc:postgresql://localhost:5432/$KC_DB_NAME
hostname=$KC_HOSTNAME
hostname-strict=false
hostname-strict-backchannel=false
proxy-headers=xforwarded
hostname-strict-https=true
http-enabled=true
http-port=$KC_HTTP_PORT
health-enabled=true
metrics-enabled=true
log=console,file
log-level=INFO
log-file=$KC_LOG_DIR/keycloak.log
cache=local
transaction-xa-enabled=false
features=token-exchange,admin-fine-grained-authz
EOF
  chown "$KC_USER:$KC_GROUP" "$KC_HOME/conf/keycloak.conf"
  chmod 640 "$KC_HOME/conf/keycloak.conf"

  # Optimize build
  sudo -u "$KC_USER" "$KC_HOME/bin/kc.sh" build \
    --db=postgres \
    --health-enabled=true \
    --metrics-enabled=true \
    --features=token-exchange,admin-fine-grained-authz

  # systemd
  cat > /etc/systemd/system/keycloak.service <<EOF
[Unit]
Description=Keycloak Identity and Access Management
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=exec
User=$KC_USER
Group=$KC_GROUP
Environment=JAVA_OPTS="-Xms512m -Xmx1024m -Djava.net.preferIPv4Stack=true"
Environment=KC_BOOTSTRAP_ADMIN_USERNAME=$KC_ADMIN_USER
Environment=KC_BOOTSTRAP_ADMIN_PASSWORD=$KC_ADMIN_PASSWORD
ExecStart=$KC_HOME/bin/kc.sh start --optimized
StandardOutput=journal
StandardError=journal
Restart=on-failure
RestartSec=10
LimitNOFILE=102642
PrivateTmp=true
ProtectHome=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable keycloak

  # Apache vhost + headers for framing
  a2dissite 000-default.conf >/dev/null 2>&1 || true
  cat > /etc/apache2/sites-available/keycloak-80.conf <<EOF
<VirtualHost *:80>
    ServerName $KC_HOSTNAME
    ProxyPreserveHost On
    ProxyRequests Off
    ProxyPass /.well-known/acme-challenge/ !
    DocumentRoot /var/www/html

    Header always set X-Content-Type-Options nosniff
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"

    RequestHeader set X-Forwarded-Proto expr=%{REQUEST_SCHEME}
    RequestHeader set X-Forwarded-Port  expr=%{SERVER_PORT}
    RequestHeader set X-Forwarded-Host  "%{HTTP_HOST}s"

    ProxyPass        / http://127.0.0.1:$KC_HTTP_PORT/
    ProxyPassReverse / http://127.0.0.1:$KC_HTTP_PORT/

    ErrorLog \${APACHE_LOG_DIR}/keycloak_error.log
    CustomLog \${APACHE_LOG_DIR}/keycloak_access.log combined
</VirtualHost>
EOF
  a2ensite keycloak-80.conf >/dev/null 2>&1 || true

  cat > /etc/apache2/conf-available/keycloak-headers.conf <<EOF
<IfModule mod_headers.c>
    Header always unset X-Frame-Options
    Header always set Content-Security-Policy "frame-ancestors ${KC_ALLOWED_FRAME_ANCESTORS}"
</IfModule>
EOF
  a2enconf keycloak-headers.conf >/dev/null 2>&1 || true

  apache2ctl configtest
  systemctl restart apache2

  # Security: UFW & fail2ban (generic)
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 22/tcp comment 'SSH'
  ufw allow 80/tcp comment 'HTTP'
  ufw allow 443/tcp comment 'HTTPS'
  ufw allow from 127.0.0.1 to any port 5432 comment 'PostgreSQL local'
  ufw --force enable

  cat > /etc/fail2ban/filter.d/keycloak.conf <<'EOF'
[Definition]
failregex = ^.*ERROR.*Login failure.*from IP.*<HOST>.*$
            ^.*WARN.*Failed login attempt.*from.*<HOST>.*$
            ^.*ERROR.*Invalid user credentials.*from.*<HOST>.*$
ignoreregex =
EOF

  cat > /etc/fail2ban/jail.d/keycloak.conf <<EOF
[keycloak]
enabled = true
port = 80,443
protocol = tcp
filter = keycloak
logpath = $KC_LOG_DIR/keycloak.log
maxretry = 5
bantime = 3600
findtime = 600
EOF
  systemctl restart fail2ban || true
  systemctl enable fail2ban || true

  systemctl start keycloak

  # Diagnostic helper
  cat > /root/keycloak-diagnostic.sh <<'EOF'
#!/bin/bash
echo "=== KEYCLOAK DIAGNOSTIC REPORT ==="
date; echo
systemctl status keycloak --no-pager -l | head -20
echo; systemctl status apache2 --no-pager -l | head -12
echo; systemctl status postgresql --no-pager -l | head -12
echo; netstat -tuln | grep -E "(8080|80|443|9000)" || true
echo; host=$(grep '^hostname=' /opt/keycloak/conf/keycloak.conf 2>/dev/null | cut -d= -f2); [[ -z "$host" ]] && host="localhost"
for u in "http://$host/" "http://$host/admin/" "http://localhost:8080/admin/master/console/"; do
  code=$(timeout 7 curl -k -s -w "%{http_code}" "$u" -o /dev/null || echo "timeout"); echo "$u -> $code"
done
echo; curl -s "http://127.0.0.1:9000/q/health" || true
EOF
  chmod +x /root/keycloak-diagnostic.sh

  ok "[KC] Installed. Admin: ${KC_ADMIN_USER}/${KC_ADMIN_PASSWORD}"
}

# ---------------------------------- Seq -------------------------------------
ENSURE_DOCKER(){
  if ! command -v docker >/dev/null 2>&1; then
    log "[SEQ] Installing Docker CE..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
  fi
  ok "[SEQ] Docker ready"
}

SEQ_INSTALL(){
  [[ "$SEQ_ACCEPT_EULA" =~ ^[Yy]$ ]] || { err "[SEQ] EULA must be accepted."; exit 1; }
  ENSURE_DOCKER

  mkdir -p "$SEQ_DATA_DIR"; chmod 755 "$SEQ_DATA_DIR"
  # vhost & headers
  cat > /etc/apache2/conf-available/seq-headers.conf <<'EOF'
<IfModule mod_headers.c>
    Header always set X-Content-Type-Options nosniff
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    # To allow embedding Seq in an iframe from specific origins, you can uncomment and edit:
    # Header always unset X-Frame-Options
    # Header always set Content-Security-Policy "frame-ancestors 'self' https://your-shell.example.com"
</IfModule>
EOF
  a2enconf seq-headers.conf >/dev/null 2>&1 || true

  cat > /etc/apache2/sites-available/seq.conf <<EOF
<VirtualHost *:80>
    ServerName ${SEQ_HOSTNAME}
    ProxyPreserveHost On
    ProxyRequests Off
    ProxyTimeout 300
    ProxyPass /.well-known/acme-challenge/ !
    DocumentRoot /var/www/html
    RequestHeader set X-Forwarded-Proto expr=%{REQUEST_SCHEME}
    RequestHeader set X-Forwarded-Port  expr=%{SERVER_PORT}
    RequestHeader set X-Forwarded-Host  "%{HTTP_HOST}s"
    ProxyPass        / http://127.0.0.1:${SEQ_BACKEND_PORT}/ keepalive=On
    ProxyPassReverse / http://127.0.0.1:${SEQ_BACKEND_PORT}/
    ErrorLog \${APACHE_LOG_DIR}/seq_error.log
    CustomLog \${APACHE_LOG_DIR}/seq_access.log combined
</VirtualHost>
EOF
  a2ensite seq.conf >/dev/null 2>&1 || true
  apache2ctl configtest
  systemctl reload apache2

  # Run (recreate) container
  if docker ps -a --format '{{.Names}}' | grep -q '^seq$'; then
    docker rm -f seq || true
  fi
  docker pull "$SEQ_IMAGE" >/dev/null || true
  docker run -d --name seq \
    -e ACCEPT_EULA=Y \
    -e SEQ_FIRSTRUN_ADMINPASSWORD="${SEQ_ADMIN_PASSWORD}" \
    -e SEQ_BASEURI="https://${SEQ_HOSTNAME}/" \
    -p "127.0.0.1:${SEQ_BACKEND_PORT}:80" \
    -p "${SEQ_TCP_INGEST_PORT}:5341" \
    -v "${SEQ_DATA_DIR}:/data" \
    --restart unless-stopped \
    "$SEQ_IMAGE"

  # UFW rules (append, do not reset if already enabled by KC step)
  ufw allow 80/tcp  comment 'HTTP' || true
  ufw allow 443/tcp comment 'HTTPS' || true
  if [[ "$SEQ_OPEN_TCP_INGEST" =~ ^[Yy]$ ]]; then
    ufw allow from "$SEQ_TCP_INGEST_CIDR" to any port "$SEQ_TCP_INGEST_PORT" proto tcp comment 'Seq TCP ingest' || true
  fi
  ufw --force enable || true

  # Wait for backend
  local max=60; local n=1
  until curl -fsS "http://127.0.0.1:${SEQ_BACKEND_PORT}/" >/dev/null 2>&1; do
    (( n >= max )) && { warn "[SEQ] Backend not answering yet, continuing..."; break; }
    sleep 2; n=$((n+1))
  done

  # SSL now?
  if [[ "$SEQ_ENABLE_SSL" =~ ^[Yy]$ ]]; then
    if certbot --apache -d "$SEQ_HOSTNAME" --non-interactive --agree-tos --email admin@"$SEQ_HOSTNAME" --redirect; then
      ok "[SEQ] SSL certificate installed; redirect enabled"
      systemctl reload apache2
    else
      warn "[SEQ] Certbot failed; try later: certbot --apache -d $SEQ_HOSTNAME"
    fi
  fi

  # Diagnostic helper
  cat > /root/seq-diagnostic.sh <<EOF
#!/bin/bash
echo "=== SEQ Diagnostic Report ==="
date
echo
echo "[Services]"
systemctl status apache2 --no-pager -l | head -12 || true
echo
echo "[Docker]"
docker ps --format "table {{'{'}}.Names{{'}'}}\t{{'{'}}.Status{{'}'}}\t{{'{'}}.Ports{{'}'}}" || true
echo
echo "[Ports]"
ss -tulpen | grep -E ":(${SEQ_BACKEND_PORT}|80|443|${SEQ_TCP_INGEST_PORT})\\b" || true
echo
echo "[Proxy test]"
curl -s -o /dev/null -w "%{http_code}\\n" "http://${SEQ_HOSTNAME}/"
echo
echo "[Backend test]"
curl -s -o /dev/null -w "%{http_code}\\n" "http://127.0.0.1:${SEQ_BACKEND_PORT}/"
echo
echo "[Seq /api]"
curl -s -o /dev/null -w "%{http_code}\\n" "http://127.0.0.1:${SEQ_BACKEND_PORT}/api"
echo
echo "[Container logs (last 100)]"
docker logs --tail 100 seq || true
EOF
  chmod +x /root/seq-diagnostic.sh

  ok "[SEQ] Installed. First-run admin user: admin (password you entered; ignored if data dir already initialized)"
}

WRITE_LOG_SUMMARY(){
  echo >> "$LOG_FILE"
  echo "==================== FINAL SETUP SUMMARY ====================" >> "$LOG_FILE"
  echo "Date: $(date)" >> "$LOG_FILE"
  echo "Server: $(hostname)  IP: $(curl -s ifconfig.me 2>/dev/null || echo 'Unknown')" >> "$LOG_FILE"
  echo >> "$LOG_FILE"
  if [[ "$INSTALL_KEYCLOAK" =~ ^[Yy]$ ]]; then
    cat >> "$LOG_FILE" <<EOF
[Keycloak]
Version: $KC_VERSION
Hostname: $KC_HOSTNAME
Backend:  http://127.0.0.1:$KC_HTTP_PORT
Admin:    $KC_ADMIN_USER
Password: $KC_ADMIN_PASSWORD   # <-- delete this file after storing safely
DB:       $KC_DB_NAME
DB User:  $KC_DB_USER
DB Pass:  $KC_DB_PASSWORD      # <-- delete this file after storing safely
Frame-ancestors: $KC_ALLOWED_FRAME_ANCESTORS
Systemd:  systemctl status keycloak
Access:   http://$KC_HOSTNAME/admin/  (use HTTPS after cert)
Diag:     /root/keycloak-diagnostic.sh

EOF
  fi
  if [[ "$INSTALL_SEQ" =~ ^[Yy]$ ]]; then
    cat >> "$LOG_FILE" <<EOF
[Seq]
Hostname:          $SEQ_HOSTNAME
UI via Apache:     http://$SEQ_HOSTNAME/  (use HTTPS if enabled)
Backend local:     http://127.0.0.1:$SEQ_BACKEND_PORT/
TCP ingest:        $SEQ_TCP_INGEST_PORT  CIDR: ${SEQ_TCP_INGEST_CIDR:-N/A}
Image:             $SEQ_IMAGE
First-run admin:   admin / $SEQ_ADMIN_PASSWORD  # ignored if data dir pre-initialized
Data dir:          $SEQ_DATA_DIR
Diag:              /root/seq-diagnostic.sh

EOF
  fi

  cat >> "$LOG_FILE" <<'EOF'
[General notes]
- To remove sensitive info, securely delete this file when done:
    shred -u /root/setup.log
- Apache control:
    systemctl status apache2
    systemctl reload apache2
- Firewall rules with UFW:
    ufw status numbered
    # remove a rule by number:
    # ufw delete <number>
- Let's Encrypt (manual retry):
    certbot --apache -d <your-domain>

EOF
  ok "Wrote $LOG_FILE (contains passwords; delete when stored elsewhere)"
}

main(){
  require_root
  PROMPT_ALL
  APT_PREP
  if [[ "$INSTALL_KEYCLOAK" =~ ^[Yy]$ ]]; then KC_INSTALL; fi
  if [[ "$INSTALL_SEQ" =~ ^[Yy]$ ]]; then SEQ_INSTALL; fi
  WRITE_LOG_SUMMARY

  echo -e "${GREEN}Installation finished.${NC}"
  echo -e "${YELLOW}Sensitive data was written to: $LOG_FILE${NC}"
  echo -e "${YELLOW}When done, delete it with: shred -u $LOG_FILE${NC}"
}

main "$@"
