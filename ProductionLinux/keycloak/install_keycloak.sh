#!/bin/bash
# Keycloak Ultimate Production Installation Script for Ubuntu 22.04
# Fixes mixed-content (proper proxy headers) and allows controlled iframe embedding via CSP frame-ancestors
# Author: Production Deployment Script
# Version: 4.2 - Ultimate Edition (HTTPS/Mixed-Content + Framing Fix)
# Date: August 2025
set -euo pipefail

# =========================
# Configuration Variables
# =========================
KEYCLOAK_VERSION="26.3.1"
KEYCLOAK_USER="keycloak"
KEYCLOAK_GROUP="keycloak"
KEYCLOAK_HOME="/opt/keycloak"
KEYCLOAK_LOG_DIR="/var/log/keycloak"
KEYCLOAK_DATA_DIR="/var/lib/keycloak"

# Defaults (change safely at runtime)
DEFAULT_HOSTNAME="auth.sivargpt.com"
DEFAULT_DB_NAME="keycloak_prod"
DEFAULT_DB_USER="keycloak_user"
DEFAULT_DB_PASSWORD="1234567890"
DEFAULT_ADMIN_USER="keycloakadmin"
DEFAULT_ADMIN_PASSWORD="1234567890"
DEFAULT_HTTP_PORT="8080"

# Default allowed framers (space-separated list of origins). Keep quotes around 'self'
DEFAULT_ALLOWED_FRAME_ANCESTORS="'self' https://your-shell.example.com"

# User-configurable (prompted)
HOSTNAME=""
DB_NAME=""
DB_USER=""
DB_PASSWORD=""
ADMIN_USER=""
ADMIN_PASSWORD=""
HTTP_PORT=""
ALLOWED_FRAME_ANCESTORS=""

