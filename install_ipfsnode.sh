#!/bin/bash

# IPFS Node Installation Script for WSL2
# This script installs IPFS (Kubo) and configures custom ports

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

# Function to check if port is available
check_port() {
    local port=$1
    if ss -tuln | grep -q ":$port "; then
        return 1  # Port is in use
    else
        return 0  # Port is available
    fi
}

# Function to prompt for port with validation
prompt_port() {
    local port_name=$1
    local default_port=$2
    local port

    while true; do
        read -p "Enter $port_name port (default: $default_port): " port
        port=${port:-$default_port}

        # Validate port number
        if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
            print_error "Invalid port number. Please enter a port between 1024 and 65535."
            continue
        fi

        # Check if port is available
        if check_port "$port"; then
            echo "$port"
            return 0
        else
            print_warning "Port $port is already in use. Please choose another port."
        fi
    done
}

print_header "IPFS Node Installation for WSL2"
echo "This script will install IPFS (Kubo) and configure it with custom ports."
echo

# Check if running on WSL2
if ! grep -qi microsoft /proc/version; then
    print_warning "This script is designed for WSL2. Continuing anyway..."
fi

# Update system
print_status "Updating system packages..."
sudo apt update

# Install required dependencies
print_status "Installing dependencies..."
sudo apt install -y wget curl tar gpg

# Detect system architecture
print_status "Detecting system architecture..."
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        IPFS_ARCH="amd64"
        ;;
    aarch64|arm64)
        IPFS_ARCH="arm64"
        ;;
    armv7l)
        IPFS_ARCH="arm"
        ;;
    *)
        print_error "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

print_status "Detected architecture: $ARCH (using $IPFS_ARCH binary)"

# Get the latest IPFS version
print_status "Fetching latest IPFS version..."
IPFS_VERSION=$(curl -s https://api.github.com/repos/ipfs/kubo/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')

if [ -z "$IPFS_VERSION" ]; then
    print_error "Failed to fetch latest IPFS version. Using fallback version v0.25.0"
    IPFS_VERSION="0.25.0"
fi

print_status "Latest IPFS version: $IPFS_VERSION"

# Download IPFS
print_status "Downloading IPFS for $IPFS_ARCH..."
cd /tmp
wget "https://dist.ipfs.tech/kubo/v${IPFS_VERSION}/kubo_v${IPFS_VERSION}_linux-${IPFS_ARCH}.tar.gz"

# Extract and install
print_status "Extracting and installing IPFS..."
tar -xzf "kubo_v${IPFS_VERSION}_linux-${IPFS_ARCH}.tar.gz"
cd kubo

# Verify the binary works before installing
print_status "Verifying binary compatibility..."
if ! ./ipfs version >/dev/null 2>&1; then
    print_error "Binary is not compatible with your system architecture."
    print_error "Architecture detected: $ARCH"
    print_error "Please check if IPFS supports your architecture."
    exit 1
fi

sudo bash install.sh

# Clean up
rm -rf "/tmp/kubo_v${IPFS_VERSION}_linux-${IPFS_ARCH}.tar.gz" /tmp/kubo

# Check if IPFS is already initialized
if [ -d "$HOME/.ipfs" ]; then
    print_warning "IPFS repository already exists at $HOME/.ipfs"
    read -p "Do you want to reinitialize? This will DELETE existing data! (y/N): " reinit
    if [[ $reinit =~ ^[Yy]$ ]]; then
        rm -rf "$HOME/.ipfs"
        print_status "Initializing IPFS repository..."
        ipfs init
    else
        print_status "Using existing IPFS repository..."
    fi
else
    print_status "Initializing IPFS repository..."
    ipfs init
fi

# Get port configurations
print_header "Port Configuration"
echo "Configure custom ports for IPFS services:"
echo

API_PORT=$(prompt_port "API" 5001)
GATEWAY_PORT=$(prompt_port "Gateway" 8080)
SWARM_PORT=$(prompt_port "Swarm" 4001)

# Configure IPFS with custom ports
print_status "Configuring IPFS with custom ports..."

# API port (for web UI and API calls)
ipfs config Addresses.API "/ip4/0.0.0.0/tcp/$API_PORT"

# Gateway port (for accessing IPFS content via HTTP)
ipfs config Addresses.Gateway "/ip4/0.0.0.0/tcp/$GATEWAY_PORT"

# Swarm ports (for peer-to-peer connections)
ipfs config --json Addresses.Swarm "[
    \"/ip4/0.0.0.0/tcp/$SWARM_PORT\",
    \"/ip6/::/tcp/$SWARM_PORT\",
    \"/ip4/127.0.0.1/udp/$SWARM_PORT/quic\"
]"

# Configure for better WSL2 performance
print_status "Optimizing configuration for WSL2..."
ipfs config --json Datastore.GCPeriod '"1h"'
ipfs config --json Reprovider.Interval '"12h"'

# Create systemd service file
print_status "Creating systemd service..."
sudo tee /etc/systemd/system/ipfs.service > /dev/null <<EOF
[Unit]
Description=IPFS daemon
After=network.target

[Service]
Type=notify
User=$USER
ExecStart=/usr/local/bin/ipfs daemon --enable-gc
Restart=on-failure
RestartSec=5
Environment=IPFS_PATH=$HOME/.ipfs

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable ipfs

print_header "Installation Complete!"
echo
print_status "IPFS has been successfully installed and configured!"
echo
echo "Configuration Summary:"
echo "  • API Port:     $API_PORT"
echo "  • Gateway Port: $GATEWAY_PORT"
echo "  • Swarm Port:   $SWARM_PORT"
echo
echo "Access URLs (from Windows or WSL2):"
echo "  • Web UI:       http://localhost:$API_PORT/webui"
echo "  • Gateway:      http://localhost:$GATEWAY_PORT"
echo "  • API:          http://localhost:$API_PORT"
echo
echo "Service Management:"
echo "  • Start:        sudo systemctl start ipfs"
echo "  • Stop:         sudo systemctl stop ipfs"
echo "  • Status:       sudo systemctl status ipfs"
echo "  • Logs:         journalctl -u ipfs -f"
echo
echo "Manual Commands:"
echo "  • Start daemon: ipfs daemon"
echo "  • Add file:     ipfs add <filename>"
echo "  • Get file:     ipfs get <hash>"
echo

read -p "Do you want to start the IPFS daemon now? (Y/n): " start_now
if [[ ! $start_now =~ ^[Nn]$ ]]; then
    print_status "Starting IPFS daemon..."
    sudo systemctl start ipfs
    sleep 3
    
    if systemctl is-active --quiet ipfs; then
        print_status "IPFS daemon is running successfully!"
        echo "You can now access the Web UI at: http://localhost:$API_PORT/webui"
    else
        print_error "Failed to start IPFS daemon. Check logs with: journalctl -u ipfs"
    fi
fi

print_status "Installation script completed!"