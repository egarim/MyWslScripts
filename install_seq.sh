#!/bin/bash

# Seq Installation Script - Updated Version
# Requires Docker to be pre-installed

set -e  # Exit on any error

echo "=== Seq Logging Server Installation Script ==="
echo ""

# Check if Docker is installed and running
if ! command -v docker &> /dev/null; then
    echo "❌ Error: Docker is not installed or not in PATH"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "❌ Error: Docker daemon is not running or user doesn't have permission"
    echo "Try: sudo systemctl start docker"
    echo "Or add user to docker group: sudo usermod -aG docker \$USER"
    exit 1
fi

echo "✅ Docker is available"
echo ""

# Prompt for configuration
read -p "Enter the port to expose Seq on (default: 5341): " SEQ_PORT
SEQ_PORT=${SEQ_PORT:-5341}

read -p "Enter container name (default: seq): " CONTAINER_NAME
CONTAINER_NAME=${CONTAINER_NAME:-seq}

# Seq version selection
echo ""
echo "📋 Seq Version Selection:"
echo "1. Latest (2025.2) - Requires authentication setup"
echo "2. Stable (2024.4) - No authentication required"
read -p "Choose version (1/2, default: 2): " VERSION_CHOICE
VERSION_CHOICE=${VERSION_CHOICE:-2}

if [ "$VERSION_CHOICE" = "1" ]; then
    SEQ_IMAGE="datalust/seq:latest"
    echo ""
    echo "🔐 Authentication Configuration (Latest version):"
    echo "1. Disable authentication (recommended for development)"
    echo "2. Set admin password"
    read -p "Choose option (1/2, default: 1): " AUTH_CHOICE
    AUTH_CHOICE=${AUTH_CHOICE:-1}
    
    if [ "$AUTH_CHOICE" = "2" ]; then
        read -s -p "Enter admin password: " ADMIN_PASSWORD
        echo ""
        read -s -p "Confirm admin password: " ADMIN_PASSWORD_CONFIRM
        echo ""
        
        if [ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]; then
            echo "❌ Passwords don't match. Exiting."
            exit 1
        fi
    fi
else
    SEQ_IMAGE="datalust/seq:2024.4"
fi

# Data persistence
read -p "Do you want to set up data persistence? (y/n, default: y): " PERSIST_DATA
PERSIST_DATA=${PERSIST_DATA:-y}

if [[ "$PERSIST_DATA" == "y" || "$PERSIST_DATA" == "Y" ]]; then
    read -p "Enter local directory for Seq data (default: ./seq-data): " DATA_DIR
    DATA_DIR=${DATA_DIR:-./seq-data}
    
    # Create data directory if it doesn't exist
    if [ ! -d "$DATA_DIR" ]; then
        echo "📁 Creating data directory: $DATA_DIR"
        mkdir -p "$DATA_DIR"
    fi
    
    # Set proper permissions (999:999 is the user inside Seq container)
    sudo chown -R 999:999 "$DATA_DIR" 2>/dev/null || {
        echo "⚠️  Could not set permissions on $DATA_DIR. You may need to run: sudo chown -R 999:999 $DATA_DIR"
    }
fi

# Log retention settings
read -p "Set log retention in days (default: 7, 0 for unlimited): " RETENTION_DAYS
RETENTION_DAYS=${RETENTION_DAYS:-7}

# Check if container already exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo ""
    echo "⚠️  Container '$CONTAINER_NAME' already exists."
    read -p "Do you want to remove it and create a new one? (y/n): " REMOVE_EXISTING
    
    if [[ "$REMOVE_EXISTING" == "y" || "$REMOVE_EXISTING" == "Y" ]]; then
        echo "🗑️  Stopping and removing existing container..."
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
        docker rm "$CONTAINER_NAME" 2>/dev/null || true
        
        # Also clean up any existing data if user wants fresh start
        if [[ "$PERSIST_DATA" == "y" || "$PERSIST_DATA" == "Y" ]]; then
            read -p "Do you want to delete existing data in $DATA_DIR? (y/n, default: n): " DELETE_DATA
            if [[ "$DELETE_DATA" == "y" || "$DELETE_DATA" == "Y" ]]; then
                echo "🗑️  Removing existing data..."
                rm -rf "$DATA_DIR"
                mkdir -p "$DATA_DIR"
                sudo chown -R 999:999 "$DATA_DIR" 2>/dev/null || true
            fi
        fi
    else
        echo "❌ Installation cancelled."
        exit 1
    fi
