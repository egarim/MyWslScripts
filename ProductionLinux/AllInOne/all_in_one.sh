#!/bin/bash
# Unified Server Installation Script for Ubuntu 22.04+
# Installs: Keycloak, Seq Log Server, and Webmin
# - Eliminates redundant prompts between services
# - Generates comprehensive installation log with credentials
# Author: Production Deployment Script
# Version: 2.0 - Unified Edition
# Date: August 2025
set -euo pipefail

# =========================
# Global Configuration Variables
# =========================
KEYCLOAK_VERSION="26.3.1"
KEYCLOAK_USER="keycloak"
KEYCLOAK_GROUP="keycloak"
KEYCLOAK_HOME="/opt/keycloak"
KEYCLOAK_LOG_DIR="/var/log/keycloak"
KEYCLOAK_DATA_DIR="/var/lib/keycloak"

# Unified Defaults
DEFAULT_BASE_DOMAIN="sivargpt.com"
DEFAULT_KEYCLOAK_SUBDOMAIN="auth"
DEFAULT_SEQ_SUBDOMAIN="logs"
DEFAULT_WEBMIN_SUBDOMAIN="webmin"

# Service-specific defaults
DEFAULT_DB_NAME="keycloak_prod"
DEFAULT_DB_USER="keycloak_user"
DEFAULT_DB_PASSWORD="$(openssl rand -base64 12)"
DEFAULT_KEYCLOAK_ADMIN_USER="keycloakadmin"
DEFAULT_KEYCLOAK_ADMIN_PASSWORD="$(openssl rand -base64 12)"
DEFAULT_KEYCLOAK_HTTP_PORT="8080"
DEFAULT_KEYCLOAK_FRAME_ANCESTORS="'self' https://your-shell.example.com"

DEFAULT_SEQ_DATA_DIR="/var/lib/seq"
DEFAULT_SEQ_BACKEND_PORT="5342"
DEFAULT_SEQ_TCP_INGEST_PORT="5341"
DEFAULT_SEQ_ACCEPT_EULA="Y"
DEFAULT_SEQ_OPEN_TCP_INGEST="N"
DEFAULT_SEQ_TCP_INGEST_CIDR="10.0.0.0/24"
DEFAULT_SEQ_IMAGE="datalust/seq:latest"
DEFAULT_SEQ_ADMIN_PASSWORD="$(openssl rand -base64 12)"

# User-configurable (prompted once)
INSTALL_KEYCLOAK=""
INSTALL_SEQ=""
INSTALL_WEBMIN=""
BASE_DOMAIN=""
KEYCLOAK_HOSTNAME=""
SEQ_HOSTNAME=""
WEBMIN_HOSTNAME=""
ENABLE_SSL=""
UFW_RESET=""

# Keycloak specific
DB_NAME=""
DB_USER=""
DB_PASSWORD=""
KEYCLOAK_ADMIN_USER=""
KEYCLOAK_ADMIN_PASSWORD=""
KEYCLOAK_HTTP_PORT=""
KEYCLOAK_FRAME_ANCESTORS=""

# Seq specific
SEQ_DATA_DIR=""
SEQ_BACKEND_PORT=""
SEQ_TCP_INGEST_PORT=""
SEQ_ACCEPT_EULA=""
SEQ_OPEN_TCP_INGEST=""
SEQ_TCP_INGEST_CIDR=""
SEQ_IMAGE=""
SEQ_ADMIN_PASSWORD=""

# Installation log file
INSTALL_LOG="/root/installation_summary_$(date +%Y%m%d_%H%M%S).log"

