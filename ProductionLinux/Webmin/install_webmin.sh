#!/bin/bash
# Webmin Ultimate Installation Script for Ubuntu 22.04+
# - Idempotent; safe to re-run
# - Proxies Webmin through Apache with HTTPS on the edge
# - Fixes SSL handshake & cookie issues (backend self-signed accepted; cookie/redirect settings applied)
# Author: Production Deployment Script
# Version: 1.3
# Date: August 2025
set -euo pipefail

# =========================
# Defaults
# =========================
DEFAULT_HOSTNAME="webmin.sivargpt.com"   # public hostname
DEFAULT_PROXY_VIA_APACHE="Y"             # recommended
DEFAULT_ENABLE_SSL="Y"                   # obtain/renew LE cert
DEFAULT_UFW_ENABLE="Y"

# =========================
# Runtime (filled by prompts)
# =========================
HOSTNAME=""
PROXY_VIA_APACHE=""
ENABLE_SSL=""
UFW_ENABLE=""

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
  echo
  log "=== Webmin Installation Configuration ==="
  echo -e "${YELLOW}Press Enter to accept defaults in [brackets]${NC}"
  read -p "Hostname for Webmin via Apache [$DEFAULT_HOSTNAME]: " HOSTNAME; HOSTNAME=${HOSTNAME:-$DEFAULT_HOSTNAME}
  read -p "Proxy Webmin via Apache? (Y/N) [$DEFAULT_PROXY_VIA_APACHE]: " PROXY_VIA_APACHE; PROXY_VIA_APACHE=${PROXY_VIA_APACHE:-$DEFAULT_PROXY_VIA_APACHE}
  if [[ "$PROXY_VIA_APACHE" =~ ^[Yy]$ ]]; then
    read -p "Run Let's Encrypt now? (Y/N) [$DEFAULT_ENABLE_SSL]: " ENABLE_SSL; ENABLE_SSL=${ENABLE_SSL:-$DEFAULT_ENABLE_SSL}
  else
    ENABLE_SSL="N"
  fi
  read -p "Ensure/adjust UFW firewall? (Y/N) [$DEFAULT_UFW_ENABLE]: " UFW_ENABLE; UFW_ENABLE=${UFW_ENABLE:-$DEFAULT_UFW_ENABLE}

  echo
  log "Summary:"
  echo "  Proxy via Apache:  $PROXY_VIA_APACHE"
  if [[ "$PROXY_VIA_APACHE" =~ ^[Yy]$ ]]; then
    echo "  Hostname:          $HOSTNAME"
    echo "  Let's Encrypt:     $ENABLE_SSL"
    echo "  Webmin bind:       127.0.0.1:10000 (SSL self-signed)"
  else
    echo "  Direct access:     https://<server-ip>:10000/ (self-signed)"
  fi
  echo "  UFW enable/update: $UFW_ENABLE"
  echo
  read -p "Continue? (y/N): " confirm
  [[ $confirm =~ ^[Yy]$ ]] || { log "Cancelled."; exit 0; }
}

update_system(){ log "Updating apt..."; apt-get update -y && apt-get upgrade -y; ok "System updated"; }

ensure_base(){
  log "Installing prerequisites..."
  apt-get install -y ca-certificates curl gnupg lsb-release software-properties-common ufw
  ok "Base packages installed"
}

ensure_apache_if_needed(){
  if [[ "$PROXY_VIA_APACHE" =~ ^[Yy]$ ]]; then
    if command -v apache2 >/dev/null 2>&1; then
      ok "Apache found"
    else
      log "Apache not found; installing Apache + certbot module..."
      apt-get install -y apache2 certbot python3-certbot-apache
      systemctl enable --now apache2
      ok "Apache installed"
    fi
    a2enmod proxy proxy_http headers rewrite ssl >/dev/null 2>&1 || true
  fi
}

install_webmin_repo(){
  log "Adding Webmin repository..."
  curl -fsSL http://www.webmin.com/jcameron-key.asc | gpg --dearmor -o /usr/share/keyrings/webmin.gpg
  echo "deb [signed-by=/usr/share/keyrings/webmin.gpg] http://download.webmin.com/download/repository sarge contrib" > /etc/apt/sources.list.d/webmin.list
  apt-get update -y
  ok "Webmin repo added"
}

install_webmin(){
  log "Installing Webmin..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y webmin
  systemctl enable --now webmin || true
  ok "Webmin installed"
}

