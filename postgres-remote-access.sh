#!/bin/bash
# Script to enable remote access to PostgreSQL on Ubuntu 22.04
# Usage: sudo bash postgres-remote-access.sh [optional_password]

set -e

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root or with sudo"
  exit 1
fi

# Default PostgreSQL version on Ubuntu 22.04 is 14
PG_VERSION=14
PG_CONF="/etc/postgresql/$PG_VERSION/main/postgresql.conf"
PG_HBA="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"

# Detect PostgreSQL version if different
if ! grep -q "cluster_name.*main" "$PG_CONF" 2>/dev/null; then
  # Find installed PostgreSQL version
  for ver in $(ls /etc/postgresql/); do
    if [ -f "/etc/postgresql/$ver/main/postgresql.conf" ]; then
      PG_VERSION=$ver
      PG_CONF="/etc/postgresql/$PG_VERSION/main/postgresql.conf"
      PG_HBA="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"
      break
    fi
  done
fi

echo "Found PostgreSQL $PG_VERSION configuration at $PG_CONF"

# Backup configuration files
echo "Creating backup of PostgreSQL configuration files..."
cp "$PG_CONF" "$PG_CONF.bak"
cp "$PG_HBA" "$PG_HBA.bak"
echo "Backups created: $PG_CONF.bak and $PG_HBA.bak"

# Modify postgresql.conf to listen on all interfaces
echo "Configuring PostgreSQL to listen on all interfaces..."
if grep -q "^#listen_addresses" "$PG_CONF"; then
  # Uncomment and change the listen_addresses line
  sed -i "s/^#listen_addresses.*/listen_addresses = '*'/" "$PG_CONF"
elif grep -q "^listen_addresses" "$PG_CONF"; then
  # Change existing listen_addresses line
  sed -i "s/^listen_addresses.*/listen_addresses = '*'/" "$PG_CONF"
else
  # Add listen_addresses line if it doesn't exist
  echo "listen_addresses = '*'" >> "$PG_CONF"
fi

# Modify pg_hba.conf to allow remote connections
echo "Configuring pg_hba.conf to allow remote connections..."
if ! grep -q "^host.*all.*all.*0.0.0.0/0" "$PG_HBA"; then
  echo "# Allow remote connections with password authentication" >> "$PG_HBA"
  echo "host    all             all             0.0.0.0/0               md5" >> "$PG_HBA"
  echo "host    all             all             ::/0                    md5" >> "$PG_HBA"
fi

# Check and configure UFW firewall if it's active
if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
  echo "Configuring UFW firewall to allow PostgreSQL connections..."
  ufw allow 5432/tcp
  echo "UFW rule added for PostgreSQL (port 5432)"
fi

# Set a password for postgres user if provided
if [ -n "$1" ]; then
  echo "Setting password for PostgreSQL 'postgres' user..."
  su - postgres -c "psql -c \"ALTER USER postgres WITH PASSWORD '$1';\""
  echo "Password set for 'postgres' user"
else
  echo "No password provided. You should set a password for the 'postgres' user."
  echo "Run: sudo -u postgres psql -c \"ALTER USER postgres WITH PASSWORD 'your_secure_password';\""
fi

# Restart PostgreSQL to apply changes
echo "Restarting PostgreSQL service..."
systemctl restart postgresql

# Verify the service is running
if systemctl is-active --quiet postgresql; then
  echo "PostgreSQL service restarted successfully"
else
  echo "Error: PostgreSQL service failed to restart. Check logs with: journalctl -u postgresql"
  exit 1
fi

# Display connection information
echo
echo "PostgreSQL is now configured for remote access!"
echo "------------------------------------------------"
echo "Server IP Address(es):"
hostname -I
echo
echo "PostgreSQL port: 5432"
echo "Connect using: psql -h <server_ip_address> -U postgres -p 5432"
echo
echo "Important security notes:"
echo "- Your PostgreSQL server is now accessible from any IP address"
echo "- Make sure your database users have strong passwords"
echo "- Consider setting up SSL for encrypted connections"
echo "- For production environments, consider restricting access to specific IP addresses"
echo "------------------------------------------------"