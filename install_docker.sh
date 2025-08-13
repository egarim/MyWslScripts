#!/bin/bash

# Docker CE Installation Script for WSL2
# Based on the Athens Docker Adventure guide
# Compatible with both ARM64 and x64 architectures

set -e  # Exit on any error

echo "🐳 Docker CE Installation Script for WSL2"
echo "=========================================="
echo ""

# Check if running in WSL2
if ! grep -qi microsoft /proc/version; then
    echo "⚠️  Warning: This script is designed for WSL2. Please ensure you're running in WSL2."
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "Step 1: Updating system packages..."
sudo apt update && sudo apt upgrade -y
echo "✅ System packages updated"
echo ""

echo "Step 2: Installing required packages..."
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release
echo "✅ Required packages installed"
echo ""

echo "Step 3: Adding Docker's official GPG key..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "✅ Docker GPG key added"
echo ""

echo "Step 4: Setting up Docker repository..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
echo "✅ Docker repository configured"
echo ""

echo "Step 5: Updating APT with new repository..."
sudo apt update
echo "✅ APT updated"
echo ""

echo "Step 6: Installing Docker CE..."
sudo apt install -y docker-ce docker-ce-cli containerd.io
echo "✅ Docker CE installed"
echo ""

echo "Step 7: Starting Docker service..."
sudo service docker start
echo "✅ Docker service started"
echo ""

echo "Step 8: Adding current user to docker group..."
sudo usermod -aG docker $USER
echo "✅ User added to docker group"
echo ""

echo "Step 9: Applying group changes..."
newgrp docker
echo "✅ Group changes applied"
echo ""

echo "Step 10: Verifying installation..."
echo "Docker version:"
docker --version
echo ""
echo "Running hello-world container:"
docker run hello-world
echo "✅ Docker installation verified"
echo ""

echo "🎯 Setting up auto-start (optional)..."
read -p "Would you like Docker to start automatically when WSL2 launches? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Check which shell is being used
    if [[ $SHELL == *"zsh"* ]]; then
        SHELL_RC="$HOME/.zshrc"
    else
        SHELL_RC="$HOME/.bashrc"
    fi
    
    # Add auto-start command if not already present
    if ! grep -q "sudo service docker start" "$SHELL_RC" 2>/dev/null; then
        echo "sudo service docker start" >> "$SHELL_RC"
        echo "✅ Auto-start added to $SHELL_RC"
    else
        echo "ℹ️  Auto-start already configured in $SHELL_RC"
    fi
fi

echo ""
echo "🎉 Docker CE installation completed successfully!"
echo ""
echo "📝 Next steps:"
echo "   • You may need to restart your WSL2 session for group changes to take full effect"
echo "   • Try running: docker run hello-world"
echo "   • Explore Docker with: docker --help"
echo ""
echo "💡 Pro tips:"
echo "   • Use 'docker ps' to see running containers"
echo "   • Use 'docker images' to see available images"
echo "   • Docker runs in command-line mode (no Desktop UI in WSL2)"
echo ""
echo "Happy containerizing! 🐳"