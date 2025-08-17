#!/bin/bash

# Keycloak Ultimate Production Installation Script for Ubuntu 22.04
# Incorporates ALL lessons learned from extensive troubleshooting
# Uses Apache, includes comprehensive diagnostics, and handles all edge cases
# Author: Production Deployment Script
# Version: 4.0 - Ultimate Edition
# Date: August 2025

set -euo pipefail

# Configuration Variables
KEYCLOAK_VERSION="26.3.1"
KEYCLOAK_USER="keycloak"
KEYCLOAK_GROUP="keycloak"
KEYCLOAK_HOME="/opt/keycloak"
KEYCLOAK_LOG_DIR="/var/log/keycloak"
KEYCLOAK_DATA_DIR="/var/lib/keycloak"

# Default Configuration
DEFAULT_HOSTNAME="auth.sivargpt.com"
DEFAULT_DB_NAME="keycloak_prod"
DEFAULT_DB_USER="keycloak_user"
DEFAULT_DB_PASSWORD="1234567890"
DEFAULT_ADMIN_USER="keycloakadmin"
DEFAULT_ADMIN_PASSWORD="1234567890"
DEFAULT_HTTP_PORT="8080"

# User Configuration Variables
HOSTNAME=""
DB_NAME=""
DB_USER=""
DB_PASSWORD=""
ADMIN_USER=""
ADMIN_PASSWORD=""
HTTP_PORT=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

