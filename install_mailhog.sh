#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== MailHog Installation Script ===${NC}"
echo "This script will install MailHog, a simple SMTP test server with a web interface."

# Check if MailHog is already installed
if command -v MailHog &> /dev/null || [ -f "$HOME/go/bin/MailHog" ]; then
    echo -e "${YELLOW}MailHog appears to be already installed.${NC}"
    read -p "Do you want to reinstall it? (yes/no) [no]: " REINSTALL
    REINSTALL=${REINSTALL:-"no"}
    
    if [[ "$REINSTALL" != "yes" ]]; then
        echo -e "${GREEN}Using existing MailHog installation.${NC}"
        SKIP_INSTALL="yes"
    else
        echo -e "${YELLOW}Proceeding with reinstallation...${NC}"
        SKIP_INSTALL="no"
    fi
else
    SKIP_INSTALL="no"
fi

# Default values
DEFAULT_INSTALL_DIR="$HOME/go/bin"
DEFAULT_SMTP_PORT=1025
DEFAULT_WEB_PORT=8025
DEFAULT_AUTOSTART="no"
DEFAULT_CREATE_SERVICE="no"

# Prompt for user input with defaults
read -p "Installation directory [$DEFAULT_INSTALL_DIR]: " INSTALL_DIR
INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}

read -p "SMTP port [$DEFAULT_SMTP_PORT]: " SMTP_PORT
SMTP_PORT=${SMTP_PORT:-$DEFAULT_SMTP_PORT}

read -p "Web interface port [$DEFAULT_WEB_PORT]: " WEB_PORT
WEB_PORT=${WEB_PORT:-$DEFAULT_WEB_PORT}

read -p "Start MailHog automatically when script finishes? (yes/no) [$DEFAULT_AUTOSTART]: " AUTOSTART
AUTOSTART=${AUTOSTART:-$DEFAULT_AUTOSTART}

read -p "Create systemd service for auto-start on boot? (yes/no) [$DEFAULT_CREATE_SERVICE]: " CREATE_SERVICE
CREATE_SERVICE=${CREATE_SERVICE:-$DEFAULT_CREATE_SERVICE}

# Create installation directory if it doesn't exist
if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${YELLOW}Creating installation directory: $INSTALL_DIR${NC}"
    mkdir -p "$INSTALL_DIR"
fi

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo -e "${YELLOW}Go is not installed. Installing Go...${NC}"
    sudo apt update
    sudo apt install -y golang-go
else
    echo -e "${GREEN}Go is already installed.${NC}"
fi

# Add Go bin to PATH if not already there
if [[ ":$PATH:" != *":$HOME/go/bin:"* ]]; then
    echo -e "${YELLOW}Adding Go bin directory to PATH...${NC}"
    echo 'export PATH=$PATH:~/go/bin' >> ~/.bashrc
    export PATH=$PATH:~/go/bin
    echo -e "${GREEN}Added Go bin to PATH.${NC}"
else
    echo -e "${GREEN}Go bin already in PATH.${NC}"
fi

# Install MailHog if not skipping installation
if [[ "$SKIP_INSTALL" != "yes" ]]; then
    echo -e "${YELLOW}Installing MailHog...${NC}"
    go install github.com/mailhog/MailHog@latest

    # Check if installation was successful
    if [ -f "$HOME/go/bin/MailHog" ]; then
        echo -e "${GREEN}MailHog installed successfully!${NC}"
        
        # Copy to target directory if different from default
        if [ "$INSTALL_DIR" != "$HOME/go/bin" ]; then
            cp "$HOME/go/bin/MailHog" "$INSTALL_DIR"
            echo -e "${GREEN}Copied MailHog to $INSTALL_DIR${NC}"
        fi
    else
        echo -e "${RED}MailHog installation failed!${NC}"
        exit 1
    fi