# =========================
# Output Cosmetics
# =========================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
log(){ echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
log_success(){ echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1"; }
log_warning(){ echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"; }
log_error(){ echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"; }
log_phase(){ echo -e "${CYAN}[$(date +'%Y-%m-%d %H:%M:%S')] PHASE:${NC} $1"; }

# Also log to file
log_to_file(){ echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$INSTALL_LOG"; }

check_root(){ if [[ $EUID -ne 0 ]]; then log_error "Run as root"; exit 1; fi; }

# =========================
# Unified Prompts
# =========================
prompt_unified_inputs(){
  echo; log "=== UNIFIED SERVER INSTALLATION CONFIGURATION ==="; echo
  echo -e "${YELLOW}This script will install Keycloak, Seq Log Server, and/or Webmin${NC}"
  echo -e "${YELLOW}Press Enter to use default values shown in brackets${NC}"; echo
  
  # Service selection
  log "📋 SERVICE SELECTION:"
  read -p "Install Keycloak Identity Server? (Y/n): " INSTALL_KEYCLOAK; INSTALL_KEYCLOAK=${INSTALL_KEYCLOAK:-Y}
  read -p "Install Seq Log Server? (Y/n): " INSTALL_SEQ; INSTALL_SEQ=${INSTALL_SEQ:-Y}
  read -p "Install Webmin? (Y/n): " INSTALL_WEBMIN; INSTALL_WEBMIN=${INSTALL_WEBMIN:-Y}
  
  if [[ ! "$INSTALL_KEYCLOAK" =~ ^[Yy]$ && ! "$INSTALL_SEQ" =~ ^[Yy]$ && ! "$INSTALL_WEBMIN" =~ ^[Yy]$ ]]; then
    log_error "At least one service must be selected"; exit 1
  fi
  
  echo; log "🌐 DOMAIN CONFIGURATION:"
  read -p "Base domain [$DEFAULT_BASE_DOMAIN]: " BASE_DOMAIN; BASE_DOMAIN=${BASE_DOMAIN:-$DEFAULT_BASE_DOMAIN}
  
  if [[ "$INSTALL_KEYCLOAK" =~ ^[Yy]$ ]]; then
    read -p "Keycloak subdomain [$DEFAULT_KEYCLOAK_SUBDOMAIN]: " KEYCLOAK_SUB; KEYCLOAK_SUB=${KEYCLOAK_SUB:-$DEFAULT_KEYCLOAK_SUBDOMAIN}
    KEYCLOAK_HOSTNAME="${KEYCLOAK_SUB}.${BASE_DOMAIN}"
  fi
  
  if [[ "$INSTALL_SEQ" =~ ^[Yy]$ ]]; then
    read -p "Seq subdomain [$DEFAULT_SEQ_SUBDOMAIN]: " SEQ_SUB; SEQ_SUB=${SEQ_SUB:-$DEFAULT_SEQ_SUBDOMAIN}
    SEQ_HOSTNAME="${SEQ_SUB}.${BASE_DOMAIN}"
  fi
  
  if [[ "$INSTALL_WEBMIN" =~ ^[Yy]$ ]]; then
    read -p "Webmin subdomain [$DEFAULT_WEBMIN_SUBDOMAIN]: " WEBMIN_SUB; WEBMIN_SUB=${WEBMIN_SUB:-$DEFAULT_WEBMIN_SUBDOMAIN}
    WEBMIN_HOSTNAME="${WEBMIN_SUB}.${BASE_DOMAIN}"
  fi
  
  echo; log "🔒 GLOBAL SETTINGS:"
  read -p "Setup SSL certificates automatically? (Y/n): " ENABLE_SSL; ENABLE_SSL=${ENABLE_SSL:-Y}
  read -p "Reset UFW firewall to secure defaults? (Y/n): " UFW_RESET; UFW_RESET=${UFW_RESET:-Y}
  
  # Service-specific configurations
  if [[ "$INSTALL_KEYCLOAK" =~ ^[Yy]$ ]]; then
    echo; log "🔑 KEYCLOAK CONFIGURATION:"
    read -p "Database name [$DEFAULT_DB_NAME]: " DB_NAME; DB_NAME=${DB_NAME:-$DEFAULT_DB_NAME}
    read -p "Database username [$DEFAULT_DB_USER]: " DB_USER; DB_USER=${DB_USER:-$DEFAULT_DB_USER}
    read -p "Database password [auto-generated]: " DB_PASSWORD; DB_PASSWORD=${DB_PASSWORD:-$DEFAULT_DB_PASSWORD}
    read -p "Keycloak admin username [$DEFAULT_KEYCLOAK_ADMIN_USER]: " KEYCLOAK_ADMIN_USER; KEYCLOAK_ADMIN_USER=${KEYCLOAK_ADMIN_USER:-$DEFAULT_KEYCLOAK_ADMIN_USER}
    read -p "Keycloak admin password [auto-generated]: " KEYCLOAK_ADMIN_PASSWORD; KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD:-$DEFAULT_KEYCLOAK_ADMIN_PASSWORD}
    read -p "Backend HTTP port [$DEFAULT_KEYCLOAK_HTTP_PORT]: " KEYCLOAK_HTTP_PORT; KEYCLOAK_HTTP_PORT=${KEYCLOAK_HTTP_PORT:-$DEFAULT_KEYCLOAK_HTTP_PORT}
    read -p "Frame ancestors [$DEFAULT_KEYCLOAK_FRAME_ANCESTORS]: " KEYCLOAK_FRAME_ANCESTORS; KEYCLOAK_FRAME_ANCESTORS=${KEYCLOAK_FRAME_ANCESTORS:-$DEFAULT_KEYCLOAK_FRAME_ANCESTORS}
  fi
  
  if [[ "$INSTALL_SEQ" =~ ^[Yy]$ ]]; then
    echo; log "📊 SEQ CONFIGURATION:"
    read -p "Data directory [$DEFAULT_SEQ_DATA_DIR]: " SEQ_DATA_DIR; SEQ_DATA_DIR=${SEQ_DATA_DIR:-$DEFAULT_SEQ_DATA_DIR}
    read -p "Backend HTTP port [$DEFAULT_SEQ_BACKEND_PORT]: " SEQ_BACKEND_PORT; SEQ_BACKEND_PORT=${SEQ_BACKEND_PORT:-$DEFAULT_SEQ_BACKEND_PORT}
    read -p "TCP ingestion port [$DEFAULT_SEQ_TCP_INGEST_PORT]: " SEQ_TCP_INGEST_PORT; SEQ_TCP_INGEST_PORT=${SEQ_TCP_INGEST_PORT:-$DEFAULT_SEQ_TCP_INGEST_PORT}
    read -p "Open TCP ingestion to CIDR? (y/N) [$DEFAULT_SEQ_OPEN_TCP_INGEST]: " SEQ_OPEN_TCP_INGEST; SEQ_OPEN_TCP_INGEST=${SEQ_OPEN_TCP_INGEST:-$DEFAULT_SEQ_OPEN_TCP_INGEST}
    if [[ "$SEQ_OPEN_TCP_INGEST" =~ ^[Yy]$ ]]; then
      read -p "CIDR for TCP ingestion [$DEFAULT_SEQ_TCP_INGEST_CIDR]: " SEQ_TCP_INGEST_CIDR; SEQ_TCP_INGEST_CIDR=${SEQ_TCP_INGEST_CIDR:-$DEFAULT_SEQ_TCP_INGEST_CIDR}
    fi
    read -p "Accept Seq EULA? (Y/n) [$DEFAULT_SEQ_ACCEPT_EULA]: " SEQ_ACCEPT_EULA; SEQ_ACCEPT_EULA=${SEQ_ACCEPT_EULA:-$DEFAULT_SEQ_ACCEPT_EULA}
    read -p "Seq admin password [auto-generated]: " SEQ_ADMIN_PASSWORD; SEQ_ADMIN_PASSWORD=${SEQ_ADMIN_PASSWORD:-$DEFAULT_SEQ_ADMIN_PASSWORD}
    SEQ_IMAGE="$DEFAULT_SEQ_IMAGE"
  fi
  
  echo; log "📋 CONFIGURATION SUMMARY:"
  echo "Services to install:"
  [[ "$INSTALL_KEYCLOAK" =~ ^[Yy]$ ]] && echo "  ✓ Keycloak → $KEYCLOAK_HOSTNAME"
  [[ "$INSTALL_SEQ" =~ ^[Yy]$ ]] && echo "  ✓ Seq → $SEQ_HOSTNAME"
  [[ "$INSTALL_WEBMIN" =~ ^[Yy]$ ]] && echo "  ✓ Webmin → $WEBMIN_HOSTNAME"
  echo "Global settings:"
  echo "  SSL certificates: $ENABLE_SSL"
  echo "  UFW reset: $UFW_RESET"
  echo "  Installation log: $INSTALL_LOG"
  echo
  read -p "Continue with this configuration? (y/N): " confirm
  if [[ ! $confirm =~ ^[Yy]$ ]]; then log "Installation cancelled by user"; exit 0; fi
  log_success "Configuration confirmed"
  
  # Initialize log file
  cat > "$INSTALL_LOG" <<EOF
=================================
UNIFIED SERVER INSTALLATION LOG
=================================
Installation Date: $(date)
Server Hostname: $(hostname)
Server IP: $(curl -s ifconfig.me 2>/dev/null || echo "Unknown")
Base Domain: $BASE_DOMAIN

SERVICES INSTALLED:
EOF
  [[ "$INSTALL_KEYCLOAK" =~ ^[Yy]$ ]] && echo "- Keycloak Identity Server" >> "$INSTALL_LOG"
  [[ "$INSTALL_SEQ" =~ ^[Yy]$ ]] && echo "- Seq Log Server" >> "$INSTALL_LOG"
  [[ "$INSTALL_WEBMIN" =~ ^[Yy]$ ]] && echo "- Webmin" >> "$INSTALL_LOG"
  echo "" >> "$INSTALL_LOG"
}

# =========================
# System Setup (Shared)
# =========================
update_system(){
  log_phase "SYSTEM PREPARATION"
  log "Updating system packages..."
  apt-get update -y && apt-get upgrade -y
  log_success "System packages updated"
  log_to_file "System packages updated successfully"
}

install_shared_dependencies(){
  log "Installing shared dependencies..."
  apt-get install -y \
    ca-certificates curl gnupg lsb-release software-properties-common \
    ufw fail2ban unzip wget openssl net-tools jq
  
  # Install Apache (shared by all services)
  if ! command -v apache2 >/dev/null 2>&1; then
    log "Installing Apache and modules..."
    apt-get install -y apache2 certbot python3-certbot-apache
    systemctl enable --now apache2
  fi
  
  a2enmod proxy proxy_http proxy_ajp rewrite deflate headers proxy_balancer proxy_connect proxy_html ssl status >/dev/null 2>&1 || true
  log_success "Shared dependencies installed"
  log_to_file "Apache and shared dependencies installed"
}

configure_unified_firewall(){
  if [[ "$UFW_RESET" =~ ^[Yy]$ ]]; then
    log "Configuring unified UFW firewall..."
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp comment 'SSH'
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    
    # PostgreSQL (only local)
    if [[ "$INSTALL_KEYCLOAK" =~ ^[Yy]$ ]]; then
      ufw allow from 127.0.0.1 to any port 5432 comment 'PostgreSQL local'
    fi
    
    # Seq TCP ingestion (conditional)
    if [[ "$INSTALL_SEQ" =~ ^[Yy]$ && "$SEQ_OPEN_TCP_INGEST" =~ ^[Yy]$ ]]; then
      ufw allow from "$SEQ_TCP_INGEST_CIDR" to any port "$SEQ_TCP_INGEST_PORT" proto tcp comment 'Seq TCP ingest'
    fi
    
    ufw --force enable
    log_success "UFW configured with unified rules"
    log_to_file "UFW firewall configured with ports: 22, 80, 443"
  fi
}

configure_unified_fail2ban(){
  log "Configuring fail2ban..."
  
  if [[ "$INSTALL_KEYCLOAK" =~ ^[Yy]$ ]]; then
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
logpath = $KEYCLOAK_LOG_DIR/keycloak.log
maxretry = 5
bantime = 3600
findtime = 600
EOF
  fi
  
  systemctl restart fail2ban
  systemctl enable fail2ban
  log_success "fail2ban configured"
  log_to_file "fail2ban configured for all services"
}

# =========================
# Keycloak Installation
# =========================
install_keycloak(){
  if [[ ! "$INSTALL_KEYCLOAK" =~ ^[Yy]$ ]]; then return 0; fi
  
  log_phase "KEYCLOAK INSTALLATION"
  
  # PostgreSQL
  log "Setting up PostgreSQL for Keycloak..."
  apt-get install -y postgresql postgresql-contrib openjdk-21-jdk
  systemctl enable --now postgresql
  
  local pg_version=$(sudo -u postgres psql -t -c "SELECT split_part(version(), ' ', 2);" | awk '{print $1}' | head -1)
  local pg_major=$(echo "$pg_version" | cut -d. -f1)
  local pg_conf="/etc/postgresql/$pg_major/main/postgresql.conf"
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

  sudo -u postgres psql <<EOF
DROP DATABASE IF EXISTS $DB_NAME;
DROP USER IF EXISTS $DB_USER;
CREATE DATABASE $DB_NAME WITH ENCODING 'UTF8' LC_COLLATE='en_US.UTF-8' LC_CTYPE='en_US.UTF-8' TEMPLATE=template0;
CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
ALTER DATABASE $DB_NAME OWNER TO $DB_USER;
\c $DB_NAME
GRANT ALL ON SCHEMA public TO $DB_USER;
GRANT CREATE, USAGE ON SCHEMA public TO $DB_USER;
EOF

  systemctl restart postgresql
  
  # Test DB connection
  if PGPASSWORD="$DB_PASSWORD" psql -h localhost -U "$DB_USER" -d "$DB_NAME" -c "SELECT version();" >/dev/null 2>&1; then
    log_success "PostgreSQL configured and tested"
    log_to_file "PostgreSQL database '$DB_NAME' created with user '$DB_USER'"
  else
    log_error "Database connection test failed"; exit 1
  fi
  
  # Keycloak user and directories
  log "Creating Keycloak user and directories..."
  groupadd -r $KEYCLOAK_GROUP 2>/dev/null || true
  useradd -r -g $KEYCLOAK_GROUP -d $KEYCLOAK_HOME -s /usr/sbin/nologin $KEYCLOAK_USER 2>/dev/null || true
  mkdir -p $KEYCLOAK_HOME $KEYCLOAK_LOG_DIR $KEYCLOAK_DATA_DIR $KEYCLOAK_HOME/conf $KEYCLOAK_HOME/data
  chown -R $KEYCLOAK_USER:$KEYCLOAK_GROUP $KEYCLOAK_HOME $KEYCLOAK_LOG_DIR $KEYCLOAK_DATA_DIR
  chmod 750 $KEYCLOAK_HOME $KEYCLOAK_DATA_DIR; chmod 755 $KEYCLOAK_LOG_DIR
  
  # Download and install Keycloak
  log "Installing Keycloak $KEYCLOAK_VERSION..."
  cd /tmp
  local url="https://github.com/keycloak/keycloak/releases/download/${KEYCLOAK_VERSION}/keycloak-${KEYCLOAK_VERSION}.tar.gz"
  wget -O keycloak.tar.gz "$url"
  tar -xzf keycloak.tar.gz
  cp -r keycloak-${KEYCLOAK_VERSION}/* $KEYCLOAK_HOME/
  chown -R $KEYCLOAK_USER:$KEYCLOAK_GROUP $KEYCLOAK_HOME
  chmod +x $KEYCLOAK_HOME/bin/*.sh
  rm -rf keycloak.tar.gz keycloak-${KEYCLOAK_VERSION}
  
  # Configure Keycloak
  log "Configuring Keycloak..."
  cat > $KEYCLOAK_HOME/conf/keycloak.conf <<EOF
# Database
db=postgres
db-username=$DB_USER
db-password=$DB_PASSWORD
db-url=jdbc:postgresql://localhost:5432/$DB_NAME
db-pool-initial-size=5
db-pool-min-size=5
db-pool-max-size=20

# Host/Proxy
hostname=$KEYCLOAK_HOSTNAME
hostname-strict=false
hostname-strict-backchannel=false
proxy-headers=xforwarded
hostname-strict-https=true

# HTTP (backend)
http-enabled=true
http-port=$KEYCLOAK_HTTP_PORT

# Health/metrics
health-enabled=true
metrics-enabled=true
http-max-queued-requests=1000

# Logging
log=console,file
log-level=INFO
log-file=$KEYCLOAK_LOG_DIR/keycloak.log
log-file-format=%d{yyyy-MM-dd HH:mm:ss,SSS} %-5p [%c] (%t) %s%e%n

# Cache
cache=local

# Transactions
transaction-xa-enabled=false

# Features
features=token-exchange,admin-fine-grained-authz
EOF
  chown $KEYCLOAK_USER:$KEYCLOAK_GROUP $KEYCLOAK_HOME/conf/keycloak.conf
  chmod 640 $KEYCLOAK_HOME/conf/keycloak.conf
  
  # Build Keycloak
  log "Building Keycloak..."
  sudo -u $KEYCLOAK_USER $KEYCLOAK_HOME/bin/kc.sh build \
    --db=postgres \
    --health-enabled=true \
    --metrics-enabled=true \
    --features=token-exchange,admin-fine-grained-authz
  
  # Create systemd service
  cat > /etc/systemd/system/keycloak.service <<EOF
[Unit]
Description=Keycloak Identity and Access Management
Documentation=https://www.keycloak.org/
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=exec
User=$KEYCLOAK_USER
Group=$KEYCLOAK_GROUP
Environment=JAVA_OPTS="-Xms512m -Xmx1024m -Djava.net.preferIPv4Stack=true"
Environment=KC_BOOTSTRAP_ADMIN_USERNAME=$KEYCLOAK_ADMIN_USER
Environment=KC_BOOTSTRAP_ADMIN_PASSWORD=$KEYCLOAK_ADMIN_PASSWORD
ExecStart=$KEYCLOAK_HOME/bin/kc.sh start --optimized
StandardOutput=journal
StandardError=journal
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=30
TimeoutStartSec=300
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
  
  # Configure Apache vhost
  configure_keycloak_apache_vhost
  
  # Start Keycloak
  log "Starting Keycloak..."
  systemctl start keycloak
  
  # Wait for startup
  local max_wait=120; local waited=0
  while (( waited < max_wait )); do
    if systemctl is-active --quiet keycloak; then
      log_success "Keycloak service is running"; break
    fi
    sleep 5; waited=$((waited+5))
  done
  
  log_success "Keycloak installation completed"
  log_to_file "Keycloak installed successfully at $KEYCLOAK_HOSTNAME"
  log_to_file "Keycloak admin user: $KEYCLOAK_ADMIN_USER"
  log_to_file "Keycloak admin password: $KEYCLOAK_ADMIN_PASSWORD"
  log_to_file "Keycloak database: $DB_NAME (user: $DB_USER, password: $DB_PASSWORD)"
}

configure_keycloak_apache_vhost(){
  log "Configuring Apache vhost for Keycloak..."
  
  # Headers configuration
  cat > /etc/apache2/conf-available/keycloak-headers.conf <<EOF
<IfModule mod_headers.c>
    Header always unset X-Frame-Options
    Header always set Content-Security-Policy "frame-ancestors ${KEYCLOAK_FRAME_ANCESTORS}"
    Header always set X-Content-Type-Options nosniff
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
</IfModule>
EOF
  a2enconf keycloak-headers.conf || true
  
  # Port 80 vhost
  cat > /etc/apache2/sites-available/keycloak.conf <<EOF
<VirtualHost *:80>
    ServerName $KEYCLOAK_HOSTNAME

    ProxyPreserveHost On
    ProxyRequests Off
    ProxyPass /.well-known/acme-challenge/ !
    DocumentRoot /var/www/html

    RequestHeader set X-Forwarded-Proto expr=%{REQUEST_SCHEME}
    RequestHeader set X-Forwarded-Port  expr=%{SERVER_PORT}
    RequestHeader set X-Forwarded-Host  "%{HTTP_HOST}s"

    ProxyPass        / http://127.0.0.1:$KEYCLOAK_HTTP_PORT/
    ProxyPassReverse / http://127.0.0.1:$KEYCLOAK_HTTP_PORT/

    ErrorLog \${APACHE_LOG_DIR}/keycloak_error.log
    CustomLog \${APACHE_LOG_DIR}/keycloak_access.log combined
</VirtualHost>
EOF
  
  a2ensite keycloak.conf
  apache2ctl configtest && systemctl reload apache2
}

# =========================
# Seq Installation
# =========================
install_seq(){
  if [[ ! "$INSTALL_SEQ" =~ ^[Yy]$ ]]; then return 0; fi
  
  log_phase "SEQ LOG SERVER INSTALLATION"
  
  # Install Docker
  if ! command -v docker >/dev/null 2>&1; then
    log "Installing Docker..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    log_success "Docker installed"
  fi
  
  # Prepare directories
  log "Preparing Seq data directory..."
  mkdir -p "$SEQ_DATA_DIR"
  chown root:root "$SEQ_DATA_DIR"
  chmod 755 "$SEQ_DATA_DIR"
  
  # Stop existing container if present
  if docker ps -a --format '{{.Names}}' | grep -q '^seq$'; then
    log_warning "Removing existing Seq container..."
    docker rm -f seq || true
  fi
  
  # Start Seq container
  [[ "$SEQ_ACCEPT_EULA" =~ ^[Yy]$ ]] || { log_error "Seq EULA must be accepted"; exit 1; }
  
  log "Starting Seq container..."
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
  
  # Wait for Seq to start
  log "Waiting for Seq to become ready..."
  local max=90; local n=1
  until curl -fsS "http://127.0.0.1:${SEQ_BACKEND_PORT}/" >/dev/null 2>&1; do
    if (( n >= max )); then
      log_warning "Seq didn't respond after ~$((max*2))s; continuing"
      break
    fi
    sleep 2; n=$((n+1))
  done
  
  # Configure Apache vhost
  configure_seq_apache_vhost
  
  log_success "Seq installation completed"
  log_to_file "Seq Log Server installed successfully at $SEQ_HOSTNAME"
  log_to_file "Seq admin password: $SEQ_ADMIN_PASSWORD"
  log_to_file "Seq data directory: $SEQ_DATA_DIR"
  log_to_file "Seq TCP ingestion port: $SEQ_TCP_INGEST_PORT"
}

configure_seq_apache_vhost(){
  log "Configuring Apache vhost for Seq..."
  
  cat > /etc/apache2/sites-available/seq.conf <<EOF
<VirtualHost *:80>
    ServerName $SEQ_HOSTNAME

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
  
  a2ensite seq.conf
  apache2ctl configtest && systemctl reload apache2
}

# =========================
# Webmin Installation
# =========================
install_webmin(){
  if [[ ! "$INSTALL_WEBMIN" =~ ^[Yy]$ ]]; then return 0; fi
  
  log_phase "WEBMIN INSTALLATION"
  
  # Add Webmin repository
  log "Adding Webmin repository..."
  curl -fsSL http://www.webmin.com/jcameron-key.asc | gpg --dearmor -o /usr/share/keyrings/webmin.gpg
  echo "deb [signed-by=/usr/share/keyrings/webmin.gpg] http://download.webmin.com/download/repository sarge contrib" > /etc/apt/sources.list.d/webmin.list
  apt-get update -y
  
  # Install Webmin
  log "Installing Webmin..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y webmin
  systemctl enable --now webmin || true
  
  # Configure Webmin for proxy
  configure_webmin_for_proxy
  
  # Configure Apache vhost
  configure_webmin_apache_vhost
  
  log_success "Webmin installation completed"
  log_to_file "Webmin installed successfully at $WEBMIN_HOSTNAME"
  log_to_file "Webmin access: Use root user credentials"
}

configure_webmin_for_proxy(){
  log "Configuring Webmin for proxy setup..."
  local conf="/etc/webmin/miniserv.conf"
  local cfg="/etc/webmin/config"
  
  if [[ -f "$conf" ]]; then
    # Bind to localhost with SSL
    grep -q '^bind=' "$conf" && sed -i 's/^bind=.*/bind=127.0.0.1/' "$conf" || echo "bind=127.0.0.1" >> "$conf"
    grep -q '^port=' "$conf" && sed -i 's/^port=.*/port=10000/' "$conf" || echo "port=10000" >> "$conf"
    grep -q '^listen=' "$conf" && sed -i 's/^listen=.*/listen=10000/' "$conf" || echo "listen=10000" >> "$conf"
    grep -q '^ssl=' "$conf" && sed -i 's/^ssl=.*/ssl=1/' "$conf" || echo "ssl=1" >> "$conf"
    
    # Proxy settings
    if [[ -f "$cfg" ]]; then
      sed -i 's/^webprefixnoredir=.*/webprefixnoredir=1/; t; $ a webprefixnoredir=1' "$cfg"
      if grep -q '^referers=' "$cfg"; then
        sed -i "s/^referers=.*/referers=${WEBMIN_HOSTNAME}/" "$cfg"
      else
        echo "referers=${WEBMIN_HOSTNAME}" >> "$cfg"
      fi
    fi
    
    # Redirect host
    if grep -q '^redirect_host=' "$conf" 2>/dev/null; then
      sed -i "s/^redirect_host=.*/redirect_host=${WEBMIN_HOSTNAME}/" "$conf"
    else
      echo "redirect_host=${WEBMIN_HOSTNAME}" >> "$conf"
    fi
    
    systemctl restart webmin
    log_success "Webmin configured for proxy"
  fi
}

configure_webmin_apache_vhost(){
  log "Configuring Apache vhost for Webmin..."
  
  cat > /etc/apache2/sites-available/webmin.conf <<EOF
<VirtualHost *:80>
    ServerName $WEBMIN_HOSTNAME

    ProxyPreserveHost On
    ProxyRequests Off
    ProxyTimeout 300
    ProxyPass /.well-known/acme-challenge/ !
    DocumentRoot /var/www/html

    RequestHeader set X-Forwarded-Proto expr=%{REQUEST_SCHEME}
    RequestHeader set X-Forwarded-Port  expr=%{SERVER_PORT}
    RequestHeader set X-Forwarded-Host  "%{HTTP_HOST}s"

    # Backend is HTTPS with self-signed cert
    SSLProxyEngine On
    SSLProxyVerify none
    SSLProxyCheckPeerName off
    SSLProxyCheckPeerCN off
    SSLProxyCheckPeerExpire off

    ProxyPass        / https://127.0.0.1:10000/ retry=1 acquire=3000 timeout=600 keepalive=On
    ProxyPassReverse / https://127.0.0.1:10000/

    ProxyPassReverseCookieDomain 127.0.0.1 $WEBMIN_HOSTNAME
    ProxyPassReverseCookiePath / /

    ErrorLog \${APACHE_LOG_DIR}/webmin_error.log
    CustomLog \${APACHE_LOG_DIR}/webmin_access.log combined
</VirtualHost>
EOF
  
  a2ensite webmin.conf
  apache2ctl configtest && systemctl reload apache2
}

# =========================
# SSL Certificate Setup
# =========================
setup_ssl_certificates(){
  if [[ ! "$ENABLE_SSL" =~ ^[Yy]$ ]]; then
    log_warning "Skipping SSL certificate setup"
    return 0
  fi
  
  log_phase "SSL CERTIFICATE SETUP"
  
  local domains=()
  [[ "$INSTALL_KEYCLOAK" =~ ^[Yy]$ ]] && domains+=("$KEYCLOAK_HOSTNAME")
  [[ "$INSTALL_SEQ" =~ ^[Yy]$ ]] && domains+=("$SEQ_HOSTNAME")
  [[ "$INSTALL_WEBMIN" =~ ^[Yy]$ ]] && domains+=("$WEBMIN_HOSTNAME")
  
  if [ ${#domains[@]} -eq 0 ]; then
    log_warning "No domains to configure SSL for"
    return 0
  fi
  
  mkdir -p /var/www/html
  chown www-data:www-data /var/www/html
  
  for domain in "${domains[@]}"; do
    log "Setting up SSL for $domain..."
    
    # Test HTTP accessibility
    if timeout 10 curl -s "http://$domain/" >/dev/null 2>&1; then
      log_success "Domain $domain is accessible over HTTP"
      
      # Run certbot
      if certbot --apache -d "$domain" --non-interactive --agree-tos --email admin@"$domain" --redirect; then
        log_success "SSL certificate issued for $domain"
        log_to_file "SSL certificate issued for $domain"
        
        # Patch HTTPS vhost if it's Webmin (needs special proxy config)
        if [[ "$domain" == "$WEBMIN_HOSTNAME" ]]; then
          patch_webmin_https_vhost
        fi
      else
        log_error "Certbot failed for $domain"
        log_to_file "SSL certificate failed for $domain"
      fi
    else
      log_error "HTTP check failed for $domain. Check DNS/Firewall."
      log_to_file "SSL setup failed for $domain - HTTP not accessible"
    fi
  done
}

patch_webmin_https_vhost(){
  local sslv="/etc/apache2/sites-available/webmin-le-ssl.conf"
  if [ ! -f "$sslv" ]; then
    return 0
  fi

  log "Patching Webmin HTTPS vhost with proxy directives..."
  awk -v host="$WEBMIN_HOSTNAME" '
    /<VirtualHost/ && $0 ~ /:443>/ { inside=1 }
    inside==1 && /ServerName/ { 
      print; print ""; 
      print "    ProxyPreserveHost On"; 
      print "    ProxyRequests Off"; 
      print "    ProxyTimeout 300"; 
      print ""; 
      print "    RequestHeader set X-Forwarded-Proto \"https\""; 
      print "    RequestHeader set X-Forwarded-Port  \"443\""; 
      print "    RequestHeader set X-Forwarded-Host  \"" host "\""; 
      print ""; 
      print "    SSLProxyEngine On"; 
      print "    SSLProxyVerify none"; 
      print "    SSLProxyCheckPeerName off"; 
      print "    SSLProxyCheckPeerCN off"; 
      print "    SSLProxyCheckPeerExpire off"; 
      print ""; 
      print "    ProxyPass        / https://127.0.0.1:10000/ retry=1 acquire=3000 timeout=600 keepalive=On"; 
      print "    ProxyPassReverse / https://127.0.0.1:10000/"; 
      print ""; 
      print "    ProxyPassReverseCookieDomain 127.0.0.1 " host; 
      print "    ProxyPassReverseCookiePath / /"; 
      skip=1; next 
    }
    /<\/VirtualHost>/ && inside==1 { inside=0 }
    { if(!skip) print; skip=0 }
  ' "$sslv" > "${sslv}.new" && mv "${sslv}.new" "$sslv"

  a2ensite webmin-le-ssl.conf >/dev/null 2>&1 || true
  apache2ctl configtest && systemctl reload apache2
}

# =========================
# Final Health Checks
# =========================
perform_health_checks(){
  log_phase "HEALTH CHECKS"
  
  local total_score=0
  local max_score=0
  
  # System checks
  log "Running system health checks..."
  systemctl is-active --quiet apache2 && { log_success "Apache running"; ((total_score++)); } || log_error "Apache not running"
  ((max_score++))
  
  ufw status | grep -q "Status: active" && { log_success "UFW active"; ((total_score++)); } || log_warning "UFW inactive"
  ((max_score++))
  
  systemctl is-active --quiet fail2ban && { log_success "fail2ban running"; ((total_score++)); } || log_error "fail2ban not running"
  ((max_score++))
  
  # Service-specific checks
  if [[ "$INSTALL_KEYCLOAK" =~ ^[Yy]$ ]]; then
    systemctl is-active --quiet keycloak && { log_success "Keycloak running"; ((total_score++)); } || log_error "Keycloak not running"
    ((max_score++))
    
    systemctl is-active --quiet postgresql && { log_success "PostgreSQL running"; ((total_score++)); } || log_error "PostgreSQL not running"
    ((max_score++))
    
    curl -s "http://127.0.0.1:$KEYCLOAK_HTTP_PORT/" >/dev/null 2>&1 && { log_success "Keycloak backend responding"; ((total_score++)); } || log_error "Keycloak backend not responding"
    ((max_score++))
    
    PGPASSWORD="$DB_PASSWORD" psql -h localhost -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" >/dev/null 2>&1 && { log_success "Database connection OK"; ((total_score++)); } || log_error "Database connection failed"
    ((max_score++))
  fi
  
  if [[ "$INSTALL_SEQ" =~ ^[Yy]$ ]]; then
    docker ps --format '{{.Names}}' | grep -q '^seq && { log_success "Seq container running"; ((total_score++)); } || log_error "Seq container not running"
    ((max_score++))
    
    curl -s "http://127.0.0.1:$SEQ_BACKEND_PORT/" >/dev/null 2>&1 && { log_success "Seq backend responding"; ((total_score++)); } || log_error "Seq backend not responding"
    ((max_score++))
  fi
  
  if [[ "$INSTALL_WEBMIN" =~ ^[Yy]$ ]]; then
    systemctl is-active --quiet webmin && { log_success "Webmin running"; ((total_score++)); } || log_error "Webmin not running"
    ((max_score++))
  fi
  
  echo; echo -e "${BLUE}Overall Health Score:${NC} ${GREEN}$total_score/$max_score${NC}"
  log_to_file "Health check completed: $total_score/$max_score services healthy"
}

# =========================
# Diagnostic Scripts
# =========================
create_diagnostic_scripts(){
  log "Creating diagnostic scripts..."
  
  # Main diagnostic script
  cat > /root/server-diagnostic.sh <<EOF
#!/bin/bash
echo "=== UNIFIED SERVER DIAGNOSTIC REPORT ==="
echo "Generated: \$(date)"
echo "Hostname: \$(hostname)"
echo "IP: \$(curl -s ifconfig.me 2>/dev/null || echo "Unknown")"
echo

echo "=== SERVICES STATUS ==="
systemctl status apache2 --no-pager -l | head -15
echo
systemctl status fail2ban --no-pager -l | head -8
echo

if systemctl list-unit-files | grep -q keycloak; then
  echo "=== KEYCLOAK ==="
  systemctl status keycloak --no-pager -l | head -15
  systemctl status postgresql --no-pager -l | head -8
  echo
fi

if docker ps --format '{{.Names}}' | grep -q seq; then
  echo "=== SEQ ==="
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep seq
  echo
fi

if systemctl list-unit-files | grep -q webmin; then
  echo "=== WEBMIN ==="
  systemctl status webmin --no-pager -l | head -15
  echo
fi

echo "=== LISTENING PORTS ==="
ss -tulpen | grep -E "(:80|:443|:8080|:5342|:5341|:10000)\b" || echo "No relevant ports found"
echo

echo "=== APACHE VHOSTS ==="
apache2ctl -S 2>/dev/null || true
echo

echo "=== HTTP/HTTPS TESTS ==="
EOF

  # Add domain testing for each installed service
  if [[ "$INSTALL_KEYCLOAK" =~ ^[Yy]$ ]]; then
    cat >> /root/server-diagnostic.sh <<EOF
for proto in http https; do
  code=\$(timeout 7 curl -k -s -w "%{http_code}" "\$proto://$KEYCLOAK_HOSTNAME/" -o /dev/null 2>/dev/null || echo "timeout")
  echo "\$proto://$KEYCLOAK_HOSTNAME/ → \$code"
done
EOF
  fi
  
  if [[ "$INSTALL_SEQ" =~ ^[Yy]$ ]]; then
    cat >> /root/server-diagnostic.sh <<EOF
for proto in http https; do
  code=\$(timeout 7 curl -k -s -w "%{http_code}" "\$proto://$SEQ_HOSTNAME/" -o /dev/null 2>/dev/null || echo "timeout")
  echo "\$proto://$SEQ_HOSTNAME/ → \$code"
done
EOF
  fi
  
  if [[ "$INSTALL_WEBMIN" =~ ^[Yy]$ ]]; then
    cat >> /root/server-diagnostic.sh <<EOF
for proto in http https; do
  code=\$(timeout 7 curl -k -s -w "%{http_code}" "\$proto://$WEBMIN_HOSTNAME/" -o /dev/null 2>/dev/null || echo "timeout")
  echo "\$proto://$WEBMIN_HOSTNAME/ → \$code"
done
EOF
  fi

  cat >> /root/server-diagnostic.sh <<'EOF'
echo

echo "=== RECENT LOGS ==="
echo "Apache errors (last 50):"
tail -n 50 /var/log/apache2/error.log 2>/dev/null || echo "No Apache error log"
echo
EOF

  if [[ "$INSTALL_KEYCLOAK" =~ ^[Yy]$ ]]; then
    cat >> /root/server-diagnostic.sh <<EOF
if [ -f $KEYCLOAK_LOG_DIR/keycloak.log ]; then
  echo "Keycloak logs (last 50):"
  tail -n 50 $KEYCLOAK_LOG_DIR/keycloak.log
  echo
fi
EOF
  fi

  if [[ "$INSTALL_SEQ" =~ ^[Yy]$ ]]; then
    cat >> /root/server-diagnostic.sh <<'EOF'
if docker ps --format '{{.Names}}' | grep -q seq; then
  echo "Seq logs (last 50):"
  docker logs --tail 50 seq 2>/dev/null || echo "Cannot access Seq logs"
  echo
fi
EOF
  fi

  cat >> /root/server-diagnostic.sh <<'EOF'
echo "=== UFW STATUS ==="
ufw status verbose || echo "UFW not available"
EOF
  
  chmod +x /root/server-diagnostic.sh
  log_to_file "Diagnostic script created: /root/server-diagnostic.sh"
}

# =========================
# Final Summary and Log Completion
# =========================
complete_installation_log(){
  log_phase "FINALIZING INSTALLATION LOG"
  
  local ip=$(curl -s ifconfig.me 2>/dev/null || echo "Unknown")
  
  cat >> "$INSTALL_LOG" <<EOF

=================================
ACCESS INFORMATION
=================================
Server IP: $ip

EOF

  if [[ "$INSTALL_KEYCLOAK" =~ ^[Yy]$ ]]; then
    cat >> "$INSTALL_LOG" <<EOF
KEYCLOAK IDENTITY SERVER:
- URL: https://$KEYCLOAK_HOSTNAME/admin/
- Admin Username: $KEYCLOAK_ADMIN_USER
- Admin Password: $KEYCLOAK_ADMIN_PASSWORD
- Backend URL: http://127.0.0.1:$KEYCLOAK_HTTP_PORT/
- Database: $DB_NAME
- Database User: $DB_USER
- Database Password: $DB_PASSWORD
- Service: systemctl status keycloak
- Logs: journalctl -u keycloak -f

EOF
  fi

  if [[ "$INSTALL_SEQ" =~ ^[Yy]$ ]]; then
    cat >> "$INSTALL_LOG" <<EOF
SEQ LOG SERVER:
- URL: https://$SEQ_HOSTNAME/
- Admin Username: admin
- Admin Password: $SEQ_ADMIN_PASSWORD
- Backend URL: http://127.0.0.1:$SEQ_BACKEND_PORT/
- TCP Ingestion Port: $SEQ_TCP_INGEST_PORT
- Data Directory: $SEQ_DATA_DIR
- Container: docker logs -f seq
- Control: docker restart seq

EOF
  fi

  if [[ "$INSTALL_WEBMIN" =~ ^[Yy]$ ]]; then
    cat >> "$INSTALL_LOG" <<EOF
WEBMIN:
- URL: https://$WEBMIN_HOSTNAME/
- Username: root
- Password: (your root password)
- Backend URL: https://127.0.0.1:10000/
- Service: systemctl status webmin
- Config: /etc/webmin/

EOF
  fi

  cat >> "$INSTALL_LOG" <<EOF
=================================
MANAGEMENT COMMANDS
=================================
- Health Check: /root/server-diagnostic.sh
- View this log: cat $INSTALL_LOG
- Apache status: systemctl status apache2
- Apache logs: tail -f /var/log/apache2/error.log
- UFW status: ufw status verbose
- fail2ban: fail2ban-client status

=================================
SECURITY NOTES
=================================
- All services are behind Apache reverse proxy with SSL
- UFW firewall is configured (ports 22, 80, 443 open)
- fail2ban is active for protection against brute force
- This log contains sensitive passwords - delete after copying credentials

=================================
LOG FILE DELETION
=================================
To securely delete this log file after copying credentials:
  shred -vfz -n 3 $INSTALL_LOG
  rm -f $INSTALL_LOG

Installation completed: $(date)
EOF

  chmod 600 "$INSTALL_LOG"
  log_success "Installation log completed: $INSTALL_LOG"
}

display_final_summary(){
  local ip=$(curl -s ifconfig.me 2>/dev/null || echo "Unknown")
  clear; echo
  echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║              🎉 UNIFIED INSTALLATION COMPLETE! 🎉              ║${NC}"
  echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
  echo
  echo -e "${BLUE}📋 INSTALLED SERVICES:${NC}"
  [[ "$INSTALL_KEYCLOAK" =~ ^[Yy]$ ]] && echo "  ✅ Keycloak Identity Server → https://$KEYCLOAK_HOSTNAME/admin/"
  [[ "$INSTALL_SEQ" =~ ^[Yy]$ ]] && echo "  ✅ Seq Log Server → https://$SEQ_HOSTNAME/"
  [[ "$INSTALL_WEBMIN" =~ ^[Yy]$ ]] && echo "  ✅ Webmin → https://$WEBMIN_HOSTNAME/"
  echo
  echo -e "${YELLOW}🔐 CREDENTIALS (also in log file):${NC}"
  if [[ "$INSTALL_KEYCLOAK" =~ ^[Yy]$ ]]; then
    echo "  Keycloak: $KEYCLOAK_ADMIN_USER / $KEYCLOAK_ADMIN_PASSWORD"
  fi
  if [[ "$INSTALL_SEQ" =~ ^[Yy]$ ]]; then
    echo "  Seq: admin / $SEQ_ADMIN_PASSWORD"
  fi
  if [[ "$INSTALL_WEBMIN" =~ ^[Yy]$ ]]; then
    echo "  Webmin: root / (your root password)"
  fi
  echo
  echo -e "${CYAN}📄 IMPORTANT:${NC}"
  echo "  📁 Complete log with all details: ${YELLOW}$INSTALL_LOG${NC}"
  echo "  🔧 Diagnostic script: ${YELLOW}/root/server-diagnostic.sh${NC}"
  echo "  🗑️  Delete log securely: ${RED}shred -vfz -n 3 $INSTALL_LOG && rm -f $INSTALL_LOG${NC}"
  echo
  echo -e "${GREEN}🎯 Installation completed successfully!${NC}"
  echo
}

# =========================
# Main Installation Flow
# =========================
main(){
  trap 'log_error "Installation failed at line $LINENO. Check logs above."; exit 1' ERR
  
  echo -e "${CYAN}"
  echo "╔═══════════════════════════════════════════════════════════════════╗"
  echo "║           UNIFIED SERVER INSTALLATION SCRIPT v2.0                ║"
  echo "║                                                                   ║"
  echo "║  🔐 Keycloak Identity Server                                     ║"
  echo "║  📊 Seq Log Server                                               ║"
  echo "║  ⚙️  Webmin                                                       ║"
  echo "║                                                                   ║"
  echo "║  Features: Apache proxy, SSL, UFW, fail2ban, health checks       ║"
  echo "╚═══════════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  
  check_root
  prompt_unified_inputs
  
  # Phase 1: System Setup
  log_phase "SYSTEM SETUP"
  update_system
  install_shared_dependencies
  configure_unified_firewall
  configure_unified_fail2ban
  
  # Phase 2: Service Installations
  install_keycloak
  install_seq
  install_webmin
  
  # Phase 3: SSL Setup
  setup_ssl_certificates
  
  # Phase 4: Final Steps
  perform_health_checks
  create_diagnostic_scripts
  complete_installation_log
  display_final_summary
  
  log_success "🎉 Unified installation completed successfully!"
}

# Start installation
main "$@"