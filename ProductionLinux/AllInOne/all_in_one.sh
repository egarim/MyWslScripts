#!/bin/bash
# Merged Installer (Webmin + Seq + Keycloak) — FIXED
# - Prompts once (no redundant questions)
# - Prevents Webmin→Keycloak redirect by creating proper 443 vhost for Webmin
# - Writes /root/stack_install_YYYYMMDD_HHMMSS.log with ALL details (incl. passwords)
# Date: 2025-08-18 23:57:37
set -euo pipefail

: "${APACHE_LOG_DIR:=/var/log/apache2}"

ensure_apache_running() {
  if ! systemctl is-active --quiet apache2; then
    systemctl start apache2 || systemctl restart apache2 || true
  fi
}

cert_exists() {
  local dom="$1"
  certbot certificates 2>/dev/null | awk '/Domains: /{for(i=2;i<=NF;i++) print $i}' | tr ' ' '\n' | grep -Fxq "$dom"
}

issue_cert() {
  local dom="$1"
  local email="$2"
  # Decide environment
  local extra=""
  if [[ "${CERTBOT_ENV:-production}" == "staging" ]]; then
    extra="--staging"
  elif [[ "${CERTBOT_ENV:-production}" == "none" ]]; then
    echo "Skipping certificate for $dom (CERTBOT_ENV=none)"
    return 0
  fi

  ensure_apache_running
  if cert_exists "$dom"; then
    echo "Certificate already present for $dom; skipping issuance."
    return 0
  fi

  certbot --apache -d "$dom" --agree-tos -m "$email" --redirect -n $extra
}

: "${APACHE_LOG_DIR:=/var/log/apache2}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log(){ echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
ok(){ echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] OK:${NC} $1"; }
warn(){ echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $1"; }
err(){ echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"; }

[[ $EUID -eq 0 ]] || { err "Run as root"; exit 1; }

# ------------- Unified prompts -------------
echo
log "=== Unified configuration (press Enter for defaults) ==="

# Global ACME email (used for cert issuance)
read -p "ACME email for TLS [admin@example.com]: " ACME_EMAIL; ACME_EMAIL=${ACME_EMAIL:-admin@example.com}

read -p "Let's Encrypt env: production (p) / staging (s) / none (n) [s]: " CERT_CHOICE; CERT_CHOICE=${CERT_CHOICE:-s}
case "$CERT_CHOICE" in
  [Pp]) CERTBOT_ENV=production ;;
  [Nn]) CERTBOT_ENV=none ;;
  *)    CERTBOT_ENV=staging ;;
esac

# Webmin
read -p "Webmin hostname [webmin.example.com]: " W_HOST; W_HOST=${W_HOST:-webmin.example.com}
read -p "Proxy Webmin via Apache? (Y/N) [Y]: " W_PROXY; W_PROXY=${W_PROXY:-Y}
if [[ "$W_PROXY" =~ ^[Yy]$ ]]; then
  read -p "Obtain Let's Encrypt cert for Webmin now? (Y/N) [Y]: " W_SSL; W_SSL=${W_SSL:-Y}
else
  W_SSL="N"
fi

# Seq
read -p "Seq hostname [logs.example.com]: " S_HOST; S_HOST=${S_HOST:-logs.example.com}
read -p "Seq data dir [/var/lib/seq]: " S_DATA; S_DATA=${S_DATA:-/var/lib/seq}
read -p "Seq UI backend port (host->container:80) [5342]: " S_UI; S_UI=${S_UI:-5342}
read -p "Seq TCP ingest port (host->container:5341) [5341]: " S_TCP; S_TCP=${S_TCP:-5341}
read -p "Open TCP ingest to CIDR? (Y/N) [N]: " S_OPEN_TCP; S_OPEN_TCP=${S_OPEN_TCP:-N}
if [[ "$S_OPEN_TCP" =~ ^[Yy]$ ]]; then
  read -p "CIDR allowed for TCP ingest [10.0.0.0/24]: " S_TCP_CIDR; S_TCP_CIDR=${S_TCP_CIDR:-10.0.0.0/24}
else
  S_TCP_CIDR=""