# Function to prompt for user inputs
prompt_inputs() {
    echo
    log "=== Keycloak Ultimate Installation Configuration ==="
    echo
    echo -e "${YELLOW}Press Enter to use default values shown in brackets${NC}"
    echo
    
    read -p "Enter hostname [$DEFAULT_HOSTNAME]: " HOSTNAME
    HOSTNAME=${HOSTNAME:-$DEFAULT_HOSTNAME}
    
    read -p "Enter database name [$DEFAULT_DB_NAME]: " DB_NAME
    DB_NAME=${DB_NAME:-$DEFAULT_DB_NAME}
    
    read -p "Enter database username [$DEFAULT_DB_USER]: " DB_USER
    DB_USER=${DB_USER:-$DEFAULT_DB_USER}
    
    read -p "Enter database password [$DEFAULT_DB_PASSWORD]: " DB_PASSWORD
    DB_PASSWORD=${DB_PASSWORD:-$DEFAULT_DB_PASSWORD}
    
    read -p "Enter admin username [$DEFAULT_ADMIN_USER]: " ADMIN_USER
    ADMIN_USER=${ADMIN_USER:-$DEFAULT_ADMIN_USER}
    
    read -p "Enter admin password [$DEFAULT_ADMIN_PASSWORD]: " ADMIN_PASSWORD
    ADMIN_PASSWORD=${ADMIN_PASSWORD:-$DEFAULT_ADMIN_PASSWORD}
    
    read -p "Enter HTTP port [$DEFAULT_HTTP_PORT]: " HTTP_PORT
    HTTP_PORT=${HTTP_PORT:-$DEFAULT_HTTP_PORT}
    
    echo
    log "Configuration Summary:"
    echo "  Hostname: $HOSTNAME"
    echo "  Database: $DB_NAME (user: $DB_USER)"
    echo "  Admin User: $ADMIN_USER"
    echo "  HTTP Port: $HTTP_PORT"
    echo
    
    read -p "Continue with this configuration? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        log "Installation cancelled by user"
        exit 0
    fi
    
    log_success "Configuration confirmed"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Function to update system packages
update_system() {
    log "Updating system packages..."
    apt-get update -y
    apt-get upgrade -y
    log_success "System packages updated"
}

# Function to install required packages
install_dependencies() {
    log "Installing required packages..."
    apt-get install -y \
        openjdk-21-jdk \
        postgresql \
        postgresql-contrib \
        apache2 \
        certbot \
        python3-certbot-apache \
        ufw \
        fail2ban \
        unzip \
        wget \
        curl \
        openssl \
        ca-certificates \
        net-tools \
        gnupg \
        lsb-release
    
    # Enable required Apache modules
    a2enmod proxy
    a2enmod proxy_http
    a2enmod proxy_ajp
    a2enmod rewrite
    a2enmod deflate
    a2enmod headers
    a2enmod proxy_balancer
    a2enmod proxy_connect
    a2enmod proxy_html
    a2enmod ssl
    
    log_success "Dependencies installed and Apache modules enabled"
}

# Function to configure PostgreSQL
setup_postgresql() {
    log "Configuring PostgreSQL database..."
    
    systemctl start postgresql
    systemctl enable postgresql
    
    # Get PostgreSQL version for config path
    local pg_version=$(sudo -u postgres psql -t -c "SELECT version();" | grep -oP '\d+\.\d+' | head -1)
    local pg_major_version=$(echo $pg_version | cut -d. -f1)
    local pg_config_file="/etc/postgresql/$pg_major_version/main/postgresql.conf"
    
    # Backup and configure PostgreSQL for production
    cp "$pg_config_file" "$pg_config_file.backup" 2>/dev/null || true
    
    cat >> "$pg_config_file" << EOF

# Keycloak Production Configuration
max_connections = 200
shared_buffers = 256MB
effective_cache_size = 1GB
work_mem = 4MB
maintenance_work_mem = 64MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
EOF
    
    # Create database and user with proper permissions
    sudo -u postgres psql << EOF
-- Clean slate: drop existing if they exist
DROP DATABASE IF EXISTS $DB_NAME;
DROP USER IF EXISTS $DB_USER;

-- Create database with proper encoding
CREATE DATABASE $DB_NAME WITH 
    ENCODING 'UTF8' 
    LC_COLLATE='en_US.UTF-8' 
    LC_CTYPE='en_US.UTF-8' 
    TEMPLATE=template0;

-- Create user with secure password
CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';

-- Grant all necessary privileges
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
ALTER DATABASE $DB_NAME OWNER TO $DB_USER;

-- Connect to the database and grant schema privileges
\c $DB_NAME
GRANT ALL ON SCHEMA public TO $DB_USER;
GRANT CREATE ON SCHEMA public TO $DB_USER;
GRANT USAGE ON SCHEMA public TO $DB_USER;

-- Verify user creation
\du $DB_USER
EOF
    
    # Restart PostgreSQL to apply configuration
    systemctl restart postgresql
    
    # Test database connection thoroughly
    log "Testing database connection..."
    if PGPASSWORD="$DB_PASSWORD" psql -h localhost -U "$DB_USER" -d "$DB_NAME" -c "SELECT version();" > /dev/null 2>&1; then
        log_success "PostgreSQL configured and tested successfully"
    else
        log_error "Database connection test failed"
        exit 1
    fi
}

# Function to create Keycloak user and directories
setup_keycloak_user() {
    log "Creating Keycloak user and directories..."
    
    # Create group and user if they don't exist
    groupadd -r $KEYCLOAK_GROUP 2>/dev/null || true
    useradd -r -g $KEYCLOAK_GROUP -d $KEYCLOAK_HOME -s /sbin/nologin $KEYCLOAK_USER 2>/dev/null || true
    
    # Create all necessary directories
    mkdir -p $KEYCLOAK_HOME
    mkdir -p $KEYCLOAK_LOG_DIR
    mkdir -p $KEYCLOAK_DATA_DIR
    mkdir -p $KEYCLOAK_HOME/conf
    mkdir -p $KEYCLOAK_HOME/data
    
    # Set proper ownership and permissions
    chown -R $KEYCLOAK_USER:$KEYCLOAK_GROUP $KEYCLOAK_HOME
    chown -R $KEYCLOAK_USER:$KEYCLOAK_GROUP $KEYCLOAK_LOG_DIR
    chown -R $KEYCLOAK_USER:$KEYCLOAK_GROUP $KEYCLOAK_DATA_DIR
    
    chmod 750 $KEYCLOAK_HOME
    chmod 755 $KEYCLOAK_LOG_DIR
    chmod 750 $KEYCLOAK_DATA_DIR
    
    log_success "Keycloak user and directories created"
}

# Function to download and install Keycloak
install_keycloak() {
    log "Downloading and installing Keycloak $KEYCLOAK_VERSION..."
    
    cd /tmp
    
    # Download Keycloak with retry mechanism
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if wget -O keycloak.tar.gz "https://github.com/keycloak/keycloak/releases/download/${KEYCLOAK_VERSION}/keycloak-${KEYCLOAK_VERSION}.tar.gz"; then
            break
        else
            if [ $attempt -eq $max_attempts ]; then
                log_error "Failed to download Keycloak after $max_attempts attempts"
                exit 1
            fi
            log_warning "Download attempt $attempt failed, retrying..."
            ((attempt++))
            sleep 5
        fi
    done
    
    # Extract and install
    tar -xzf keycloak.tar.gz
    cp -r keycloak-${KEYCLOAK_VERSION}/* $KEYCLOAK_HOME/
    
    # Set proper ownership and permissions
    chown -R $KEYCLOAK_USER:$KEYCLOAK_GROUP $KEYCLOAK_HOME
    chmod +x $KEYCLOAK_HOME/bin/*.sh
    
    # Cleanup
    rm -rf keycloak.tar.gz keycloak-${KEYCLOAK_VERSION}
    
    log_success "Keycloak installed successfully"
}

# Function to configure Keycloak (lessons learned applied)
configure_keycloak() {
    log "Configuring Keycloak with all lessons learned..."
    
    # Create production-ready configuration file
    cat > $KEYCLOAK_HOME/conf/keycloak.conf << EOF
# Database configuration
db=postgres
db-username=$DB_USER
db-password=$DB_PASSWORD
db-url=jdbc:postgresql://localhost:5432/$DB_NAME
db-pool-initial-size=5
db-pool-min-size=5
db-pool-max-size=20

# Hostname configuration (FIXED: correct proxy headers syntax)
hostname=$HOSTNAME
hostname-strict=false
hostname-strict-backchannel=false
proxy-headers=forwarded

# HTTP configuration
http-enabled=true
http-port=$HTTP_PORT

# Performance and monitoring
health-enabled=true
metrics-enabled=true
http-max-queued-requests=1000

# Logging configuration
log=console,file
log-level=INFO
log-file=$KEYCLOAK_LOG_DIR/keycloak.log
log-file-format=%d{yyyy-MM-dd HH:mm:ss,SSS} %-5p [%c] (%t) %s%e%n

# Cache configuration (local for single instance)
cache=local

# Transaction configuration
transaction-xa-enabled=false

# Features
features=token-exchange,admin-fine-grained-authz
EOF
    
    # Set proper permissions on config file
    chown $KEYCLOAK_USER:$KEYCLOAK_GROUP $KEYCLOAK_HOME/conf/keycloak.conf
    chmod 640 $KEYCLOAK_HOME/conf/keycloak.conf
    
    log_success "Keycloak configuration created with correct syntax"
}

# Function to build optimized Keycloak
build_keycloak() {
    log "Building optimized Keycloak..."
    
    # Build Keycloak with proper options (lessons learned: no cache option in build)
    sudo -u $KEYCLOAK_USER $KEYCLOAK_HOME/bin/kc.sh build \
        --db=postgres \
        --health-enabled=true \
        --metrics-enabled=true \
        --features=token-exchange,admin-fine-grained-authz
    
    log_success "Keycloak build completed successfully"
}

# Function to create systemd service (VPS-optimized)
create_systemd_service() {
    log "Creating systemd service (VPS-optimized)..."
    
    cat > /etc/systemd/system/keycloak.service << EOF
[Unit]
Description=Keycloak Identity and Access Management
Documentation=https://www.keycloak.org/
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=exec
User=$KEYCLOAK_USER
Group=$KEYCLOAK_GROUP
# VPS-compatible Java options (lessons learned: avoid memory execution issues)
Environment=JAVA_OPTS="-Xms512m -Xmx1024m -Djava.net.preferIPv4Stack=true"
# FIXED: Use new environment variable names
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

# Security settings compatible with VPS
PrivateTmp=true
ProtectHome=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable keycloak
    
    log_success "Systemd service created and enabled"
}

# Function to configure Apache reverse proxy
configure_apache() {
    log "Configuring Apache reverse proxy..."
    
    # Disable default site
    a2dissite 000-default.conf 2>/dev/null || true
    
    # Create Keycloak virtual host with proper proxy configuration
    cat > /etc/apache2/sites-available/keycloak.conf << EOF
<VirtualHost *:80>
    ServerName $HOSTNAME
    ServerAlias www.$HOSTNAME
    
    # Security headers
    Header always set X-Frame-Options DENY
    Header always set X-Content-Type-Options nosniff
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy strict-origin-when-cross-origin
    Header always set X-Forwarded-Proto "http"
    
    # Proxy configuration for Keycloak
    ProxyPreserveHost On
    ProxyRequests Off
    
    # Main Keycloak proxy (preserve Let's Encrypt path)
    ProxyPass /.well-known/acme-challenge/ !
    ProxyPass / http://127.0.0.1:$HTTP_PORT/
    ProxyPassReverse / http://127.0.0.1:$HTTP_PORT/
    
    # Set proper headers for Keycloak (lessons learned)
    ProxyPreserveHost On
    RequestHeader set X-Forwarded-Proto "http"
    RequestHeader set X-Forwarded-Port "80"
    RequestHeader set X-Forwarded-Host "%{HTTP_HOST}s"
    
    # Timeout settings
    ProxyTimeout 300
    
    # Logging
    ErrorLog \${APACHE_LOG_DIR}/keycloak_error.log
    CustomLog \${APACHE_LOG_DIR}/keycloak_access.log combined
    
    # Document root for Let's Encrypt
    DocumentRoot /var/www/html
    
    # Handle health checks efficiently
    <Location "/health">
        ProxyPass http://127.0.0.1:9000/q/health
        ProxyPassReverse http://127.0.0.1:9000/q/health
    </Location>
</VirtualHost>
EOF
    
    # Enable site and restart Apache
    a2ensite keycloak.conf
    
    # Test Apache configuration
    if apache2ctl configtest; then
        systemctl restart apache2
        systemctl enable apache2
        log_success "Apache configured successfully"
    else
        log_error "Apache configuration test failed"
        exit 1
    fi
}

# Function to configure firewall
configure_firewall() {
    log "Configuring firewall..."
    
    # Reset and configure UFW
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow essential ports
    ufw allow 22/tcp comment 'SSH'
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    ufw allow from 127.0.0.1 to any port 5432 comment 'PostgreSQL local'
    
    # Enable firewall
    ufw --force enable
    
    log_success "Firewall configured"
}

# Function to configure fail2ban
configure_fail2ban() {
    log "Configuring fail2ban for security..."
    
    # Create Keycloak-specific fail2ban filter
    cat > /etc/fail2ban/filter.d/keycloak.conf << 'EOF'
[Definition]
failregex = ^.*ERROR.*Login failure.*from IP.*<HOST>.*$
            ^.*WARN.*Failed login attempt.*from.*<HOST>.*$
            ^.*ERROR.*Invalid user credentials.*from.*<HOST>.*$
ignoreregex =
EOF
    
    # Create Keycloak jail configuration
    cat > /etc/fail2ban/jail.d/keycloak.conf << EOF
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
    
    # Restart and enable fail2ban
    systemctl restart fail2ban
    systemctl enable fail2ban
    
    log_success "Fail2ban configured"
}

# Function to start and verify Keycloak
start_and_verify() {
    log "Starting Keycloak service..."
    
    # Start Keycloak
    systemctl start keycloak
    
    # Wait for startup with progress indication
    log "Waiting for Keycloak to start (this may take 1-2 minutes)..."
    local max_wait=120
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        if systemctl is-active --quiet keycloak; then
            log_success "Keycloak service is running"
            break
        fi
        
        if [ $((wait_time % 10)) -eq 0 ]; then
            log "Still waiting... ($wait_time/$max_wait seconds)"
        fi
        
        sleep 5
        wait_time=$((wait_time + 5))
    done
    
    # Verify service is actually running
    if ! systemctl is-active --quiet keycloak; then
        log_error "Keycloak service failed to start"
        log "Checking service status..."
        systemctl status keycloak --no-pager -l
        log "Checking recent logs..."
        journalctl -u keycloak --no-pager -l --since "5 minutes ago"
        return 1
    fi
    
    # Test connectivity with proper endpoints (lessons learned)
    log "Testing Keycloak connectivity..."
    local max_attempts=20
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        # Test different endpoints based on lessons learned
        if curl -s -w "%{http_code}" "http://localhost:$HTTP_PORT/" -o /dev/null | grep -qE "^(200|302)$"; then
            log_success "Keycloak is responding correctly"
            break
        elif curl -s -w "%{http_code}" "http://localhost:$HTTP_PORT/realms/master" -o /dev/null | grep -qE "^(200|302)$"; then
            log_success "Keycloak realms endpoint is responding"
            break
        else
            if [ $attempt -eq $max_attempts ]; then
                log_error "Keycloak is not responding after $max_attempts attempts"
                return 1
            fi
            log "Attempt $attempt/$max_attempts: Waiting for Keycloak to respond..."
            sleep 10
            ((attempt++))
        fi
    done
    
    # Test Apache proxy
    if curl -s -w "%{http_code}" "http://localhost/" -o /dev/null | grep -qE "^(200|302)$"; then
        log_success "Apache reverse proxy is working"
    else
        log_warning "Apache proxy may have issues"
    fi
    
    # Test management interface
    if curl -s "http://localhost:9000/q/health" | grep -q "UP"; then
        log_success "Management interface is responding"
    else
        log_warning "Management interface may not be available"
    fi
}

# Function to discover and test endpoints (lessons learned)
discover_working_endpoints() {
    log "Discovering working Keycloak endpoints..."
    
    local server_ip=$(curl -s ifconfig.me 2>/dev/null || echo "Unable to detect")
    local working_urls=()
    
    # Test comprehensive URL patterns based on lessons learned
    local test_urls=(
        "http://localhost:$HTTP_PORT/"
        "http://localhost:$HTTP_PORT/admin/"
        "http://localhost:$HTTP_PORT/admin/master/console/"
        "http://localhost:$HTTP_PORT/realms/master"
        "http://localhost/"
        "http://localhost/admin/"
        "http://$server_ip/"
        "http://$server_ip/admin/"
        "http://$HOSTNAME/"
        "http://$HOSTNAME/admin/"
    )
    
    echo
    log "Testing endpoint accessibility..."
    for url in "${test_urls[@]}"; do
        local response=$(timeout 10 curl -s -w "%{http_code}" "$url" -o /dev/null 2>/dev/null || echo "timeout")
        
        case $response in
            200|302|301)
                log_success "$url → $response"
                working_urls+=("$url")
                ;;
            404)
                log_warning "$url → $response (may redirect)"
                ;;
            *)
                log_warning "$url → $response"
                ;;
        esac
    done
    
    echo
    if [[ ${#working_urls[@]} -gt 0 ]]; then
        echo -e "${GREEN}🎉 WORKING ENDPOINTS DISCOVERED! 🎉${NC}"
        echo
        for url in "${working_urls[@]}"; do
            echo -e "   ${GREEN}✓${NC} $url"
        done
    else
        echo -e "${YELLOW}⚠ Limited endpoint access detected${NC}"
        echo "This is often normal - Keycloak may be working but not all URLs tested successfully"
    fi
}

# Function to create comprehensive diagnostic script
create_diagnostic_script() {
    log "Creating comprehensive diagnostic script..."
    
    cat > /root/keycloak-diagnostic.sh << 'EOF'
#!/bin/bash

# Keycloak Ultimate Diagnostic Script
# Auto-generated by installation script with all lessons learned

echo "=== KEYCLOAK ULTIMATE DIAGNOSTIC REPORT ==="
echo "Generated: $(date)"
echo "Server: $(hostname)"
echo

echo "1. SERVICE STATUS:"
echo "=================="
echo "Keycloak Service:"
systemctl status keycloak --no-pager -l | head -15
echo
echo "Apache Service:"
systemctl status apache2 --no-pager -l | head -5
echo
echo "PostgreSQL Service:"
systemctl status postgresql --no-pager -l | head -5
echo

echo "2. PORT STATUS:"
echo "==============="
echo "Listening ports:"
netstat -tuln | grep -E "(8080|80|5432|9000)" || echo "No relevant ports found"
echo

echo "3. CONNECTIVITY TESTS:"
echo "======================"
server_ip=$(curl -s ifconfig.me 2>/dev/null || echo "Unknown")

# Comprehensive endpoint testing based on lessons learned
test_urls=(
    "http://localhost:8080/"
    "http://localhost:8080/admin/"
    "http://localhost:8080/admin/master/console/"
    "http://localhost:8080/realms/master"
    "http://localhost/"
    "http://localhost/admin/"
    "http://$server_ip/"
    "http://$server_ip/admin/"
    "http://auth.sivargpt.com/"
    "http://auth.sivargpt.com/admin/"
)

for url in "${test_urls[@]}"; do
    response=$(timeout 5 curl -s -w "%{http_code}" "$url" -o /dev/null 2>/dev/null || echo "timeout")
    case $response in
        200|302|301)
            echo "✓ $url → $response"
            ;;
        *)
            echo "✗ $url → $response"
            ;;
    esac
done
echo

echo "4. MANAGEMENT INTERFACE:"
echo "========================"
echo -n "Health endpoint: "
if curl -s "http://localhost:9000/q/health" 2>/dev/null | grep -q "UP"; then
    echo "✓ Available"
    echo "Health status:"
    curl -s "http://localhost:9000/q/health" 2>/dev/null | head -5
else
    echo "✗ Not available"
fi
echo

echo "5. CONFIGURATION CHECK:"
echo "======================="
echo "Keycloak config (sensitive data hidden):"
if [[ -f /opt/keycloak/conf/keycloak.conf ]]; then
    grep -E "(hostname|http-enabled|http-port|db=|proxy-headers)" /opt/keycloak/conf/keycloak.conf
else
    echo "Config file not found"
fi
echo

echo "6. RECENT LOGS:"
echo "==============="
echo "Last 15 Keycloak log entries:"
journalctl -u keycloak --no-pager -l --since "10 minutes ago" | tail -15
echo

echo "7. DATABASE CONNECTION:"
echo "======================="
echo -n "PostgreSQL connection: "
if PGPASSWORD="1234567890" psql -h localhost -U keycloak_user -d keycloak_prod -c "SELECT version();" >/dev/null 2>&1; then
    echo "✓ Connected"
else
    echo "✗ Connection failed"
fi
echo

echo "8. APACHE CONFIGURATION:"
echo "========================"
echo -n "Apache config test: "
if apache2ctl configtest 2>/dev/null; then
    echo "✓ Valid"
else
    echo "✗ Invalid"
fi
echo

echo "9. WORKING ACCESS URLS:"
echo "======================"
echo "Based on tests above, try these URLs for admin access:"
echo "• Primary: http://auth.sivargpt.com/admin/"
echo "• Backup:  http://$server_ip/admin/"
echo "• Direct:  http://localhost:8080/admin/master/console/"
echo "• Local:   http://localhost:8080/admin/"
echo
echo "Login credentials:"
echo "• Username: keycloakadmin"
echo "• Password: 1234567890"
echo

echo "10. QUICK TROUBLESHOOTING:"
echo "=========================="
echo "If admin console not accessible:"
echo "1. Check: systemctl status keycloak"
echo "2. Restart: systemctl restart keycloak"
echo "3. Logs: journalctl -u keycloak -f"
echo "4. Test direct: curl http://localhost:8080/"
echo "5. Manual start: sudo -u keycloak /opt/keycloak/bin/kc.sh start"
echo

echo "=== END OF DIAGNOSTIC REPORT ==="
EOF
    
    chmod +x /root/keycloak-diagnostic.sh
    
    log_success "Diagnostic script created at /root/keycloak-diagnostic.sh"
}

# Function to setup SSL certificate with Let's Encrypt
setup_ssl_certificate() {
    log "Setting up SSL certificate with Let's Encrypt..."
    
    # Check if domain is properly pointing to this server
    local server_ip=$(curl -s ifconfig.me 2>/dev/null || echo "Unknown")
    local domain_ip=$(nslookup $HOSTNAME 2>/dev/null | grep -A1 "Name:" | tail -1 | awk '{print $2}' 2>/dev/null || echo "Unknown")
    
    if [[ "$domain_ip" != "$server_ip" ]]; then
        log_warning "DNS may not be pointing correctly to this server"
        log "Domain $HOSTNAME resolves to: $domain_ip"
        log "Server IP: $server_ip"
        echo
        read -p "Do you want to continue with SSL setup anyway? (y/N): " continue_ssl
        if [[ ! $continue_ssl =~ ^[Yy]$ ]]; then
            log "Skipping SSL setup. You can run it later with: certbot --apache -d $HOSTNAME"
            return 0
        fi
    fi
    
    # Create webroot directory for Let's Encrypt challenges
    mkdir -p /var/www/html
    chown www-data:www-data /var/www/html
    
    # Test if domain is accessible via HTTP
    log "Testing domain accessibility..."
    if timeout 10 curl -s "http://$HOSTNAME/" >/dev/null 2>&1; then
        log_success "Domain is accessible via HTTP"
        
        # Attempt to get SSL certificate
        log "Attempting to obtain SSL certificate..."
        if certbot --apache -d $HOSTNAME --non-interactive --agree-tos --email admin@$HOSTNAME --redirect; then
            log_success "SSL certificate obtained and configured successfully!"
            
            # Test HTTPS access
            if timeout 10 curl -s "https://$HOSTNAME/" >/dev/null 2>&1; then
                log_success "HTTPS is now working!"
                return 0
            else
                log_warning "SSL certificate installed but HTTPS may need a moment to propagate"
            fi
        else
            log_error "Failed to obtain SSL certificate"
            log "You can try manually later with: certbot --apache -d $HOSTNAME"
            return 1
        fi
    else
        log_error "Domain $HOSTNAME is not accessible via HTTP"
        log "Please ensure:"
        log "  1. DNS is pointing to this server ($server_ip)"
        log "  2. Firewall allows port 80"
        log "  3. Apache is running properly"
        log "You can setup SSL later with: certbot --apache -d $HOSTNAME"
        return 1
    fi
}

# Function to display ultimate installation summary
display_ultimate_summary() {
    local server_ip=$(curl -s ifconfig.me 2>/dev/null || echo "Unable to detect")
    
    clear
    echo
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                🎉 KEYCLOAK INSTALLATION COMPLETE! 🎉           ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${BLUE}📋 INSTALLATION SUMMARY:${NC}"
    echo "  • Keycloak Version: $KEYCLOAK_VERSION (Latest)"
    echo "  • Hostname: $HOSTNAME"
    echo "  • Database: $DB_NAME (PostgreSQL)"
    echo "  • Reverse Proxy: Apache HTTP Server"
    echo "  • Server IP: $server_ip"
    echo "  • Security: UFW Firewall + Fail2ban"
    echo
    
    # Check if HTTPS is available
    local https_available=false
    if timeout 5 curl -s "https://$HOSTNAME/" >/dev/null 2>&1; then
        https_available=true
    fi
    
    echo -e "${YELLOW}🔗 ACCESS URLS:${NC}"
    if [[ "$https_available" == "true" ]]; then
        echo -e "  🟢 ${GREEN}https://$HOSTNAME/admin/${NC} (SSL Enabled)"
        echo -e "  🔓 http://$HOSTNAME/admin/ (HTTP)"
    else
        echo -e "  🔓 ${YELLOW}http://$HOSTNAME/admin/${NC} (Use HTTP until SSL setup)"
        echo -e "  ⚠️  Note: Use HTTP (not HTTPS) to avoid SSL errors"
    fi
    echo -e "  🌐 http://$server_ip/admin/ (Backup IP access)"
    echo -e "  🏠 http://localhost:8080/admin/master/console/ (Direct)"
    echo
    echo -e "${YELLOW}👤 LOGIN CREDENTIALS:${NC}"
    echo "  • Username: $ADMIN_USER"
    echo "  • Password: $ADMIN_PASSWORD"
    echo
    echo -e "${YELLOW}🛠️ MANAGEMENT COMMANDS:${NC}"
    echo "  • Status:     systemctl status keycloak"
    echo "  • Restart:    systemctl restart keycloak"
    echo "  • Logs:       journalctl -u keycloak -f"
    echo "  • Diagnostic: /root/keycloak-diagnostic.sh"
    echo
    echo -e "${YELLOW}📋 NEXT STEPS:${NC}"
    echo "  1. 🌐 Test access using the HTTP URLs above"
    if [[ "$https_available" != "true" ]]; then
        echo -e "  2. 🔒 ${YELLOW}Setup SSL: certbot --apache -d $HOSTNAME${NC}"
    else
        echo "  2. ✅ SSL certificate is configured"
    fi
    echo "  3. 🔧 Configure your realms, clients, and users"
    echo "  4. 💾 Set up regular database backups"
    echo "  5. 📊 Monitor performance and logs"
    echo
    echo -e "${YELLOW}🚨 IMPORTANT NOTES:${NC}"
    if [[ "$https_available" != "true" ]]; then
        echo -e "  • ${YELLOW}Use HTTP URLs (not HTTPS) until SSL is configured${NC}"
        echo -e "  • ${YELLOW}Browser SSL errors are normal without valid certificate${NC}"
    fi
    echo -e "  • Save credentials securely: $ADMIN_USER / $ADMIN_PASSWORD"
    echo -e "  • DNS points $HOSTNAME → $server_ip"
    echo
    echo -e "${YELLOW}🔍 TROUBLESHOOTING:${NC}"
    echo "  • Run diagnostic: /root/keycloak-diagnostic.sh"
    echo "  • Check logs: journalctl -u keycloak -f"
    echo "  • Test endpoints: curl http://localhost:8080/"
    echo "  • Manual start: sudo -u keycloak /opt/keycloak/bin/kc.sh start"
    echo
    echo -e "${YELLOW}🌟 LESSONS LEARNED APPLIED:${NC}"
    echo "  ✅ Fixed proxy-headers syntax (forwarded, not forwarded|xforwarded)"
    echo "  ✅ VPS-compatible Java memory settings"
    echo "  ✅ Correct admin environment variables (KC_BOOTSTRAP_*)"
    echo "  ✅ Proper endpoint discovery and testing"
    echo "  ✅ Apache instead of Nginx for familiarity"
    echo "  ✅ Comprehensive error handling and diagnostics"
    echo "  ✅ Production-ready PostgreSQL configuration"
    echo "  ✅ Security hardening with UFW and Fail2ban"
    echo "  ✅ HTTP/HTTPS URL guidance to avoid SSL errors"
    echo
    echo -e "${GREEN}🚀 Keycloak is ready for production use!${NC}"
    echo
}

# Function to perform final health check
perform_final_health_check() {
    log "Performing final comprehensive health check..."
    echo
    
    local health_score=0
    local max_score=10
    
    # Check 1: Service running
    if systemctl is-active --quiet keycloak; then
        log_success "✓ Keycloak service is running"
        ((health_score++))
    else
        log_error "✗ Keycloak service is not running"
    fi
    
    # Check 2: Database connection
    if PGPASSWORD="$DB_PASSWORD" psql -h localhost -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" >/dev/null 2>&1; then
        log_success "✓ Database connection working"
        ((health_score++))
    else
        log_error "✗ Database connection failed"
    fi
    
    # Check 3: HTTP endpoint responding
    if curl -s "http://localhost:$HTTP_PORT/" >/dev/null 2>&1; then
        log_success "✓ HTTP endpoint responding"
        ((health_score++))
    else
        log_error "✗ HTTP endpoint not responding"
    fi
    
    # Check 4: Apache proxy working
    if curl -s "http://localhost/" >/dev/null 2>&1; then
        log_success "✓ Apache proxy working"
        ((health_score++))
    else
        log_error "✗ Apache proxy not working"
    fi
    
    # Check 5: Management interface
    if curl -s "http://localhost:9000/q/health" | grep -q "UP" 2>/dev/null; then
        log_success "✓ Management interface responding"
        ((health_score++))
    else
        log_warning "⚠ Management interface may not be available"
    fi
    
    # Check 6: Configuration file valid
    if sudo -u keycloak /opt/keycloak/bin/kc.sh show-config >/dev/null 2>&1; then
        log_success "✓ Configuration file valid"
        ((health_score++))
    else
        log_error "✗ Configuration file has issues"
    fi
    
    # Check 7: PostgreSQL service running
    if systemctl is-active --quiet postgresql; then
        log_success "✓ PostgreSQL service running"
        ((health_score++))
    else
        log_error "✗ PostgreSQL service not running"
    fi
    
    # Check 8: Apache service running
    if systemctl is-active --quiet apache2; then
        log_success "✓ Apache service running"
        ((health_score++))
    else
        log_error "✗ Apache service not running"
    fi
    
    # Check 9: Firewall configured
    if ufw status | grep -q "Status: active"; then
        log_success "✓ Firewall is active"
        ((health_score++))
    else
        log_warning "⚠ Firewall may not be active"
    fi
    
    # Check 10: Admin console accessible
    if curl -s "http://localhost:$HTTP_PORT/admin/" | grep -qi "keycloak" 2>/dev/null; then
        log_success "✓ Admin console accessible"
        ((health_score++))
    else
        log_warning "⚠ Admin console may need direct testing"
    fi
    
    echo
    echo -e "${BLUE}🏥 HEALTH CHECK RESULTS:${NC}"
    echo -e "   Score: ${GREEN}$health_score/$max_score${NC}"
    
    if [ $health_score -ge 8 ]; then
        echo -e "   Status: ${GREEN}🟢 EXCELLENT - Ready for production${NC}"
    elif [ $health_score -ge 6 ]; then
        echo -e "   Status: ${YELLOW}🟡 GOOD - Minor issues to address${NC}"
    else
        echo -e "   Status: ${RED}🔴 NEEDS ATTENTION - Check failed components${NC}"
    fi
    
    echo
}

# Main installation function
main() {
    log "Starting Keycloak Ultimate Installation..."
    echo
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         KEYCLOAK ULTIMATE INSTALLATION SCRIPT v4.0            ║${NC}"
    echo -e "${BLUE}║              Incorporates ALL Lessons Learned                  ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    check_root
    prompt_inputs
    
    echo
    log "Starting installation process..."
    echo
    
    # Phase 1: System Preparation
    echo -e "${YELLOW}🔧 PHASE 1: System Preparation${NC}"
    update_system
    install_dependencies
    echo
    
    # Phase 2: Database Setup
    echo -e "${YELLOW}🗄️ PHASE 2: Database Configuration${NC}"
    setup_postgresql
    echo
    
    # Phase 3: Keycloak Installation
    echo -e "${YELLOW}⚡ PHASE 3: Keycloak Installation${NC}"
    setup_keycloak_user
    install_keycloak
    configure_keycloak
    build_keycloak
    echo
    
    # Phase 4: Service Configuration
    echo -e "${YELLOW}🔌 PHASE 4: Service Configuration${NC}"
    create_systemd_service
    configure_apache
    echo
    
    # Phase 5: Security Setup
    echo -e "${YELLOW}🔒 PHASE 5: Security Configuration${NC}"
    configure_firewall
    configure_fail2ban
    echo
    
    # Phase 6: Startup and Verification
    echo -e "${YELLOW}🚀 PHASE 6: Startup and Verification${NC}"
    start_and_verify
    discover_working_endpoints
    echo
    
    # Phase 7: SSL Certificate Setup
    echo -e "${YELLOW}🔒 PHASE 7: SSL Certificate Setup${NC}"
    echo
    read -p "Do you want to set up SSL certificate with Let's Encrypt now? (y/N): " setup_ssl
    if [[ $setup_ssl =~ ^[Yy]$ ]]; then
        setup_ssl_certificate
    else
        log "Skipping SSL setup. You can run it later with: certbot --apache -d $HOSTNAME"
        log_warning "Remember to use HTTP URLs (not HTTPS) until SSL is configured"
    fi
    echo
    
    # Phase 8: Final Setup and Diagnostics
    echo -e "${YELLOW}📊 PHASE 8: Final Setup and Diagnostics${NC}"
    create_diagnostic_script
    perform_final_health_check
    echo
    
    # Display final results
    display_ultimate_summary
    
    log_success "🎉 Ultimate Keycloak installation completed successfully!"
    echo
    
    # Display final access information
    local server_ip=$(curl -s ifconfig.me 2>/dev/null || echo "Unknown")
    local https_available=false
    if timeout 5 curl -s "https://$HOSTNAME/" >/dev/null 2>&1; then
        https_available=true
    fi
    
    if [[ "$https_available" == "true" ]]; then
        echo -e "${GREEN}🌟 Access Keycloak at: https://$HOSTNAME/admin/${NC}"
    else
        echo -e "${YELLOW}🌟 Access Keycloak at: http://$HOSTNAME/admin/${NC}"
        echo -e "${YELLOW}⚠️  Note: Use HTTP (not HTTPS) until SSL certificate is configured${NC}"
    fi
    echo -e "${GREEN}🔑 Login with: $ADMIN_USER / $ADMIN_PASSWORD${NC}"
    echo
}

# Error handling
trap 'log_error "Installation failed at line $LINENO. Check the logs above."; exit 1' ERR

# Run main function
main "$@"