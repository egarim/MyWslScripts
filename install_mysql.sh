#!/bin/bash

# Exit on any error
set -e

# Variables
MYSQL_ROOT_PASSWORD="1234567890"

# Function to print status messages
print_status() {
    echo "==> $1"
}

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root or with sudo"
    exit 1
fi

# Update package list
print_status "Updating package list..."
apt-get update

# Install MySQL Server
print_status "Installing MySQL Server..."
DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server

# Ensure MySQL is running
print_status "Starting MySQL service..."
systemctl start mysql
systemctl enable mysql

# Secure MySQL installation
print_status "Configuring MySQL root password..."
mysql --user=root <<_EOF_
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
_EOF_

# Update MySQL configuration to allow remote connections
print_status "Configuring MySQL to allow remote connections..."
cat > /etc/mysql/mysql.conf.d/mysqld.cnf << EOF
[mysqld]
pid-file        = /var/run/mysqld/mysqld.pid
socket          = /var/run/mysqld/mysqld.sock
datadir         = /var/lib/mysql
log-error       = /var/log/mysql/error.log
bind-address    = 0.0.0.0
EOF

# Create root user that can connect from any host
print_status "Creating root user for remote connections..."
mysql --user=root --password="${MYSQL_ROOT_PASSWORD}" <<_EOF_
CREATE USER 'root'@'%' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
_EOF_

# Restart MySQL to apply changes
print_status "Restarting MySQL service..."
systemctl restart mysql

# Configure firewall if it's active
if command -v ufw >/dev/null 2>&1; then
    print_status "Configuring firewall..."
    ufw allow 3306/tcp
fi

print_status "MySQL installation and configuration completed!"
print_status "Root password has been set to: ${MYSQL_ROOT_PASSWORD}"
print_status "MySQL is now accessible from any host on port 3306"
