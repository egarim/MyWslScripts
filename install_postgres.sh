#!/bin/bash
# Exit on error
set -e

echo "Installing PostgreSQL and required packages..."
sudo apt update
sudo apt install -y git
sudo apt install -y gnupg postgresql-common apt-transport-https lsb-release wget curl build-essential

# Run PostgreSQL repository setup script
sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y

# Install PostgreSQL development packages
sudo apt install -y postgresql-server-dev-17

# Add TimescaleDB repository for Ubuntu
curl -s https://packagecloud.io/install/repositories/timescale/timescaledb/script.deb.sh | sudo bash

# Update package list
sudo apt update

# Install TimescaleDB and PostgreSQL client
sudo apt install -y timescaledb-2-postgresql-17 postgresql-client-17

# Install pgvector from source
echo "Installing pgvector from source..."
cd /tmp
git clone --branch v0.5.1 https://github.com/pgvector/pgvector.git
cd pgvector
make
sudo make install

# Run TimescaleDB tuning
sudo timescaledb-tune --quiet --yes

# Restart PostgreSQL
sudo systemctl restart postgresql

# Set PostgreSQL password
echo "Setting PostgreSQL password..."
sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD '1234567890';"

# Add TimescaleDB extension to template1 (will be added to all new databases)
sudo -u postgres psql -d template1 -c 'CREATE EXTENSION IF NOT EXISTS timescaledb;'

# Add pgvector extension to template1
sudo -u postgres psql -d template1 -c 'CREATE EXTENSION IF NOT EXISTS vector;'

# Save installation details to a file
echo "Creating installation details file..."
cat << EOF > postgres_details.txt
PostgreSQL Installation Details
-----------------------------

Date of Installation: $(date)
PostgreSQL Version: $(psql -V)
TimescaleDB Version: $(psql -d template1 -c "SELECT extversion FROM pg_extension WHERE extname = 'timescaledb';" -t)
pgvector Version: $(psql -d template1 -c "SELECT extversion FROM pg_extension WHERE extname = 'vector';" -t)
Database Port: 5432
Database User: postgres
Database Password: 1234567890
Extensions Installed:
- TimescaleDB
- pgvector
EOF

echo "Installation details have been saved to postgres_details.txt"
echo "Installation complete!"
echo "PostgreSQL, TimescaleDB, and pgvector have been installed and configured."
echo "The PostgreSQL password has been set to: 1234567890"