else
    # If using existing installation, check if we need to copy to target directory
    if [ -f "$HOME/go/bin/MailHog" ] && [ "$INSTALL_DIR" != "$HOME/go/bin" ] && [ ! -f "$INSTALL_DIR/MailHog" ]; then
        mkdir -p "$INSTALL_DIR"
        cp "$HOME/go/bin/MailHog" "$INSTALL_DIR"
        echo -e "${GREEN}Copied existing MailHog to $INSTALL_DIR${NC}"
    fi
fi

# Create a convenience script to start MailHog with custom settings
STARTUP_SCRIPT="$HOME/start-mailhog.sh"
echo -e "${YELLOW}Creating startup script: $STARTUP_SCRIPT${NC}"

cat > "$STARTUP_SCRIPT" << EOF
#!/bin/bash
echo "Starting MailHog SMTP server on port $SMTP_PORT and web interface on port $WEB_PORT"
nohup $INSTALL_DIR/MailHog -smtp-bind-addr 0.0.0.0:$SMTP_PORT -ui-bind-addr 0.0.0.0:$WEB_PORT > /dev/null 2>&1 &
echo "MailHog started. Web interface available at http://localhost:$WEB_PORT"
echo "To find your WSL2 IP address for external connections:"
echo "ip addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}'"
EOF

chmod +x "$STARTUP_SCRIPT"

# Create systemd service if requested
if [[ "$CREATE_SERVICE" == "yes" ]]; then
    SERVICE_FILE="/etc/systemd/system/mailhog.service"
    
    # Check if systemd is available
    if command -v systemctl &> /dev/null; then
        echo -e "${YELLOW}Creating systemd service...${NC}"
        
        sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=MailHog Email Catcher
After=network.target

[Service]
ExecStart=$INSTALL_DIR/MailHog -smtp-bind-addr 0.0.0.0:$SMTP_PORT -ui-bind-addr 0.0.0.0:$WEB_PORT
Restart=always
User=$USER

[Install]
WantedBy=multi-user.target
EOF

        sudo systemctl daemon-reload
        sudo systemctl enable mailhog.service
        sudo systemctl start mailhog.service
        echo -e "${GREEN}Systemd service created and started.${NC}"
    else
        echo -e "${RED}Systemd not available. Service creation skipped.${NC}"
        CREATE_SERVICE="no"
    fi
fi

# Start MailHog if requested
if [[ "$AUTOSTART" == "yes" && "$CREATE_SERVICE" == "no" ]]; then
    echo -e "${YELLOW}Starting MailHog...${NC}"
    bash "$STARTUP_SCRIPT"
    echo -e "${GREEN}MailHog started.${NC}"
fi

# Print summary
echo -e "\n${BLUE}=== Installation Summary ===${NC}"
echo -e "MailHog installed to: ${GREEN}$INSTALL_DIR${NC}"
echo -e "SMTP server port: ${GREEN}$SMTP_PORT${NC}"
echo -e "Web interface port: ${GREEN}$WEB_PORT${NC}"
echo -e "Startup script created: ${GREEN}$STARTUP_SCRIPT${NC}"

if [[ "$CREATE_SERVICE" == "yes" ]]; then
    echo -e "Systemd service: ${GREEN}Created and enabled${NC}"
    echo -e "To manage service: ${YELLOW}sudo systemctl start|stop|status mailhog.service${NC}"
else
    echo -e "To start MailHog: ${YELLOW}$STARTUP_SCRIPT${NC}"
fi

echo -e "\nSMTP Settings for your applications:"
echo -e "Host: ${GREEN}localhost${NC} (or your WSL2 IP for external access)"
echo -e "Port: ${GREEN}$SMTP_PORT${NC}"
echo -e "Authentication: ${GREEN}None${NC}"
echo -e "Encryption: ${GREEN}None${NC}"
echo -e "Web Interface: ${GREEN}http://localhost:$WEB_PORT${NC}"

exit 0