configure_webmin_bind_local(){
  # Bind Webmin to loopback with SSL enabled; fix redirects and referrers
  local conf="/etc/webmin/miniserv.conf"
  local cfg="/etc/webmin/config"
  if [[ -f "$conf" ]]; then
    log "Configuring Webmin (bind=127.0.0.1:10000, SSL on)…"
    grep -q '^bind=' "$conf" && sed -i 's/^bind=.*/bind=127.0.0.1/' "$conf" || echo "bind=127.0.0.1" >> "$conf"
    grep -q '^port=' "$conf" && sed -i 's/^port=.*/port=10000/' "$conf" || echo "port=10000" >> "$conf"
    grep -q '^listen=' "$conf" && sed -i 's/^listen=.*/listen=10000/' "$conf" || echo "listen=10000" >> "$conf"
    grep -q '^ssl=' "$conf" && sed -i 's/^ssl=.*/ssl=1/' "$conf" || echo "ssl=1" >> "$conf"
    # Prevent redirects to :10000 when behind proxy
    if [[ -f "$cfg" ]]; then
      sed -i 's/^webprefixnoredir=.*/webprefixnoredir=1/; t; $ a webprefixnoredir=1' "$cfg"
      if grep -q '^referers=' "$cfg"; then
        sed -i "s/^referers=.*/referers=${HOSTNAME}/" "$cfg"
      else
        echo "referers=${HOSTNAME}" >> "$cfg"
      fi
    fi
    # Make Webmin aware of the public host for redirects
    if grep -q '^redirect_host=' "$conf" 2>/dev/null; then
      sed -i "s/^redirect_host=.*/redirect_host=${HOSTNAME}/" "$conf"
    else
      echo "redirect_host=${HOSTNAME}" >> "$conf"
    fi
    systemctl restart webmin
    ok "Webmin bound & proxy-aware"
  else
    warn "miniserv.conf not found; skipping bind tweak"
  fi
}

write_webmin_vhost80(){
  # Port 80 vhost (used for ACME and as a proxy before redirect to HTTPS)
  local vhost="/etc/apache2/sites-available/webmin.conf"
  log "Writing/refreshing Webmin HTTP vhost for $HOSTNAME..."
  cat > "$vhost" <<EOF
<VirtualHost *:80>
    ServerName ${HOSTNAME}

    ProxyPreserveHost On
    ProxyRequests Off
    ProxyTimeout 300

    # Let ACME pass through
    ProxyPass /.well-known/acme-challenge/ !
    DocumentRoot /var/www/html

    # Forward headers based on the connection scheme/port
    RequestHeader set X-Forwarded-Proto expr=%{REQUEST_SCHEME}
    RequestHeader set X-Forwarded-Port  expr=%{SERVER_PORT}
    RequestHeader set X-Forwarded-Host  "%{HTTP_HOST}s"

    # Backend is HTTPS with self-signed cert — accept it
    SSLProxyEngine On
    SSLProxyVerify none
    SSLProxyCheckPeerName off
    SSLProxyCheckPeerCN off
    SSLProxyCheckPeerExpire off

    ProxyPass        / https://127.0.0.1:10000/ retry=1 acquire=3000 timeout=600 keepalive=On
    ProxyPassReverse / https://127.0.0.1:10000/

    # Cookies & paths mapping
    ProxyPassReverseCookieDomain 127.0.0.1 ${HOSTNAME}
    ProxyPassReverseCookiePath / /

    ErrorLog \${APACHE_LOG_DIR}/webmin_error.log
    CustomLog \${APACHE_LOG_DIR}/webmin_access.log combined
</VirtualHost>
EOF
  a2ensite webmin.conf >/dev/null 2>&1 || true
  apache2ctl configtest && systemctl reload apache2
  ok "HTTP vhost active"
}

run_certbot_if_enabled(){
  if [[ "$PROXY_VIA_APACHE" =~ ^[Yy]$ && "$ENABLE_SSL" =~ ^[Yy]$ ]]; then
    log "Issuing/renewing Let's Encrypt cert for ${HOSTNAME}…"
    apt-get install -y certbot python3-certbot-apache >/dev/null 2>&1 || true
    # If a previous SSL vhost is broken, disable and back it up so certbot can recreate cleanly
    if [ -f /etc/apache2/sites-available/webmin-le-ssl.conf ]; then
      a2dissite webmin-le-ssl.conf || true
      mv /etc/apache2/sites-available/webmin-le-ssl.conf /etc/apache2/sites-available/webmin-le-ssl.conf.pre-certbot.$(date +%s) || true
      apache2ctl configtest && systemctl reload apache2 || true
    fi
    certbot --apache -d "$HOSTNAME" --agree-tos -m admin@"$HOSTNAME" --redirect -n || true
    ok "Certbot completed (or cert already present)"
  else
    warn "Skipping certbot (either proxy disabled or SSL disabled)"
  fi
}

