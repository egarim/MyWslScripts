#!/bin/bash

# Keycloak Installation Script for WSL2 Ubuntu
# This script installs Keycloak with PostgreSQL integration

# Exit on any error
set -e

# Configuration variables - modify these as needed
KEYCLOAK_VERSION="21.1.2"
POSTGRES_JDBC_VERSION="42.6.0"
KEYCLOAK_PORT=8080
DB_HOST="localhost"
DB_PORT=5432
DB_NAME="keycloak"
JAVA_VERSION="openjdk-17-jdk"

# Print section header
section() {
    echo "==============================================="
    echo "  $1"
    echo "==============================================="
}

# Update system packages
section "Updating system packages"
sudo apt update && sudo apt upgrade -y

# Install Java if not already installed
section "Installing Java"
if ! command -v java &> /dev/null; then
    sudo apt install $JAVA_VERSION -y
fi
java -version

# Install PostgreSQL client tools
section "Installing PostgreSQL client tools"
sudo apt install postgresql-client -y

# Create installation directory
section "Creating installation directory"
INSTALL_DIR="$HOME/keycloak"
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# Download and extract Keycloak
section "Downloading Keycloak $KEYCLOAK_VERSION"
if [ ! -f "keycloak-$KEYCLOAK_VERSION.tar.gz" ]; then
    wget https://github.com/keycloak/keycloak/releases/download/$KEYCLOAK_VERSION/keycloak-$KEYCLOAK_VERSION.tar.gz
fi

section "Extracting Keycloak"
if [ ! -d "keycloak-$KEYCLOAK_VERSION" ]; then
    tar -xvzf keycloak-$KEYCLOAK_VERSION.tar.gz
fi

# Set up Keycloak directory
KEYCLOAK_DIR="$INSTALL_DIR/keycloak-$KEYCLOAK_VERSION"
cd $KEYCLOAK_DIR

# Download PostgreSQL JDBC driver
section "Downloading PostgreSQL JDBC driver"
mkdir -p providers
if [ ! -f "providers/postgresql-$POSTGRES_JDBC_VERSION.jar" ]; then
    wget https://jdbc.postgresql.org/download/postgresql-$POSTGRES_JDBC_VERSION.jar -P providers/
fi

# Database configuration
section "Database Configuration"
echo "Enter your PostgreSQL database details:"
read -p "Database host [$DB_HOST]: " input_host
DB_HOST=${input_host:-$DB_HOST}

read -p "Database port [$DB_PORT]: " input_port
DB_PORT=${input_port:-$DB_PORT}

read -p "Database name [$DB_NAME]: " input_dbname
DB_NAME=${input_dbname:-$DB_NAME}

read -p "Database username: " DB_USER
while [ -z "$DB_USER" ]; do
    echo "Username cannot be empty"
    read -p "Database username: " DB_USER
done

read -sp "Database password: " DB_PASSWORD
echo ""
while [ -z "$DB_PASSWORD" ]; do
    echo "Password cannot be empty"
    read -sp "Database password: " DB_PASSWORD
    echo ""
done

# Create database setup script
section "Creating database setup script"
cat > create_db.sql <<EOF
CREATE DATABASE $DB_NAME WITH ENCODING='UTF8';
EOF

# Verify database connection
section "Verifying database connection"
echo "Attempting to connect to PostgreSQL..."
if PGPASSWORD="$DB_PASSWORD" psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d postgres -c "SELECT 1" &>/dev/null; then
    echo "Connection successful!"
    
    # Check if database exists
    if ! PGPASSWORD="$DB_PASSWORD" psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d postgres -c "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1; then
        echo "Creating database $DB_NAME..."
        PGPASSWORD="$DB_PASSWORD" psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d postgres -f create_db.sql
        echo "Database created successfully!"
    else
        echo "Database $DB_NAME already exists."
    fi
else
    echo "Failed to connect to PostgreSQL. Please check your credentials and try again."
    exit 1
fi

# Build Keycloak
section "Building Keycloak"
./bin/kc.sh build

# Create startup script
section "Creating startup script"
cat > start-keycloak.sh <<EOF
#!/bin/bash
cd $KEYCLOAK_DIR
./bin/kc.sh start-dev \\
  --db=postgres \\
  --db-url=jdbc:postgresql://$DB_HOST:$DB_PORT/$DB_NAME \\
  --db-username=$DB_USER \\
  --db-password=$DB_PASSWORD \\
  --http-port=$KEYCLOAK_PORT
EOF

chmod +x start-keycloak.sh

# Create a desktop shortcut
section "Creating desktop shortcut"
mkdir -p ~/Desktop
cat > ~/Desktop/keycloak.desktop <<EOF
[Desktop Entry]
Name=Keycloak
Exec=bash -c "$KEYCLOAK_DIR/start-keycloak.sh"
Type=Application
Terminal=true
EOF

chmod +x ~/Desktop/keycloak.desktop

# Get the WSL2 IP address
WSL_IP=$(ip addr show eth0 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)

section "Installation Complete"
echo "Keycloak has been installed successfully!"
echo ""
echo "To start Keycloak:"
echo "  1. Run: $KEYCLOAK_DIR/start-keycloak.sh"
echo "  2. Or use the desktop shortcut created"
echo ""
echo "Access the Keycloak console at: http://$WSL_IP:$KEYCLOAK_PORT"
echo ""
echo "Database Configuration:"
echo "  - Host: $DB_HOST"
echo "  - Port: $DB_PORT"
echo "  - Database: $DB_NAME"
echo "  - Username: $DB_USER"
echo ""
echo "Note: The database password is stored in the start-keycloak.sh script."
echo "For security in production environments, consider using environment variables instead."