fi

# Build docker run command
DOCKER_CMD="docker run -d --name $CONTAINER_NAME --restart unless-stopped"
DOCKER_CMD="$DOCKER_CMD -e ACCEPT_EULA=Y"

# Add authentication settings for latest version
if [ "$VERSION_CHOICE" = "1" ]; then
    if [ "$AUTH_CHOICE" = "1" ]; then
        DOCKER_CMD="$DOCKER_CMD -e SEQ_FIRSTRUN_NOAUTHENTICATION=true"
    else
        DOCKER_CMD="$DOCKER_CMD -e SEQ_FIRSTRUN_ADMINPASSWORD=$ADMIN_PASSWORD"
    fi
fi

# Use 0.0.0.0 to bind to all interfaces (fixes WSL networking)
DOCKER_CMD="$DOCKER_CMD -p 0.0.0.0:$SEQ_PORT:80"

# Add data persistence if requested
if [[ "$PERSIST_DATA" == "y" || "$PERSIST_DATA" == "Y" ]]; then
    DOCKER_CMD="$DOCKER_CMD -v $(realpath $DATA_DIR):/data"
fi

# Add retention policy
if [ "$RETENTION_DAYS" != "0" ]; then
    DOCKER_CMD="$DOCKER_CMD -e SEQ_CACHE_SYSTEMRAMTARGET=0.9 -e SEQ_STORAGE_RETENTIONDAYS=$RETENTION_DAYS"
fi

# Add the Docker image
DOCKER_CMD="$DOCKER_CMD $SEQ_IMAGE"

echo ""
echo "🚀 Starting Seq container..."
echo "Command: $DOCKER_CMD"
echo ""

# Run the container
if eval $DOCKER_CMD; then
    echo "✅ Seq container started successfully!"
    echo ""
    
    # Wait for container to be ready
    echo "⏳ Waiting for Seq to be ready..."
    READY=false
    for i in {1..30}; do
        if curl -s "http://localhost:$SEQ_PORT" > /dev/null 2>&1; then
            READY=true
            break
        fi
        sleep 2
        echo -n "."
    done
    echo ""
    
    if [ "$READY" = true ]; then
        echo "✅ Seq is ready!"
        
        echo ""
        echo "📊 Seq Details:"
        echo "   Container Name: $CONTAINER_NAME"
        echo "   Version: $SEQ_IMAGE"
        echo "   Port: $SEQ_PORT"
        echo "   Web Interface: http://localhost:$SEQ_PORT"
        
        if [[ "$PERSIST_DATA" == "y" || "$PERSIST_DATA" == "Y" ]]; then
            echo "   Data Directory: $(realpath $DATA_DIR)"
        fi
        
        if [ "$VERSION_CHOICE" = "1" ] && [ "$AUTH_CHOICE" = "2" ]; then
            echo "   Admin Username: admin"
            echo "   Admin Password: [hidden]"
        elif [ "$VERSION_CHOICE" = "1" ] && [ "$AUTH_CHOICE" = "1" ]; then
            echo "   Authentication: Disabled"
        fi
        
        echo ""
        echo "🔗 Connection URLs for your C# application:"
        echo "   From WSL: http://localhost:$SEQ_PORT"
        
        # Get WSL IP if we're in WSL
        if grep -q microsoft /proc/version 2>/dev/null; then
            WSL_IP=$(hostname -I | awk '{print $1}')
            if [ ! -z "$WSL_IP" ]; then
                echo "   From Windows: http://$WSL_IP:$SEQ_PORT"
                echo ""
                echo "💡 WSL Networking Tips:"
                echo "   - WSL IP: $WSL_IP"
                echo "   - If Windows can't access, run in PowerShell as Admin:"
                echo "     netsh interface portproxy add v4tov4 listenport=$SEQ_PORT listenaddress=0.0.0.0 connectport=$SEQ_PORT connectaddress=$WSL_IP"
            fi
        fi
        
        echo ""
        echo "📝 Example C# Serilog configuration:"
        echo "   Log.Logger = new LoggerConfiguration()"
        echo "       .WriteTo.Seq(\"http://localhost:$SEQ_PORT\")"
        echo "       .CreateLogger();"
        echo ""
        echo "📋 Useful Docker commands:"
        echo "   View logs: docker logs $CONTAINER_NAME"
        echo "   Stop Seq: docker stop $CONTAINER_NAME"
        echo "   Start Seq: docker start $CONTAINER_NAME"
        echo "   Remove Seq: docker stop $CONTAINER_NAME && docker rm $CONTAINER_NAME"
        
        # Write information to file
        echo ""
        echo "💾 Writing installation details to seq_info.txt..."
        
        cat > seq_info.txt << EOF