patch_https_vhost(){
  # After certbot, patch the HTTPS vhost to include proxy + cookie directives
  local sslv="/etc/apache2/sites-available/webmin-le-ssl.conf"
  if [ ! -f "$sslv" ]; then
    warn "No HTTPS vhost to patch (skipping)"
    return 0
  fi

  log "Patching HTTPS vhost with proxy/header/cookie directives…"
  awk -v host="$HOSTNAME" '
    /<VirtualHost/ && $0 ~ /:443>/ { inside=1 }
    inside==1 && /ServerName/ { print; print ""; print "    ProxyPreserveHost On"; print "    ProxyRequests Off"; print "    ProxyTimeout 300"; print ""; print "    RequestHeader set X-Forwarded-Proto \"https\""; print "    RequestHeader set X-Forwarded-Port  \"443\""; print "    RequestHeader set X-Forwarded-Host  \"" host "\""; print ""; print "    SSLProxyEngine On"; print "    SSLProxyVerify none"; print "    SSLProxyCheckPeerName off"; print "    SSLProxyCheckPeerCN off"; print "    SSLProxyCheckPeerExpire off"; print ""; print "    ProxyPass        / https://127.0.0.1:10000/ retry=1 acquire=3000 timeout=600 keepalive=On"; print "    ProxyPassReverse / https://127.0.0.1:10000/"; print ""; print "    ProxyPassReverseCookieDomain 127.0.0.1 " host; print "    ProxyPassReverseCookiePath / /"; skip=1; next }
    /<\/VirtualHost>/ && inside==1 { inside=0 }
    { if(!skip) print; skip=0 }
  ' "$sslv" > "${sslv}.new" && mv "${sslv}.new" "$sslv"

  a2ensite webmin-le-ssl.conf >/dev/null 2>&1 || true
  apache2ctl configtest && systemctl reload apache2
  ok "HTTPS vhost patched & loaded"
}

configure_ufw(){
  if [[ "$UFW_ENABLE" =~ ^[Yy]$ ]]; then
    log "Configuring UFW…"
    if ! ufw status | grep -q "Status: active"; then
      ufw --force reset
      ufw default deny incoming
      ufw default allow outgoing
    fi
    ufw allow 80/tcp  comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    # Webmin is bound to 127.0.0.1, so 10000 remains closed externally
    ufw --force enable
    ok "UFW configured"
  else
    warn "Skipping UFW changes"
  fi
}

write_diag(){
  log "Writing diagnostic helper /root/webmin-diagnostic.sh …"
  cat > /root/webmin-diagnostic.sh <<'EOF'
#!/bin/bash
echo "=== WEBMIN Diagnostic Report ==="
date
echo
echo "[Services]"
systemctl status webmin --no-pager -l | head -20 || true
echo
echo "[Apache]"
systemctl status apache2 --no-pager -l | head -20 || true
echo
echo "[Listening ports]"
ss -tulpen | grep -E "(:80|:443|:10000)\b" || true
echo
echo "[Apache vhosts]"
apache2ctl -S 2>/dev/null || true
echo
echo "[miniserv.conf]"
grep -E "^(port|listen|bind|ssl|redirect_host)=" /etc/webmin/miniserv.conf 2>/dev/null || true
echo
echo "[/etc/webmin/config]"
grep -E "^(webprefixnoredir|referers)=" /etc/webmin/config 2>/dev/null || true
echo
echo "[HTTP probe]"
curl -s -o /dev/null -w "%{http_code}\n" "http://${HOST}"
echo
echo "[HTTPS probe]"
curl -s -o /dev/null -w "%{http_code}\n" "https://${HOST}"
echo
echo "[Apache error tail]"
tail -n 80 /var/log/apache2/webmin_error.log 2>/dev/null || true
echo
echo "[Webmin error tail]"
tail -n 80 /var/webmin/miniserv.error 2>/dev/null || true
echo
EOF
  chmod +x /root/webmin-diagnostic.sh
  ok "Diagnostic script ready: /root/webmin-diagnostic.sh"
}

summary(){
  local ip=$(curl -s ifconfig.me 2>/dev/null || echo "Unknown")
  echo
  echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║            🎉 WEBMIN INSTALL COMPLETE! 🎉            ║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
  echo
  echo -e "${BLUE}📋 SUMMARY:${NC}"
  echo "  • Server IP:       $ip"
  echo "  • Access via:      https://$HOSTNAME/  (HTTP redirects to HTTPS)"
  echo "  • Webmin bind:     127.0.0.1:10000 (SSL self-signed)"
  echo "  • Notes:           Backend TLS accepted; cookies & redirects fixed"
  echo
  echo -e "${YELLOW}🛠 Useful:${NC}"
  echo "  • Service:  systemctl status webmin"
  echo "  • Logs:     tail -n 200 /var/webmin/miniserv.error"
  echo "  • Apache:   tail -n 200 /var/log/apache2/webmin_error.log"
  echo "  • Diagnose: HOST=$HOSTNAME /root/webmin-diagnostic.sh"
  echo
}

main(){
  trap 'err "Install failed at line $LINENO"; exit 1' ERR
  check_root
  prompt_inputs
  update_system
  ensure_base
  install_webmin_repo
  install_webmin

  if [[ "$PROXY_VIA_APACHE" =~ ^[Yy]$ ]]; then
    ensure_apache_if_needed
    configure_webmin_bind_local
    write_webmin_vhost80
    run_certbot_if_enabled
    patch_https_vhost
  fi

  configure_ufw
  write_diag
  summary
}

main "$@"