# =========================
# Output Cosmetics
# =========================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log(){ echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
log_success(){ echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1"; }
log_warning(){ echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"; }
log_error(){ echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"; }

# =========================
# Prompts
# =========================
prompt_inputs(){
  echo; log "=== Keycloak Ultimate Installation Configuration ==="; echo
  echo -e "${YELLOW}Press Enter to use default values shown in brackets${NC}"; echo
  read -p "Enter hostname [$DEFAULT_HOSTNAME]: " HOSTNAME; HOSTNAME=${HOSTNAME:-$DEFAULT_HOSTNAME}
  read -p "Enter database name [$DEFAULT_DB_NAME]: " DB_NAME; DB_NAME=${DB_NAME:-$DEFAULT_DB_NAME}
  read -p "Enter database username [$DEFAULT_DB_USER]: " DB_USER; DB_USER=${DB_USER:-$DEFAULT_DB_USER}
  read -p "Enter database password [$DEFAULT_DB_PASSWORD]: " DB_PASSWORD; DB_PASSWORD=${DB_PASSWORD:-$DEFAULT_DB_PASSWORD}
  read -p "Enter admin username [$DEFAULT_ADMIN_USER]: " ADMIN_USER; ADMIN_USER=${ADMIN_USER:-$DEFAULT_ADMIN_USER}
  read -p "Enter admin password [$DEFAULT_ADMIN_PASSWORD]: " ADMIN_PASSWORD; ADMIN_PASSWORD=${ADMIN_PASSWORD:-$DEFAULT_ADMIN_PASSWORD}
  read -p "Enter backend HTTP port [$DEFAULT_HTTP_PORT]: " HTTP_PORT; HTTP_PORT=${HTTP_PORT:-$DEFAULT_HTTP_PORT}
  read -p "Enter allowed frame ancestors (space-separated origins) [$DEFAULT_ALLOWED_FRAME_ANCESTORS]: " ALLOWED_FRAME_ANCESTORS
  ALLOWED_FRAME_ANCESTORS=${ALLOWED_FRAME_ANCESTORS:-$DEFAULT_ALLOWED_FRAME_ANCESTORS}

  echo; log "Configuration Summary:"
  echo "  Hostname: $HOSTNAME"
  echo "  Database: $DB_NAME (user: $DB_USER)"
  echo "  Admin User: $ADMIN_USER"
  echo "  Backend HTTP Port: $HTTP_PORT"
  echo "  Frame ancestors: $ALLOWED_FRAME_ANCESTORS"
  echo
  read -p "Continue with this configuration? (y/N): " confirm
  if [[ ! $confirm =~ ^[Yy]$ ]]; then log "Installation cancelled by user"; exit 0; fi
  log_success "Configuration confirmed"
}

check_root(){ if [[ $EUID -ne 0 ]]; then log_error "Run as root"; exit 1; fi; }

update_system(){
  log "Updating system packages..."
  apt-get update -y; apt-get upgrade -y
  log_success "System packages updated"
}

install_dependencies(){
  log "Installing dependencies..."
  apt-get install -y \
    openjdk-21-jdk postgresql postgresql-contrib apache2 certbot python3-certbot-apache \
    ufw fail2ban unzip wget curl openssl ca-certificates net-tools gnupg lsb-release
  a2enmod proxy proxy_http proxy_ajp rewrite deflate headers proxy_balancer proxy_connect proxy_html ssl
  a2enmod status
  log_success "Dependencies installed and Apache modules enabled"
}

setup_postgresql(){
  log "Configuring PostgreSQL..."
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
  log "Testing DB connectivity..."
  if PGPASSWORD="$DB_PASSWORD" psql -h localhost -U "$DB_USER" -d "$DB_NAME" -c "SELECT version();" >/dev/null 2>&1; then
    log_success "PostgreSQL configured and tested"
  else
    log_error "Database connection test failed"; exit 1
  fi
}

setup_keycloak_user(){
  log "Creating keycloak user and dirs..."
  groupadd -r $KEYCLOAK_GROUP 2>/dev/null || true
  useradd -r -g $KEYCLOAK_GROUP -d $KEYCLOAK_HOME -s /usr/sbin/nologin $KEYCLOAK_USER 2>/dev/null || true
  mkdir -p $KEYCLOAK_HOME $KEYCLOAK_LOG_DIR $KEYCLOAK_DATA_DIR $KEYCLOAK_HOME/conf $KEYCLOAK_HOME/data
  chown -R $KEYCLOAK_USER:$KEYCLOAK_GROUP $KEYCLOAK_HOME $KEYCLOAK_LOG_DIR $KEYCLOAK_DATA_DIR
  chmod 750 $KEYCLOAK_HOME $KEYCLOAK_DATA_DIR; chmod 755 $KEYCLOAK_LOG_DIR
  log_success "Keycloak user and dirs ready"
}

install_keycloak(){
  log "Installing Keycloak $KEYCLOAK_VERSION..."
  cd /tmp
  local url="https://github.com/keycloak/keycloak/releases/download/${KEYCLOAK_VERSION}/keycloak-${KEYCLOAK_VERSION}.tar.gz"
  local max=3; local n=1
  while (( n <= max )); do
    if wget -O keycloak.tar.gz "$url"; then break; fi
    if (( n == max )); then log_error "Download failed after $max attempts"; exit 1; fi
    log_warning "Download attempt $n failed, retrying..."; n=$((n+1)); sleep 5
  done
  tar -xzf keycloak.tar.gz
  cp -r keycloak-${KEYCLOAK_VERSION}/* $KEYCLOAK_HOME/
  chown -R $KEYCLOAK_USER:$KEYCLOAK_GROUP $KEYCLOAK_HOME
  chmod +x $KEYCLOAK_HOME/bin/*.sh
  rm -rf keycloak.tar.gz keycloak-${KEYCLOAK_VERSION}
  log_success "Keycloak installed"
}

configure_keycloak(){
  log "Writing keycloak.conf (with HTTPS/mixed-content fix)..."
  cat > $KEYCLOAK_HOME/conf/keycloak.conf <<EOF
# ---------- Database ----------
db=postgres
db-username=$DB_USER
db-password=$DB_PASSWORD
db-url=jdbc:postgresql://localhost:5432/$DB_NAME
db-pool-initial-size=5
db-pool-min-size=5
db-pool-max-size=20

# ---------- Host/Proxy ----------
hostname=$HOSTNAME
hostname-strict=false
hostname-strict-backchannel=false
# IMPORTANT: honor Apache's X-Forwarded-* headers
proxy-headers=xforwarded
# IMPORTANT: when the request arrives via HTTPS at the proxy, generate HTTPS URLs
hostname-strict-https=true

# ---------- HTTP (backend) ----------
http-enabled=true
http-port=$HTTP_PORT

# ---------- Health/metrics ----------
health-enabled=true
metrics-enabled=true
http-max-queued-requests=1000

# ---------- Logging ----------
log=console,file
log-level=INFO
log-file=$KEYCLOAK_LOG_DIR/keycloak.log
log-file-format=%d{yyyy-MM-dd HH:mm:ss,SSS} %-5p [%c] (%t) %s%e%n

# ---------- Cache ----------
cache=local

# ---------- Transactions ----------
transaction-xa-enabled=false

# ---------- Features ----------
features=token-exchange,admin-fine-grained-authz
EOF
  chown $KEYCLOAK_USER:$KEYCLOAK_GROUP $KEYCLOAK_HOME/conf/keycloak.conf
  chmod 640 $KEYCLOAK_HOME/conf/keycloak.conf
  log_success "keycloak.conf written"
}

build_keycloak(){
  log "Building Keycloak (optimized)..."
  sudo -u $KEYCLOAK_USER $KEYCLOAK_HOME/bin/kc.sh build \
    --db=postgres \
    --health-enabled=true \
    --metrics-enabled=true \
    --features=token-exchange,admin-fine-grained-authz
  log_success "Keycloak build complete"
}

create_systemd_service(){
  log "Creating systemd service..."
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
Environment=KC_BOOTSTRAP_ADMIN_USERNAME=$ADMIN_USER
Environment=KC_BOOTSTRAP_ADMIN_PASSWORD=$ADMIN_PASSWORD
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
  log_success "Systemd service installed"
}

configure_apache(){
  log "Configuring Apache reverse proxy (no mixed-content)..."

  # Disable default site
  a2dissite 000-default.conf 2>/dev/null || true

  # Port 80 vhost: ACME + (conditional) redirect to HTTPS
  cat > /etc/apache2/sites-available/keycloak-80.conf <<EOF
<VirtualHost *:80>
    ServerName $HOSTNAME
    ServerAlias www.$HOSTNAME

    # ACME path (exclude from proxy)
    ProxyPreserveHost On
    ProxyRequests Off
    ProxyPass /.well-known/acme-challenge/ !
    DocumentRoot /var/www/html

    # Security headers (no X-Frame-Options here; managed globally by CSP)
    Header always set X-Content-Type-Options nosniff
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"

    # Forward headers reflect the real scheme/port dynamically
    RequestHeader set X-Forwarded-Proto expr=%{REQUEST_SCHEME}
    RequestHeader set X-Forwarded-Port  expr=%{SERVER_PORT}
    RequestHeader set X-Forwarded-Host  "%{HTTP_HOST}s"

    # Proxy to backend (HTTP)
    ProxyPass        / http://127.0.0.1:$HTTP_PORT/
    ProxyPassReverse / http://127.0.0.1:$HTTP_PORT/

    # Optional redirect HTTP->HTTPS once cert exists (helper conf toggles env)
    RewriteEngine On
    RewriteCond %{ENV:HTTPS_CERT_READY} =1
    RewriteRule ^/(.*)$ https://%{HTTP_HOST}/\$1 [R=301,L]

    # Logs
    ErrorLog \${APACHE_LOG_DIR}/keycloak_error.log
    CustomLog \${APACHE_LOG_DIR}/keycloak_access.log combined
</VirtualHost>
EOF

  a2ensite keycloak-80.conf

  if apache2ctl configtest; then
    systemctl restart apache2
    systemctl enable apache2
    log_success "Apache port 80 vhost configured"
  else
    log_error "Apache configuration test failed"; exit 1
  fi
}

# NEW: Global header conf to allow controlled framing and unset X-Frame-Options
configure_framing_headers(){
  log "Configuring CSP frame-ancestors headers (and unsetting X-Frame-Options)..."

  cat > /etc/apache2/conf-available/keycloak-headers.conf <<EOF
<IfModule mod_headers.c>
    # Remove Keycloak's default X-Frame-Options: DENY so CSP can govern framing
    Header always unset X-Frame-Options

    # Allow only these origins to frame Keycloak (use quotes around 'self')
    # Example value becomes: frame-ancestors ${ALLOWED_FRAME_ANCESTORS}
    Header always set Content-Security-Policy "frame-ancestors ${ALLOWED_FRAME_ANCESTORS}"
</IfModule>
EOF

  a2enconf keycloak-headers.conf || true

  if apache2ctl configtest; then
    systemctl reload apache2
    log_success "Framing headers configured (CSP frame-ancestors) and Apache reloaded"
  else
    log_warning "Apache config test failed for framing headers; keeping previous config"
  fi
}

configure_firewall(){
  log "Configuring UFW..."
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 22/tcp comment 'SSH'
  ufw allow 80/tcp comment 'HTTP'
  ufw allow 443/tcp comment 'HTTPS'
  ufw allow from 127.0.0.1 to any port 5432 comment 'PostgreSQL local'
  ufw --force enable
  log_success "UFW configured"
}

configure_fail2ban(){
  log "Configuring fail2ban..."
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

  systemctl restart fail2ban
  systemctl enable fail2ban
  log_success "fail2ban configured"
}

start_and_verify(){
  log "Starting Keycloak..."
  systemctl start keycloak

  log "Waiting for Keycloak to become active..."
  local max_wait=120; local waited=0
  while (( waited < max_wait )); do
    if systemctl is-active --quiet keycloak; then
      log_success "Keycloak service is running"; break
    fi
    sleep 5; waited=$((waited+5))
  done

  if ! systemctl is-active --quiet keycloak; then
    log_error "Keycloak failed to start"
    systemctl status keycloak --no-pager -l || true
    journalctl -u keycloak --no-pager -l --since "10 minutes ago" || true
    exit 1
  fi

  log "Testing backend connectivity..."
  if curl -s -w "%{http_code}" "http://127.0.0.1:$HTTP_PORT/" -o /dev/null | grep -qE "^(200|302)$"; then
    log_success "Backend responding"
  else
    log_warning "Backend not returning 200/302 yet"
  fi

  # Test Apache
  if curl -s -w "%{http_code}" "http://127.0.0.1/" -o /dev/null | grep -qE "^(200|301|302)$"; then
    log_success "Apache proxy reachable"
  else
    log_warning "Apache proxy check returned non-2xx/3xx"
  fi

  # Health endpoint
  if curl -s "http://127.0.0.1:9000/q/health" | grep -q "UP"; then
    log_success "Management health is UP"
  else
    log_warning "Management interface not responding UP yet"
  fi
}

discover_working_endpoints(){
  log "Discovering endpoints..."
  local ip=$(curl -s ifconfig.me 2>/dev/null || echo "Unknown")
  local urls=(
    "http://localhost:$HTTP_PORT/"
    "http://localhost:$HTTP_PORT/realms/master"
    "http://localhost/"
    "http://$ip/"
    "http://$HOSTNAME/"
  )
  for u in "${urls[@]}"; do
    local code
    code=$(timeout 10 curl -s -w "%{http_code}" "$u" -o /dev/null 2>/dev/null || echo "timeout")
    [[ $code =~ ^(200|301|302)$ ]] && log_success "$u → $code" || log_warning "$u → $code"
  done
}

create_diagnostic_script(){
  log "Creating diagnostic script..."
  cat > /root/keycloak-diagnostic.sh <<'EOF'
#!/bin/bash
echo "=== KEYCLOAK ULTIMATE DIAGNOSTIC REPORT ==="
echo "Generated: $(date)"
echo "Server: $(hostname)"
echo

echo "1) Services"
systemctl status keycloak --no-pager -l | head -15
echo
systemctl status apache2 --no-pager -l | head -8
echo
systemctl status postgresql --no-pager -l | head -8
echo

echo "2) Ports"
netstat -tuln | grep -E "(8080|80|443|9000)" || echo "No relevant ports found"
echo

echo "3) HTTP/HTTPS checks"
host=$(grep '^hostname=' /opt/keycloak/conf/keycloak.conf 2>/dev/null | cut -d= -f2)
[[ -z "$host" ]] && host="localhost"
for u in \
  "http://$host/" \
  "https://$host/" \
  "http://$host/admin/" \
  "https://$host/admin/" \
  "http://localhost:8080/admin/master/console/"; do
  code=$(timeout 7 curl -k -s -w "%{http_code}" "$u" -o /dev/null || echo "timeout")
  echo "$u → $code"
done
echo

echo "4) Health"
if curl -s "http://localhost:9000/q/health" | grep -q "UP"; then
  echo "Health: UP"
else
  echo "Health: not UP"
fi
echo

echo "5) Keycloak config (non-sensitive)"
if [[ -f /opt/keycloak/conf/keycloak.conf ]]; then
  egrep "^(hostname|http-enabled|http-port|proxy-headers|hostname-strict-https)" /opt/keycloak/conf/keycloak.conf
else
  echo "Config file missing"
fi
echo

echo "6) Apache vhost"
apache2ctl -S 2>/dev/null || true
echo

echo "7) Recent logs"
journalctl -u keycloak --no-pager -l --since "10 minutes ago" | tail -50
echo
EOF
  chmod +x /root/keycloak-diagnostic.sh
  log_success "Diagnostic script at /root/keycloak-diagnostic.sh"
}

setup_ssl_certificate(){
  log "Setting up SSL with Let's Encrypt..."
  local server_ip=$(curl -s ifconfig.me 2>/dev/null || echo "Unknown")
  local domain_ip=$(getent ahostsv4 "$HOSTNAME" 2>/dev/null | awk '{print $1; exit}')
  if [[ -n "$domain_ip" && "$domain_ip" != "$server_ip" ]]; then
    log_warning "DNS mismatch: $HOSTNAME → $domain_ip (server: $server_ip)"
    read -p "Continue anyway? (y/N): " ans
    [[ ! $ans =~ ^[Yy]$ ]] && { log "Skipping SSL setup"; return 0; }
  fi

  mkdir -p /var/www/html
  chown www-data:www-data /var/www/html

  log "Testing HTTP reachability..."
  if timeout 10 curl -s "http://$HOSTNAME/" >/dev/null 2>&1; then
    log_success "Domain is accessible over HTTP"
    if certbot --apache -d "$HOSTNAME" --non-interactive --agree-tos --email admin@"$HOSTNAME" --redirect; then
      log_success "SSL certificate issued and redirect enabled"
      # Toggle env for HTTP->HTTPS redirect in keycloak-80.conf if needed
      echo "SetEnvIfExpr \"%{REQUEST_SCHEME} = 'http'\" HTTPS_CERT_READY 1" > /etc/apache2/conf-available/kc-https-ready.conf
      a2enconf kc-https-ready.conf || true
      systemctl reload apache2
    else
      log_error "Certbot failed"; return 1
    fi
  else
    log_error "HTTP check failed for $HOSTNAME. Check DNS/Firewall/Apache."
    return 1
  fi
}

perform_final_health_check(){
  log "Running final health check..."
  local score=0; local max=10
  systemctl is-active --quiet keycloak && { log_success "Keycloak running"; ((score++)); } || log_error "Keycloak not running"
  PGPASSWORD="$DB_PASSWORD" psql -h localhost -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" >/dev/null 2>&1 && { log_success "DB OK"; ((score++)); } || log_error "DB failed"
  curl -s "http://127.0.0.1:$HTTP_PORT/" >/dev/null 2>&1 && { log_success "Backend HTTP OK"; ((score++)); } || log_error "Backend HTTP failed"
  curl -s "http://127.0.0.1/" >/dev/null 2>&1 && { log_success "Apache proxy OK"; ((score++)); } || log_error "Apache proxy failed"
  curl -s "http://127.0.0.1:9000/q/health" | grep -q "UP" && { log_success "Mgmt health OK"; ((score++)); } || log_warning "Mgmt health not UP"
  sudo -u $KEYCLOAK_USER $KEYCLOAK_HOME/bin/kc.sh show-config >/dev/null 2>&1 && { log_success "KC config valid"; ((score++)); } || log_error "KC config invalid"
  systemctl is-active --quiet postgresql && { log_success "PostgreSQL running"; ((score++)); } || log_error "PostgreSQL not running"
  systemctl is-active --quiet apache2 && { log_success "Apache running"; ((score++)); } || log_error "Apache not running"
  ufw status | grep -q "Status: active" && { log_success "Firewall active"; ((score++)); } || log_warning "Firewall inactive"
  curl -s "http://127.0.0.1:$HTTP_PORT/admin/" | grep -qi "keycloak" 2>/dev/null && { log_success "Admin console reachable"; ((score++)); } || log_warning "Admin console not confirmed"

  echo; echo -e "${BLUE}Health Score:${NC} ${GREEN}$score/10${NC}"
}

display_ultimate_summary(){
  local ip=$(curl -s ifconfig.me 2>/dev/null || echo "Unknown")
  clear; echo
  echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║                🎉 KEYCLOAK INSTALLATION COMPLETE! 🎉           ║${NC}"
  echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
  echo
  echo -e "${BLUE}📋 SUMMARY:${NC}"
  echo "  • Keycloak: $KEYCLOAK_VERSION"
  echo "  • Hostname: $HOSTNAME"
  echo "  • Backend:  http://127.0.0.1:$HTTP_PORT"
  echo "  • Reverse Proxy: Apache"
  echo "  • Server IP: $ip"
  echo "  • Frame ancestors: $ALLOWED_FRAME_ANCESTORS"
  echo
  echo -e "${YELLOW}🔗 ACCESS:${NC}"
  echo "  • HTTP (until SSL):  http://$HOSTNAME/admin/"
  echo "  • After SSL:         https://$HOSTNAME/admin/"
  echo "  • Direct (local):    http://localhost:$HTTP_PORT/admin/master/console/"
  echo
  echo -e "${YELLOW}👤 LOGIN:${NC} $ADMIN_USER / $ADMIN_PASSWORD"
  echo
  echo -e "${YELLOW}🛠  Commands:${NC} status|restart logs"
  echo "     systemctl status keycloak"
  echo "     systemctl restart keycloak"
  echo "     journalctl -u keycloak -f"
  echo "     /root/keycloak-diagnostic.sh"
  echo
  echo -e "${YELLOW}🔒 Mixed-Content & Framing Fixes Applied:${NC}"
  echo "  ✓ proxy-headers=xforwarded"
  echo "  ✓ hostname-strict-https=true"
  echo "  ✓ Apache sets X-Forwarded-Proto/Port dynamically"
  echo "  ✓ CSP frame-ancestors (${ALLOWED_FRAME_ANCESTORS})"
  echo "  ✓ X-Frame-Options unset at proxy (CSP governs framing)"
  echo
}

main(){
  log "Starting Keycloak Ultimate Installation (v4.2)"; echo
  check_root
  prompt_inputs

  echo -e "${YELLOW}🔧 PHASE 1: System Preparation${NC}"; update_system; install_dependencies; echo
  echo -e "${YELLOW}🗄  PHASE 2: Database${NC}"; setup_postgresql; echo
  echo -e "${YELLOW}⚡ PHASE 3: Keycloak Install${NC}"; setup_keycloak_user; install_keycloak; configure_keycloak; build_keycloak; echo
  echo -e "${YELLOW}🔌 PHASE 4: Service Configuration${NC}"
  create_systemd_service
  configure_apache
  configure_framing_headers
  echo
  echo -e "${YELLOW}🔒 PHASE 5: Security${NC}"; configure_firewall; configure_fail2ban; echo
  echo -e "${YELLOW}🚀 PHASE 6: Startup & Verify${NC}"; start_and_verify; discover_working_endpoints; echo

  echo -e "${YELLOW}🔐 PHASE 7: SSL (optional now)${NC}"
  read -p "Run Let's Encrypt SSL setup now? (y/N): " ssl
  if [[ $ssl =~ ^[Yy]$ ]]; then setup_ssl_certificate; else log_warning "Skipping SSL for now. You can run certbot later."; fi
  echo

  echo -e "${YELLOW}📊 PHASE 8: Final Checks${NC}"
  create_diagnostic_script
  perform_final_health_check
  display_ultimate_summary

  log_success "🎉 Ultimate Keycloak installation completed!"
}

trap 'log_error "Installation failed at line $LINENO. Check the logs above." ; exit 1' ERR
main "$@"
