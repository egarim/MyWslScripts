#!/bin/bash
# Merge Installer: Webmin + Seq + Keycloak (Ubuntu 22.04+)
# - Single, consolidated script
# - Prompts once (no redundant questions)
# - Writes /root/setup.log with ALL collected details (incl. passwords)
# - Provides diagnostic helpers
# - Handles Apache reverse proxy, UFW, Fail2ban, SSL via Let's Encrypt
# Author: Merge Linux
# Version: 1.0 (2025-08-18)
set -euo pipefail

############################################
# Styling / logging
############################################
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log(){ echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
ok(){ echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] OK:${NC} $1"; }
warn(){ echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $1"; }
err(){ echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"; }

check_root(){ [[ $EUID -eq 0 ]] || { err "Run as root"; exit 1; }; }

############################################
# Defaults
############################################
# Global
DEFAULT_ACME_EMAIL="admin@vmi2711131.contaboserver.net"

# Webmin
DEFAULT_WEBMIN_DOMAIN="webmin.sivargpt.com"
DEFAULT_WEBMIN_PROXY="Y"
DEFAULT_WEBMIN_SSL="Y"
DEFAULT_WEBMIN_UFW="Y"

# Seq
DEFAULT_SEQ_DOMAIN="logs.sivargpt.com"
DEFAULT_SEQ_DATA_DIR="/var/lib/seq"
DEFAULT_SEQ_BACKEND_PORT="5342"     # host -> container 80
DEFAULT_SEQ_TCP_PORT="5341"         # host -> container 5341
DEFAULT_SEQ_OPEN_TCP="N"
DEFAULT_SEQ_TCP_CIDR="10.0.0.0/24"
DEFAULT_SEQ_ACCEPT_EULA="Y"
DEFAULT_SEQ_IMAGE="datalust/seq:latest"
DEFAULT_SEQ_ADMIN_PASSWORD="ChangeMe!123"
DEFAULT_SEQ_ENABLE_SSL="Y"

# Keycloak
DEFAULT_KC_DOMAIN="auth2.sivargpt.com"
DEFAULT_KC_HTTP_PORT="8080"
DEFAULT_KC_DB_NAME="keycloak_prod"
DEFAULT_KC_DB_USER="keycloak_user"
DEFAULT_KC_DB_PASSWORD="1234567890"
DEFAULT_KC_ADMIN_USER="keycloakadmin"
DEFAULT_KC_ADMIN_PASSWORD="1234567890"
DEFAULT_KC_ALLOWED_FRAME_ANCESTORS="'self' https://webmin.sivargpt.com https://logs.sivargpt.com"

############################################
# Runtime (will be filled from prompts)
############################################
ACME_EMAIL=""
WEBMIN_DOMAIN=""
WEBMIN_PROXY=""
WEBMIN_SSL=""
WEBMIN_UFW=""
SEQ_DOMAIN=""
SEQ_DATA_DIR=""
SEQ_BACKEND_PORT=""
SEQ_TCP_PORT=""
SEQ_OPEN_TCP=""
SEQ_TCP_CIDR=""
SEQ_ACCEPT_EULA=""
SEQ_IMAGE=""
SEQ_ADMIN_PASSWORD=""
SEQ_ENABLE_SSL=""
KC_DOMAIN=""
KC_HTTP_PORT=""
KC_DB_NAME=""
KC_DB_USER=""
KC_DB_PASSWORD=""
KC_ADMIN_USER=""
KC_ADMIN_PASSWORD=""
KC_ALLOWED_FRAME_ANCESTORS=""

############################################
# Prompts
############################################
prompt_all(){
  echo
  log "=== Merge Installer Configuration (Webmin + Seq + Keycloak) ==="
  echo -e "${YELLOW}Press Enter to accept defaults in [brackets]${NC}"
  echo

  # Global
  read -p "ACME email for TLS [$DEFAULT_ACME_EMAIL]: " ACME_EMAIL; ACME_EMAIL=${ACME_EMAIL:-$DEFAULT_ACME_EMAIL}

  # Webmin
  echo; log "— Webmin —"
  read -p "Public domain for Webmin [$DEFAULT_WEBMIN_DOMAIN]: " WEBMIN_DOMAIN; WEBMIN_DOMAIN=${WEBMIN_DOMAIN:-$DEFAULT_WEBMIN_DOMAIN}
  read -p "Proxy Webmin via Apache? (Y/N) [$DEFAULT_WEBMIN_PROXY]: " WEBMIN_PROXY; WEBMIN_PROXY=${WEBMIN_PROXY:-$DEFAULT_WEBMIN_PROXY}
  if [[ "$WEBMIN_PROXY" =~ ^[Yy]$ ]]; then
    read -p "Obtain Let's Encrypt for Webmin now? (Y/N) [$DEFAULT_WEBMIN_SSL]: " WEBMIN_SSL; WEBMIN_SSL=${WEBMIN_SSL:-$DEFAULT_WEBMIN_SSL}
  else
    WEBMIN_SSL="N"
  fi
  read -p "Enable/adjust UFW firewall? (Y/N) [$DEFAULT_WEBMIN_UFW]: " WEBMIN_UFW; WEBMIN_UFW=${WEBMIN_UFW:-$DEFAULT_WEBMIN_UFW}

  # Seq
  echo; log "— Seq —"
  read -p "Public domain for Seq [$DEFAULT_SEQ_DOMAIN]: " SEQ_DOMAIN; SEQ_DOMAIN=${SEQ_DOMAIN:-$DEFAULT_SEQ_DOMAIN}
  read -p "Seq data directory [$DEFAULT_SEQ_DATA_DIR]: " SEQ_DATA_DIR; SEQ_DATA_DIR=${SEQ_DATA_DIR:-$DEFAULT_SEQ_DATA_DIR}
  read -p "Seq backend HTTP port (host->container:80) [$DEFAULT_SEQ_BACKEND_PORT]: " SEQ_BACKEND_PORT; SEQ_BACKEND_PORT=${SEQ_BACKEND_PORT:-$DEFAULT_SEQ_BACKEND_PORT}
  read -p "Seq TCP ingest port (host->container:5341) [$DEFAULT_SEQ_TCP_PORT]: " SEQ_TCP_PORT; SEQ_TCP_PORT=${SEQ_TCP_PORT:-$DEFAULT_SEQ_TCP_PORT}
  read -p "Open TCP ingest to a CIDR? (Y/N) [$DEFAULT_SEQ_OPEN_TCP]: " SEQ_OPEN_TCP; SEQ_OPEN_TCP=${SEQ_OPEN_TCP:-$DEFAULT_SEQ_OPEN_TCP}
  if [[ "$SEQ_OPEN_TCP" =~ ^[Yy]$ ]]; then
    read -p "CIDR allowed for TCP ingest [$DEFAULT_SEQ_TCP_CIDR]: " SEQ_TCP_CIDR; SEQ_TCP_CIDR=${SEQ_TCP_CIDR:-$DEFAULT_SEQ_TCP_CIDR}
  else
    SEQ_TCP_CIDR=""
  fi
  read -p "Accept Seq EULA? (Y/N) [$DEFAULT_SEQ_ACCEPT_EULA]: " SEQ_ACCEPT_EULA; SEQ_ACCEPT_EULA=${SEQ_ACCEPT_EULA:-$DEFAULT_SEQ_ACCEPT_EULA}
  read -p "Docker image for Seq [$DEFAULT_SEQ_IMAGE]: " SEQ_IMAGE; SEQ_IMAGE=${SEQ_IMAGE:-$DEFAULT_SEQ_IMAGE}
  read -p "Seq initial admin password (first run) [$DEFAULT_SEQ_ADMIN_PASSWORD]: " SEQ_ADMIN_PASSWORD; SEQ_ADMIN_PASSWORD=${SEQ_ADMIN_PASSWORD:-$DEFAULT_SEQ_ADMIN_PASSWORD}
  read -p "Obtain Let's Encrypt for Seq now? (Y/N) [$DEFAULT_SEQ_ENABLE_SSL]: " SEQ_ENABLE_SSL; SEQ_ENABLE_SSL=${SEQ_ENABLE_SSL:-$DEFAULT_SEQ_ENABLE_SSL}

  # Keycloak
  echo; log "— Keycloak —"
  read -p "Public domain for Keycloak [$DEFAULT_KC_DOMAIN]: " KC_DOMAIN; KC_DOMAIN=${KC_DOMAIN:-$DEFAULT_KC_DOMAIN}
  read -p "Keycloak backend HTTP port [$DEFAULT_KC_HTTP_PORT]: " KC_HTTP_PORT; KC_HTTP_PORT=${KC_HTTP_PORT:-$DEFAULT_KC_HTTP_PORT}
  read -p "Keycloak DB name [$DEFAULT_KC_DB_NAME]: " KC_DB_NAME; KC_DB_NAME=${KC_DB_NAME:-$DEFAULT_KC_DB_NAME}
  read -p "Keycloak DB user [$DEFAULT_KC_DB_USER]: " KC_DB_USER; KC_DB_USER=${KC_DB_USER:-$DEFAULT_KC_DB_USER}
  read -p "Keycloak DB password [$DEFAULT_KC_DB_PASSWORD]: " KC_DB_PASSWORD; KC_DB_PASSWORD=${KC_DB_PASSWORD:-$DEFAULT_KC_DB_PASSWORD}
  read -p "Keycloak admin username [$DEFAULT_KC_ADMIN_USER]: " KC_ADMIN_USER; KC_ADMIN_USER=${KC_ADMIN_USER:-$DEFAULT_KC_ADMIN_USER}
  read -p "Keycloak admin password [$DEFAULT_KC_ADMIN_PASSWORD]: " KC_ADMIN_PASSWORD; KC_ADMIN_PASSWORD=${KC_ADMIN_PASSWORD:-$DEFAULT_KC_ADMIN_PASSWORD}
  read -p "Allowed frame-ancestors for Keycloak CSP [$DEFAULT_KC_ALLOWED_FRAME_ANCESTORS]: " KC_ALLOWED_FRAME_ANCESTORS; KC_ALLOWED_FRAME_ANCESTORS=${KC_ALLOWED_FRAME_ANCESTORS:-$DEFAULT_KC_ALLOWED_FRAME_ANCESTORS}

  echo
  log "Summary:"
  echo "  ACME email:        $ACME_EMAIL"
  echo "  WEBMIN domain:     $WEBMIN_DOMAIN  (proxy: $WEBMIN_PROXY, ssl: $WEBMIN_SSL, ufw: $WEBMIN_UFW)"
  echo "  SEQ domain:        $SEQ_DOMAIN     (backend:$SEQ_BACKEND_PORT tcp:$SEQ_TCP_PORT open:$SEQ_OPEN_TCP ${SEQ_TCP_CIDR:+cidr:$SEQ_TCP_CIDR})"
  echo "  KEYCLOAK domain:   $KC_DOMAIN      (http:$KC_HTTP_PORT)"
  echo "  KC DB:             $KC_DB_NAME / $KC_DB_USER"
  echo "  KC frame-ancestors:$KC_ALLOWED_FRAME_ANCESTORS"
  echo
  read -p "Continue with installation? (y/N): " confirm
  [[ $confirm =~ ^[Yy]$ ]] || { log "Cancelled."; exit 0; }
}

############################################
# System preparation
############################################
update_system(){ log "Updating apt …"; apt-get update -y && apt-get upgrade -y; ok "System updated"; }

ensure_base(){
  log "Installing base packages …"
  apt-get install -y ca-certificates curl gnupg lsb-release software-properties-common ufw fail2ban jq net-tools unzip wget openssl
  ok "Base packages installed"
}

ensure_apache(){
  if command -v apache2 >/dev/null 2>&1; then
    ok "Apache found"
  else
    log "Installing Apache …"
    apt-get install -y apache2
    systemctl enable --now apache2
    ok "Apache installed"
  fi
  a2enmod proxy proxy_http proxy_html headers rewrite ssl status >/dev/null 2>&1 || true
}

ensure_certbot(){
  apt-get install -y certbot python3-certbot-apache >/dev/null 2>&1 || true
}

############################################
# Webmin (proxied via Apache)
############################################
install_webmin_repo(){
  log "Adding Webmin repository …"
  curl -fsSL http://www.webmin.com/jcameron-key.asc | gpg --dearmor -o /usr/share/keyrings/webmin.gpg
  echo "deb [signed-by=/usr/share/keyrings/webmin.gpg] http://download.webmin.com/download/repository sarge contrib" > /etc/apt/sources.list.d/webmin.list
  apt-get update -y
}

install_webmin(){
  log "Installing Webmin …"
  DEBIAN_FRONTEND=noninteractive apt-get install -y webmin
  systemctl enable --now webmin || true
  ok "Webmin installed"
}

configure_webmin_proxy(){
  # Bind to loopback + SSL; fix redirects and referrers
  local conf="/etc/webmin/miniserv.conf"
  local cfg="/etc/webmin/config"
  grep -q '^bind=' "$conf" && sed -i 's/^bind=.*/bind=127.0.0.1/' "$conf" || echo "bind=127.0.0.1" >> "$conf"
  grep -q '^port=' "$conf" && sed -i 's/^port=.*/port=10000/' "$conf" || echo "port=10000" >> "$conf"
  grep -q '^listen=' "$conf" && sed -i 's/^listen=.*/listen=10000/' "$conf" || echo "listen=10000" >> "$conf"
  grep -q '^ssl=' "$conf" && sed -i 's/^ssl=.*/ssl=1/' "$conf" || echo "ssl=1" >> "$conf"
  sed -i 's/^webprefixnoredir=.*/webprefixnoredir=1/; t; $ a webprefixnoredir=1' "$cfg" || true
  if grep -q '^referers=' "$cfg"; then sed -i "s/^referers=.*/referers=${WEBMIN_DOMAIN}/" "$cfg"; else echo "referers=${WEBMIN_DOMAIN}" >> "$cfg"; fi
  if grep -q '^redirect_host=' "$conf" 2>/dev/null; then sed -i "s/^redirect_host=.*/redirect_host=${WEBMIN_DOMAIN}/" "$conf"; else echo "redirect_host=${WEBMIN_DOMAIN}" >> "$conf"; fi
  systemctl restart webmin || true

  # Apache vhost (80) with ACME passthrough and proxy to backend https://127.0.0.1:10000
  cat > /etc/apache2/sites-available/webmin.conf <<EOF
<VirtualHost *:80>
    ServerName ${WEBMIN_DOMAIN}
    ProxyPreserveHost On
    ProxyRequests Off
    ProxyTimeout 300
    ProxyPass /.well-known/acme-challenge/ !
    DocumentRoot /var/www/html
    RequestHeader set X-Forwarded-Proto expr=%{REQUEST_SCHEME}
    RequestHeader set X-Forwarded-Port  expr=%{SERVER_PORT}
    RequestHeader set X-Forwarded-Host  "%{HTTP_HOST}s"
    SSLProxyEngine On
    SSLProxyVerify none
    SSLProxyCheckPeerName off
    SSLProxyCheckPeerCN off
    SSLProxyCheckPeerExpire off
    ProxyPass        / https://127.0.0.1:10000/
    ProxyPassReverse / https://127.0.0.1:10000/
    ProxyPassReverseCookieDomain 127.0.0.1 ${WEBMIN_DOMAIN}
    ProxyPassReverseCookiePath / /
    ErrorLog \${APACHE_LOG_DIR}/webmin_error.log
    CustomLog \${APACHE_LOG_DIR}/webmin_access.log combined
</VirtualHost>
EOF
  a2ensite webmin.conf >/dev/null 2>&1 || true
  apache2ctl configtest && systemctl reload apache2
  ok "Webmin proxied via Apache"
}

webmin_ssl(){
  if [[ "$WEBMIN_PROXY" =~ ^[Yy]$ && "$WEBMIN_SSL" =~ ^[Yy]$ ]]; then
    ensure_certbot
    certbot --apache -d "$WEBMIN_DOMAIN" --non-interactive --agree-tos --email "$ACME_EMAIL" --redirect || true
    ok "Webmin SSL processed (or already valid)"
  else
    warn "Skipping Webmin SSL"
  fi
}

############################################
# Seq (Docker + Apache reverse proxy)
############################################
ensure_docker(){
  if command -v docker >/dev/null 2>&1; then ok "Docker present"; return; fi
  log "Installing Docker CE …"
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
}

seq_prepare_dirs(){
  mkdir -p "$SEQ_DATA_DIR"
  chown root:root "$SEQ_DATA_DIR"
  chmod 755 "$SEQ_DATA_DIR"
}

seq_run_container(){
  [[ "$SEQ_ACCEPT_EULA" =~ ^[Yy]$ ]] || { err "Seq EULA must be accepted"; exit 1; }
  docker ps -a --format '{{.Names}}' | grep -q '^seq$' && { warn "Removing existing 'seq' container"; docker rm -f seq || true; }
  docker pull "$SEQ_IMAGE" >/dev/null || true
  docker run -d --name seq \
    -e ACCEPT_EULA=Y \
    -e SEQ_FIRSTRUN_ADMINPASSWORD="${SEQ_ADMIN_PASSWORD}" \
    -e SEQ_BASEURI="https://${SEQ_DOMAIN}/" \
    -p "127.0.0.1:${SEQ_BACKEND_PORT}:80" \
    -p "${SEQ_TCP_PORT}:5341" \
    -v "${SEQ_DATA_DIR}:/data" \
    --restart unless-stopped \
    "$SEQ_IMAGE"
  ok "Seq container started"
}

seq_apache_vhost(){
  cat > /etc/apache2/sites-available/seq.conf <<EOF
<VirtualHost *:80>
    ServerName ${SEQ_DOMAIN}
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
  apache2ctl configtest && systemctl reload apache2
  ok "Seq vhost enabled"
}

seq_ssl(){
  if [[ "$SEQ_ENABLE_SSL" =~ ^[Yy]$ ]]; then
    ensure_certbot
    certbot --apache -d "$SEQ_DOMAIN" --non-interactive --agree-tos --email "$ACME_EMAIL" --redirect || true
    ok "Seq SSL processed (or already valid)"
  else
    warn "Skipping Seq SSL"
  fi
}

############################################
# Keycloak (systemd + Apache reverse proxy + PostgreSQL)
############################################
kc_install_dependencies(){
  apt-get install -y openjdk-21-jdk postgresql postgresql-contrib
  a2enmod proxy_ajp deflate proxy_balancer proxy_connect >/dev/null 2>&1 || true
}

kc_setup_postgresql(){
  systemctl enable --now postgresql
  local pg_version=$(sudo -u postgres psql -t -c "SELECT split_part(version(), ' ', 2);" | awk '{print $1}' | head -1 || true)
  local pg_major=$(echo "$pg_version" | cut -d. -f1)
  local pg_conf="/etc/postgresql/${pg_major}/main/postgresql.conf"
  if [[ -f "$pg_conf" ]]; then
    cp "$pg_conf" "$pg_conf.backup" 2>/dev/null || true
    cat >> "$pg_conf" <<EOF

# Keycloak Production Tuning
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
DROP DATABASE IF EXISTS ${KC_DB_NAME};
DROP USER IF EXISTS ${KC_DB_USER};
CREATE DATABASE ${KC_DB_NAME} WITH ENCODING 'UTF8' LC_COLLATE='en_US.UTF-8' LC_CTYPE='en_US.UTF-8' TEMPLATE=template0;
CREATE USER ${KC_DB_USER} WITH PASSWORD '${KC_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON DATABASE ${KC_DB_NAME} TO ${KC_DB_USER};
ALTER DATABASE ${KC_DB_NAME} OWNER TO ${KC_DB_USER};
\c ${KC_DB_NAME}
GRANT ALL ON SCHEMA public TO ${KC_DB_USER};
GRANT CREATE, USAGE ON SCHEMA public TO ${KC_DB_USER};
EOF
  systemctl restart postgresql
  ok "PostgreSQL ready for Keycloak"
}

kc_setup_user_dirs(){
  local KC_USER="keycloak"; local KC_GROUP="keycloak"
  local KC_HOME="/opt/keycloak"; local KC_LOG_DIR="/var/log/keycloak"; local KC_DATA_DIR="/var/lib/keycloak"
  groupadd -r $KC_GROUP 2>/dev/null || true
  useradd -r -g $KC_GROUP -d $KC_HOME -s /usr/sbin/nologin $KC_USER 2>/dev/null || true
  mkdir -p $KC_HOME $KC_LOG_DIR $KC_DATA_DIR $KC_HOME/conf $KC_HOME/data
  chown -R $KC_USER:$KC_GROUP $KC_HOME $KC_LOG_DIR $KC_DATA_DIR
  chmod 750 $KC_HOME $KC_DATA_DIR; chmod 755 $KC_LOG_DIR
}

kc_install_binary(){
  local KC_USER="keycloak"; local KC_HOME="/opt/keycloak"
  local VERSION="26.3.1"
  cd /tmp
  local url="https://github.com/keycloak/keycloak/releases/download/${VERSION}/keycloak-${VERSION}.tar.gz"
  local max=3; local n=1
  while (( n <= max )); do
    if wget -O keycloak.tar.gz "$url"; then break; fi
    (( n == max )) && { err "Failed to download Keycloak"; exit 1; }
    warn "Retrying Keycloak download ($n/$max)…"; n=$((n+1)); sleep 5
  done
  tar -xzf keycloak.tar.gz
  cp -r keycloak-${VERSION}/* $KC_HOME/
  chown -R $KC_USER:$KC_USER $KC_HOME
  chmod +x $KC_HOME/bin/*.sh
  rm -rf keycloak.tar.gz keycloak-${VERSION}
  ok "Keycloak installed to $KC_HOME"
}

kc_write_config_and_build(){
  local KC_USER="keycloak"; local KC_HOME="/opt/keycloak"; local KC_LOG_DIR="/var/log/keycloak"
  cat > $KC_HOME/conf/keycloak.conf <<EOF
db=postgres
db-username=${KC_DB_USER}
db-password=${KC_DB_PASSWORD}
db-url=jdbc:postgresql://localhost:5432/${KC_DB_NAME}
db-pool-initial-size=5
db-pool-min-size=5
db-pool-max-size=20
hostname=${KC_DOMAIN}
hostname-strict=false
hostname-strict-backchannel=false
proxy-headers=xforwarded
hostname-strict-https=true
http-enabled=true
http-port=${KC_HTTP_PORT}
health-enabled=true
metrics-enabled=true
log=console,file
log-level=INFO
log-file=${KC_LOG_DIR}/keycloak.log
cache=local
transaction-xa-enabled=false
features=token-exchange,admin-fine-grained-authz
EOF
  chown keycloak:keycloak $KC_HOME/conf/keycloak.conf
  chmod 640 $KC_HOME/conf/keycloak.conf
  sudo -u $KC_USER $KC_HOME/bin/kc.sh build --db=postgres --health-enabled=true --metrics-enabled=true --features=token-exchange,admin-fine-grained-authz
  ok "Keycloak built"
}

kc_systemd_service(){
  cat > /etc/systemd/system/keycloak.service <<EOF
[Unit]
Description=Keycloak Identity and Access Management
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=exec
User=keycloak
Group=keycloak
Environment=JAVA_OPTS="-Xms512m -Xmx1024m -Djava.net.preferIPv4Stack=true"
Environment=KC_BOOTSTRAP_ADMIN_USERNAME=${KC_ADMIN_USER}
Environment=KC_BOOTSTRAP_ADMIN_PASSWORD=${KC_ADMIN_PASSWORD}
ExecStart=/opt/keycloak/bin/kc.sh start --optimized
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
  ok "Keycloak systemd service installed"
}

kc_apache_vhosts(){
  # Port 80 vhost with ACME and proxy to backend http
  cat > /etc/apache2/sites-available/keycloak-80.conf <<EOF
<VirtualHost *:80>
    ServerName ${KC_DOMAIN}
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
    ProxyPass        / http://127.0.0.1:${KC_HTTP_PORT}/
    ProxyPassReverse / http://127.0.0.1:${KC_HTTP_PORT}/
    ErrorLog \${APACHE_LOG_DIR}/keycloak_error.log
    CustomLog \${APACHE_LOG_DIR}/keycloak_access.log combined
</VirtualHost>
EOF
  a2ensite keycloak-80.conf >/dev/null 2>&1 || true

  # Global header conf: allow controlled framing via CSP and unset X-Frame-Options
  cat > /etc/apache2/conf-available/keycloak-headers.conf <<EOF
<IfModule mod_headers.c>
    Header always unset X-Frame-Options
    Header always set Content-Security-Policy "frame-ancestors ${KC_ALLOWED_FRAME_ANCESTORS}"
</IfModule>
EOF
  a2enconf keycloak-headers.conf >/dev/null 2>&1 || true

  apache2ctl configtest && systemctl reload apache2
  ok "Keycloak Apache config staged"
}

kc_ssl(){
  ensure_certbot
  if certbot --apache -d "$KC_DOMAIN" --non-interactive --agree-tos --email "$ACME_EMAIL" --redirect; then
    ok "Keycloak SSL issued; HTTP->HTTPS redirect enabled"
  else
    warn "Keycloak certbot failed; you can retry later: certbot --apache -d $KC_DOMAIN"
  fi
}

kc_start_and_check(){
  systemctl start keycloak
  log "Waiting for Keycloak to become active …"
  local max_wait=120; local waited=0
  while (( waited < max_wait )); do
    systemctl is-active --quiet keycloak && { ok "Keycloak running"; break; }
    sleep 5; waited=$((waited+5))
  done
  systemctl is-active --quiet keycloak || { err "Keycloak failed to start"; exit 1; }
}

############################################
# Security (UFW + fail2ban)
############################################
configure_ufw_global(){
  if [[ "$WEBMIN_UFW" =~ ^[Yy]$ ]]; then
    log "Configuring UFW …"
    if ! ufw status | grep -q "Status: active"; then
      ufw --force reset
      ufw default deny incoming
      ufw default allow outgoing
    fi
    ufw allow 22/tcp  comment 'SSH'
    ufw allow 80/tcp  comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    # Seq TCP ingest
    if [[ "$SEQ_OPEN_TCP" =~ ^[Yy]$ && -n "$SEQ_TCP_CIDR" ]]; then
      ufw allow from "$SEQ_TCP_CIDR" to any port "$SEQ_TCP_PORT" proto tcp comment 'Seq TCP ingest'
    fi
    # Postgres stays local; Keycloak backend is local; Webmin binds to 127.0.0.1
    ufw --force enable
    ok "UFW configured"
  else
    warn "Skipping UFW configuration"
  fi
}

enable_fail2ban(){
  systemctl enable --now fail2ban >/dev/null 2>&1 || true
  ok "fail2ban enabled"
}

############################################
# Diagnostics
############################################
write_diag_helpers(){
  cat > /root/seq-diagnostic.sh <<EOF
#!/bin/bash
echo "=== SEQ Diagnostic Report ==="
date
echo
systemctl status apache2 --no-pager -l | head -12 || true
echo
docker ps --format "table {{'Names'}}\t{{'Status'}}\t{{'Ports'}}" || true
echo
ss -tulpen | grep -E ":(${SEQ_BACKEND_PORT}|80|443|${SEQ_TCP_PORT})\\b" || true
echo
curl -s -o /dev/null -w "%{http_code}\\n" "http://${SEQ_DOMAIN}/"
curl -s -o /dev/null -w "%{http_code}\\n" "http://127.0.0.1:${SEQ_BACKEND_PORT}/"
echo
docker logs --tail 100 seq || true
EOF
  chmod +x /root/seq-diagnostic.sh

  cat > /root/webmin-diagnostic.sh <<'EOF'
#!/bin/bash
echo "=== WEBMIN Diagnostic Report ==="
date
echo
systemctl status webmin --no-pager -l | head -20 || true
echo
systemctl status apache2 --no-pager -l | head -20 || true
echo
ss -tulpen | grep -E "(:80|:443|:10000)\b" || true
echo
apache2ctl -S 2>/dev/null || true
echo
grep -E "^(port|listen|bind|ssl|redirect_host)=" /etc/webmin/miniserv.conf 2>/dev/null || true
echo
grep -E "^(webprefixnoredir|referers)=" /etc/webmin/config 2>/dev/null || true
EOF
  chmod +x /root/webmin-diagnostic.sh

  cat > /root/keycloak-diagnostic.sh <<'EOF'
#!/bin/bash
echo "=== KEYCLOAK Diagnostic Report ==="
date
echo
systemctl status keycloak --no-pager -l | head -20 || true
echo
systemctl status apache2 --no-pager -l | head -20 || true
echo
systemctl status postgresql --no-pager -l | head -20 || true
echo
ss -tulpen | grep -E "(:80|:443|:8080|:9000)\b" || true
echo
host=$(grep '^hostname=' /opt/keycloak/conf/keycloak.conf 2>/dev/null | cut -d= -f2)
[[ -z "$host" ]] && host="localhost"
for u in "http://$host/" "https://$host/" "http://localhost:8080/admin/master/console/"; do
  code=$(timeout 7 curl -k -s -o /dev/null -w "%{http_code}" "$u" || echo "timeout")
  echo "$u -> $code"
done
echo
curl -s "http://localhost:9000/q/health" || true
EOF
  chmod +x /root/keycloak-diagnostic.sh
}

############################################
# Setup log writer
############################################
write_setup_log(){
  local LOG="/root/setup.log"
  local IP=$(curl -s ifconfig.me 2>/dev/null || echo "Unknown")
  {
    echo "=== MERGE INSTALL SETUP LOG ==="
    echo "Generated: $(date)"
    echo "Server: $(hostname)"
    echo "Public IP: $IP"
    echo
    echo "[GLOBAL]"
    echo "ACME_EMAIL=$ACME_EMAIL"
    echo
    echo "[WEBMIN]"
    echo "WEBMIN_DOMAIN=$WEBMIN_DOMAIN"
    echo "WEBMIN_PROXY=$WEBMIN_PROXY"
    echo "WEBMIN_SSL=$WEBMIN_SSL"
    echo "WEBMIN_UFW=$WEBMIN_UFW"
    echo
    echo "[SEQ]"
    echo "SEQ_DOMAIN=$SEQ_DOMAIN"
    echo "SEQ_DATA_DIR=$SEQ_DATA_DIR"
    echo "SEQ_BACKEND_PORT=$SEQ_BACKEND_PORT"
    echo "SEQ_TCP_PORT=$SEQ_TCP_PORT"
    echo "SEQ_OPEN_TCP=$SEQ_OPEN_TCP"
    [[ -n "$SEQ_TCP_CIDR" ]] && echo "SEQ_TCP_CIDR=$SEQ_TCP_CIDR" || true
    echo "SEQ_ACCEPT_EULA=$SEQ_ACCEPT_EULA"
    echo "SEQ_IMAGE=$SEQ_IMAGE"
    echo "SEQ_ADMIN_PASSWORD=$SEQ_ADMIN_PASSWORD"
    echo "SEQ_ENABLE_SSL=$SEQ_ENABLE_SSL"
    echo
    echo "[KEYCLOAK]"
    echo "KC_DOMAIN=$KC_DOMAIN"
    echo "KC_HTTP_PORT=$KC_HTTP_PORT"
    echo "KC_DB_NAME=$KC_DB_NAME"
    echo "KC_DB_USER=$KC_DB_USER"
    echo "KC_DB_PASSWORD=$KC_DB_PASSWORD"
    echo "KC_ADMIN_USER=$KC_ADMIN_USER"
    echo "KC_ADMIN_PASSWORD=$KC_ADMIN_PASSWORD"
    echo "KC_ALLOWED_FRAME_ANCESTORS=$KC_ALLOWED_FRAME_ANCESTORS"
    echo
    echo "[ACCESS]"
    echo "Webmin:   https://${WEBMIN_DOMAIN}/ (proxied; backend 127.0.0.1:10000)"
    echo "Seq:      https://${SEQ_DOMAIN}/ (UI; backend http://127.0.0.1:${SEQ_BACKEND_PORT}/)"
    echo "Keycloak: https://${KC_DOMAIN}/admin/ (backend http://127.0.0.1:${KC_HTTP_PORT}/)"
    echo
    echo "[COMMANDS]"
    echo "Webmin diagnose: /root/webmin-diagnostic.sh"
    echo "Seq diagnose:    /root/seq-diagnostic.sh"
    echo "Keycloak diag:   /root/keycloak-diagnostic.sh"
    echo
    echo "[SECURITY & RENEWAL]"
    echo "• UFW configured: $WEBMIN_UFW (HTTP/HTTPS open; Seq TCP per settings)"
    echo "• Let's Encrypt auto-renew is handled by systemd timers installed by certbot."
    echo
    echo "[DELETE THIS FILE]"
    echo "This file contains secrets. To securely delete:"
    echo "  shred -u /root/setup.log   # overwrite and remove"
    echo "  history -c; history -w     # clear current shell history"
  } > "$LOG"
  chmod 600 "$LOG"
  ok "Setup log written to $LOG"
}

############################################
# Summary
############################################
summary(){
  local ip=$(curl -s ifconfig.me 2>/dev/null || echo "Unknown")
  echo
  echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║                🎉 MERGED INSTALL COMPLETE! 🎉                  ║${NC}"
  echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
  echo
  echo -e "${BLUE}📋 QUICK LINKS:${NC}"
  [[ "$WEBMIN_PROXY" =~ ^[Yy]$ ]] && echo "• Webmin:   https://${WEBMIN_DOMAIN}/"
  echo "• Seq:      https://${SEQ_DOMAIN}/"
  echo "• Keycloak: https://${KC_DOMAIN}/admin/"
  echo
  echo -e "${YELLOW}🛠 Diagnostics:${NC} /root/webmin-diagnostic.sh | /root/seq-diagnostic.sh | /root/keycloak-diagnostic.sh"
  echo -e "${YELLOW}📄 Setup log:${NC} /root/setup.log (contains passwords; see deletion instructions inside)"
  echo
}

############################################
# Main
############################################
main(){
  trap 'err "Installation failed at line $LINENO"; exit 1' ERR
  check_root
  prompt_all
  update_system
  ensure_base
  ensure_apache

  # WEBMIN
  install_webmin_repo
  install_webmin
  if [[ "$WEBMIN_PROXY" =~ ^[Yy]$ ]]; then
    configure_webmin_proxy
    webmin_ssl
  fi

  # SEQ
  ensure_docker
  seq_prepare_dirs
  seq_run_container
  seq_apache_vhost
  seq_ssl

  # KEYCLOAK
  kc_install_dependencies
  kc_setup_postgresql
  kc_setup_user_dirs
  kc_install_binary
  kc_write_config_and_build
  kc_systemd_service
  kc_apache_vhosts
  kc_ssl
  kc_start_and_check

  # Security & tools
  configure_ufw_global
  enable_fail2ban
  write_diag_helpers

  # Log + summary
  write_setup_log
  summary
}

main "$@"