fi
read -p "Seq initial admin password [ChangeMe!123]: " S_ADMIN_PASS; S_ADMIN_PASS=${S_ADMIN_PASS:-ChangeMe!123}
read -p "Obtain Let's Encrypt cert for Seq now? (Y/N) [N]: " S_SSL; S_SSL=${S_SSL:-N}

# Keycloak
read -p "Keycloak hostname [auth.example.com]: " K_HOST; K_HOST=${K_HOST:-auth.example.com}
read -p "Keycloak DB name [keycloak_prod]: " K_DB; K_DB=${K_DB:-keycloak_prod}
read -p "Keycloak DB user [keycloak_user]: " K_DB_USER; K_DB_USER=${K_DB_USER:-keycloak_user}
read -p "Keycloak DB password [ChangeMe_DB!123]: " K_DB_PASS; K_DB_PASS=${K_DB_PASS:-ChangeMe_DB!123}
read -p "Keycloak admin user [keycloakadmin]: " K_ADMIN; K_ADMIN=${K_ADMIN:-keycloakadmin}
read -p "Keycloak admin password [ChangeMe_KC!123]: " K_ADMIN_PASS; K_ADMIN_PASS=${K_ADMIN_PASS:-ChangeMe_KC!123}
read -p "Keycloak backend HTTP port [8080]: " K_HTTP; K_HTTP=${K_HTTP:-8080}
read -p "Keycloak frame-ancestors ['self' https://your-shell.example.com]: " K_FRAME; K_FRAME=${K_FRAME:-'self' https://your-shell.example.com}

# UFW
read -p "Enable/update UFW firewall? (Y/N) [Y]: " UFW_EN; UFW_EN=${UFW_EN:-Y}

echo
log "=== Summary ==="
echo "Webmin:   host=$W_HOST proxy=$W_PROXY ssl_now=$W_SSL"
echo "Seq:      host=$S_HOST data=$S_DATA ui=$S_UI tcp=$S_TCP ${S_TCP_CIDR:+(CIDR $S_TCP_CIDR)} ssl_now=$S_SSL"
echo "Keycloak: host=$K_HOST db=$K_DB/$K_DB_USER http_port=$K_HTTP frame_ancestors=$K_FRAME"
echo "UFW:      $UFW_EN"
read -p "Continue with installation? (y/N): " confirm
[[ $confirm =~ ^[Yy]$ ]] || { log "Cancelled."; exit 0; }

# ------------- Write install log (contains passwords) -------------
LOG_FILE="/root/stack_install_$(date +%Y%m%d_%H%M%S).log"
umask 077
{
  echo "=== MERGED INSTALL LOG ==="
  echo "Generated: $(date) on $(hostname)"
  echo
  echo "[ACME]"
  echo "ACME_EMAIL=$ACME_EMAIL"
  echo
  echo "[WEBMIN]"
  echo "HOST=$W_HOST"
  echo "PROXY=$W_PROXY"
  echo "SSL_NOW=$W_SSL"
  echo
  echo "[SEQ]"
  echo "HOST=$S_HOST"
  echo "DATA=$S_DATA"
  echo "UI_PORT=$S_UI"
  echo "TCP_PORT=$S_TCP"
  echo "OPEN_TCP=$S_OPEN_TCP"
  echo "TCP_CIDR=$S_TCP_CIDR"
  echo "ADMIN_PASSWORD=$S_ADMIN_PASS"
  echo "SSL_NOW=$S_SSL"
  echo
  echo "[KEYCLOAK]"
  echo "HOST=$K_HOST"
  echo "DB=$K_DB"
  echo "DB_USER=$K_DB_USER"
  echo "DB_PASSWORD=$K_DB_PASS"
  echo "ADMIN_USER=$K_ADMIN"
  echo "ADMIN_PASSWORD=$K_ADMIN_PASS"
  echo "HTTP_PORT=$K_HTTP"
  echo "FRAME_ANCESTORS=$K_FRAME"
  echo
  echo "[DELETE THIS FILE]"
  echo "This file contains secrets. To securely delete:"
  echo "  shred -u $LOG_FILE"
  echo "  history -c; history -w"
} > "$LOG_FILE"
ok "Wrote install log to $LOG_FILE"

# ------------- Base system prep -------------
log "Installing base packages (Apache, Docker, PostgreSQL, Certbot, Java)…"
apt-get update -y && apt-get upgrade -y
apt-get install -y ca-certificates curl gnupg lsb-release software-properties-common \
  apache2 certbot python3-certbot-apache ufw fail2ban \
  docker.io postgresql postgresql-contrib openjdk-21-jdk jq
systemctl enable --now apache2 docker postgresql
a2enmod proxy proxy_http headers rewrite ssl proxy_html >/dev/null 2>&1 || true
a2dissite 000-default.conf >/dev/null 2>&1 || true

# ------------- UFW -------------
if [[ "$UFW_EN" =~ ^[Yy]$ ]]; then
  if ! ufw status | grep -q "Status: active"; then
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
  fi
  ufw allow 22/tcp; ufw allow 80/tcp; ufw allow 443/tcp
  if [[ "$S_OPEN_TCP" =~ ^[Yy]$ && -n "$S_TCP_CIDR" ]]; then
    ufw allow from "$S_TCP_CIDR" to any port "$S_TCP" proto tcp
  fi
  ufw --force enable
  ok "UFW configured"
else
  warn "Skipping UFW config"
fi

# ------------- Webmin (bind local + Apache proxy + dedicated 443 vhost) -------------
log "Installing Webmin…"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.webmin.com/jcameron-key.asc | gpg --dearmor | tee /etc/apt/keyrings/webmin.gpg >/dev/null
chmod 644 /etc/apt/keyrings/webmin.gpg
echo "deb [signed-by=/etc/apt/keyrings/webmin.gpg] https://download.webmin.com/download/repository sarge contrib" > /etc/apt/sources.list.d/webmin.list
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y webmin

# Bind to loopback with SSL (self-signed) and set redirect host
conf="/etc/webmin/miniserv.conf"; cfg="/etc/webmin/config"
grep -q '^bind=' "$conf" && sed -i 's/^bind=.*/bind=127.0.0.1/' "$conf" || echo "bind=127.0.0.1" >> "$conf"
grep -q '^port=' "$conf" && sed -i 's/^port=.*/port=10000/' "$conf" || echo "port=10000" >> "$conf"
grep -q '^listen=' "$conf" && sed -i 's/^listen=.*/listen=10000/' "$conf" || echo "listen=10000" >> "$conf"
grep -q '^ssl=' "$conf" && sed -i 's/^ssl=.*/ssl=1/' "$conf" || echo "ssl=1" >> "$conf"
grep -q '^redirect_host=' "$conf" && sed -i "s/^redirect_host=.*/redirect_host=${W_HOST}/" "$conf" || echo "redirect_host=${W_HOST}" >> "$conf"
sed -i 's/^webprefixnoredir=.*/webprefixnoredir=1/; t; $ a webprefixnoredir=1' "$cfg" || true
if grep -q '^referers=' "$cfg"; then sed -i "s/^referers=.*/referers=${W_HOST}/" "$cfg"; else echo "referers=${W_HOST}" >> "$cfg"; fi
systemctl restart webmin

# HTTP vhost + create explicit HTTPS vhost to avoid SNI fallback
cat > /etc/apache2/sites-available/webmin.conf <<EOF
<VirtualHost *:80>
    ServerName ${W_HOST}
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
    ProxyPassReverseCookieDomain 127.0.0.1 ${W_HOST}
    ProxyPassReverseCookiePath / /
    ErrorLog ${APACHE_LOG_DIR}/webmin_error.log
    CustomLog ${APACHE_LOG_DIR}/webmin_access.log combined
</VirtualHost>
EOF

cat > /etc/apache2/sites-available/webmin-le-ssl.conf <<EOF
<IfModule mod_ssl.c>
<VirtualHost *:443>
    ServerName ${W_HOST}
    SSLEngine on
    ProxyPreserveHost On
    ProxyRequests Off
    ProxyTimeout 300
    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Forwarded-Port  "443"
    RequestHeader set X-Forwarded-Host  "${W_HOST}"
    SSLProxyEngine On
    SSLProxyVerify none
    SSLProxyCheckPeerName off
    SSLProxyCheckPeerCN off
    SSLProxyCheckPeerExpire off
    ProxyPass        / https://127.0.0.1:10000/ retry=1 acquire=3000 timeout=600 keepalive=On
    ProxyPassReverse / https://127.0.0.1:10000/
    ProxyPassReverseCookieDomain 127.0.0.1 ${W_HOST}
    ProxyPassReverseCookiePath / /
    ErrorLog ${APACHE_LOG_DIR}/webmin_error.log
    CustomLog ${APACHE_LOG_DIR}/webmin_access.log combined
</VirtualHost>
</IfModule>
EOF

a2ensite webmin.conf >/dev/null 2>&1 || true
a2ensite webmin-le-ssl.conf >/dev/null 2>&1 || true

# Issue/attach Let's Encrypt for Webmin if requested
if [[ "$W_PROXY" =~ ^[Yy]$ && "$W_SSL" =~ ^[Yy]$ ]]; then
  issue_cert "$W_HOST" "$ACME_EMAIL" || true
fi

ensure_apache_running; apache2ctl configtest; systemctl reload apache2 || systemctl start apache2 || systemctl restart apache2 || true

# ------------- Seq (Docker + Apache proxy) -------------
log "Deploying Seq…"
docker rm -f seq >/dev/null 2>&1 || true
mkdir -p "$S_DATA"
docker run -d --name seq \
  -e ACCEPT_EULA=Y \
  -e SEQ_FIRSTRUN_ADMINPASSWORD="${S_ADMIN_PASS}" \
  -e SEQ_BASEURI="https://${S_HOST}/" \
  -p "127.0.0.1:${S_UI}:80" \
  -p "${S_TCP}:5341" \
  -v "${S_DATA}:/data" \
  --restart unless-stopped \
  datalust/seq:latest

cat > /etc/apache2/sites-available/seq.conf <<EOF
<VirtualHost *:80>
    ServerName ${S_HOST}
    ProxyPreserveHost On
    ProxyRequests Off
    ProxyTimeout 300
    ProxyPass /.well-known/acme-challenge/ !
    DocumentRoot /var/www/html
    RequestHeader set X-Forwarded-Proto expr=%{REQUEST_SCHEME}
    RequestHeader set X-Forwarded-Port  expr=%{SERVER_PORT}
    RequestHeader set X-Forwarded-Host  "%{HTTP_HOST}s"
    ProxyPass        / http://127.0.0.1:${S_UI}/ keepalive=On
    ProxyPassReverse / http://127.0.0.1:${S_UI}/
    ErrorLog ${APACHE_LOG_DIR}/seq_error.log
    CustomLog ${APACHE_LOG_DIR}/seq_access.log combined
</VirtualHost>
EOF
a2ensite seq.conf >/dev/null 2>&1 || true
ensure_apache_running; apache2ctl configtest; systemctl reload apache2 || systemctl start apache2 || systemctl restart apache2 || true
if [[ "$S_SSL" =~ ^[Yy]$ ]]; then
  issue_cert "$S_HOST" "$ACME_EMAIL" || true
fi

# ------------- Keycloak (tarball + systemd + Apache proxy + CSP frame-ancestors) -------------
log "Setting up PostgreSQL for Keycloak…"
sudo -u postgres psql <<EOF
DROP DATABASE IF EXISTS $K_DB;
DROP USER IF EXISTS $K_DB_USER;
CREATE DATABASE $K_DB WITH ENCODING 'UTF8' TEMPLATE=template0;
CREATE USER $K_DB_USER WITH PASSWORD '$K_DB_PASS';
GRANT ALL PRIVILEGES ON DATABASE $K_DB TO $K_DB_USER;
ALTER DATABASE $K_DB OWNER TO $K_DB_USER;
EOF

KC_HOME="/opt/keycloak"; KC_LOG="/var/log/keycloak"; KC_USER="keycloak"; KC_GROUP="keycloak"
groupadd -r "$KC_GROUP" 2>/dev/null || true
useradd -r -g "$KC_GROUP" -d "$KC_HOME" -s /usr/sbin/nologin "$KC_USER" 2>/dev/null || true
mkdir -p "$KC_HOME" "$KC_LOG" /var/lib/keycloak "$KC_HOME/conf"
chown -R "$KC_USER:$KC_GROUP" "$KC_HOME" "$KC_LOG" /var/lib/keycloak

KC_VER="26.3.1"
cd /tmp && wget -q -O kc.tgz "https://github.com/keycloak/keycloak/releases/download/${KC_VER}/keycloak-${KC_VER}.tar.gz"
tar -xzf kc.tgz && cp -r keycloak-${KC_VER}/* "$KC_HOME"/ && rm -rf kc.tgz keycloak-${KC_VER}
chown -R "$KC_USER:$KC_GROUP" "$KC_HOME"
chmod +x "$KC_HOME/bin/"*.sh

cat > "$KC_HOME/conf/keycloak.conf" <<EOF
db=postgres
db-username=$K_DB_USER
db-password=$K_DB_PASS
db-url=jdbc:postgresql://localhost:5432/$K_DB
hostname=$K_HOST
hostname-strict=false
hostname-strict-backchannel=false
proxy-headers=xforwarded
hostname-strict-https=true
http-enabled=true
http-port=$K_HTTP
health-enabled=true
metrics-enabled=true
log=console,file
log-level=INFO
log-file=$KC_LOG/keycloak.log
cache=local
EOF
chown "$KC_USER:$KC_GROUP" "$KC_HOME/conf/keycloak.conf"
sudo -u "$KC_USER" "$KC_HOME/bin/kc.sh" build --db=postgres --health-enabled=true --metrics-enabled=true

cat > /etc/systemd/system/keycloak.service <<EOF
[Unit]
Description=Keycloak
After=network.target postgresql.service
Wants=postgresql.service
[Service]
Type=exec
User=$KC_USER
Group=$KC_GROUP
Environment=KC_BOOTSTRAP_ADMIN_USERNAME=$K_ADMIN
Environment=KC_BOOTSTRAP_ADMIN_PASSWORD=$K_ADMIN_PASS
ExecStart=$KC_HOME/bin/kc.sh start --optimized
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now keycloak

# Apache proxy for Keycloak + CSP headers
cat > /etc/apache2/conf-available/keycloak-headers.conf <<EOF
<IfModule mod_headers.c>
    Header always unset X-Frame-Options
    Header always set Content-Security-Policy "frame-ancestors $K_FRAME"
</IfModule>
EOF
a2enconf keycloak-headers.conf >/dev/null 2>&1 || true

cat > /etc/apache2/sites-available/keycloak-80.conf <<EOF
<VirtualHost *:80>
    ServerName ${K_HOST}
    ProxyPreserveHost On
    ProxyRequests Off
    ProxyTimeout 300
    ProxyPass /.well-known/acme-challenge/ !
    DocumentRoot /var/www/html
    RequestHeader set X-Forwarded-Proto expr=%{REQUEST_SCHEME}
    RequestHeader set X-Forwarded-Port  expr=%{SERVER_PORT}
    RequestHeader set X-Forwarded-Host  "%{HTTP_HOST}s"
    ProxyPass        / http://127.0.0.1:${K_HTTP}/
    ProxyPassReverse / http://127.0.0.1:${K_HTTP}/
    ErrorLog ${APACHE_LOG_DIR}/keycloak_error.log
    CustomLog ${APACHE_LOG_DIR}/keycloak_access.log combined
</VirtualHost>
EOF
a2ensite keycloak-80.conf >/dev/null 2>&1 || true

ensure_apache_running; apache2ctl configtest; systemctl reload apache2 || systemctl start apache2 || systemctl restart apache2 || true

read -p "Obtain Let's Encrypt cert for Keycloak now? (y/N): " KC_SSL
if [[ "$KC_SSL" =~ ^[Yy]$ ]]; then
  issue_cert "$K_HOST" "$ACME_EMAIL" || true
fi

echo
ok "All done."
echo "Webmin:   https://$W_HOST/"
echo "Seq:      https://$S_HOST/ (or http if SSL not enabled)"
echo "Keycloak: https://$K_HOST/admin/ (admin: $K_ADMIN / $K_ADMIN_PASS)"
echo "Install log: $LOG_FILE"
echo "Delete securely with: shred -u $LOG_FILE"