Seq Logging Server Installation Details
=======================================
Installation Date: $(date)
Container Name: $CONTAINER_NAME
Version: $SEQ_IMAGE
Port: $SEQ_PORT
Web Interface: http://localhost:$SEQ_PORT

EOF

        if [[ "$PERSIST_DATA" == "y" || "$PERSIST_DATA" == "Y" ]]; then
            echo "Data Directory: $(realpath $DATA_DIR)" >> seq_info.txt
            echo "" >> seq_info.txt
        fi

        if [ "$VERSION_CHOICE" = "1" ] && [ "$AUTH_CHOICE" = "2" ]; then
            cat >> seq_info.txt << EOF
Admin Credentials:
  Username: admin
  Password: [Check installation logs]

EOF
        elif [ "$VERSION_CHOICE" = "1" ] && [ "$AUTH_CHOICE" = "1" ]; then
            echo "Authentication: Disabled" >> seq_info.txt
            echo "" >> seq_info.txt
        fi

        cat >> seq_info.txt << EOF
Connection URLs for C# Application:
  From WSL: http://localhost:$SEQ_PORT
EOF

        # Add WSL IP if available
        if grep -q microsoft /proc/version 2>/dev/null; then
            WSL_IP=$(hostname -I | awk '{print $1}')
            if [ ! -z "$WSL_IP" ]; then
                cat >> seq_info.txt << EOF
  From Windows: http://$WSL_IP:$SEQ_PORT

WSL Networking:
  WSL IP: $WSL_IP
  Windows Port Forward Command (if needed):
    netsh interface portproxy add v4tov4 listenport=$SEQ_PORT listenaddress=0.0.0.0 connectport=$SEQ_PORT connectaddress=$WSL_IP
EOF
            fi
        fi

        cat >> seq_info.txt << EOF

C# Serilog Configuration Example:
Log.Logger = new LoggerConfiguration()
    .WriteTo.Seq("http://localhost:$SEQ_PORT")
    .CreateLogger();

Useful Docker Commands:
  View logs: docker logs $CONTAINER_NAME
  Stop Seq: docker stop $CONTAINER_NAME
  Start Seq: docker start $CONTAINER_NAME
  Remove Seq: docker stop $CONTAINER_NAME && docker rm $CONTAINER_NAME

Settings:
  Log retention: $RETENTION_DAYS days$([ "$RETENTION_DAYS" = "0" ] && echo " (unlimited)")
  Data persistence: $([ "$PERSIST_DATA" = "y" ] && echo "Enabled" || echo "Disabled")
EOF

        echo "✅ Installation details saved to seq_info.txt"
        echo ""
        echo "🎉 Installation complete!"
        echo "🌐 Access Seq at: http://localhost:$SEQ_PORT"
        
    else
        echo "⚠️  Seq container started but may not be fully ready yet."
        echo "   Check status with: docker logs $CONTAINER_NAME"
        echo "   Try accessing: http://localhost:$SEQ_PORT"
    fi
    
else
    echo "❌ Failed to start Seq container"
    echo "Check the error above and try again."
    exit 1
fi