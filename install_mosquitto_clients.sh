#!/bin/bash

# Mosquitto MQTT Clients Installation Script
# Usage: ./install_mosquitto_clients.sh [install|test|help]
# 
# This script installs mosquitto-clients (mosquitto_pub, mosquitto_sub) 
# which are universal MQTT client tools that work with any MQTT broker
# including RabbitMQ, Eclipse Mosquitto, HiveMQ, AWS IoT Core, etc.

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if mosquitto clients are already installed
check_installation() {
    if command -v mosquitto_pub &> /dev/null && command -v mosquitto_sub &> /dev/null; then
        return 0  # Installed
    else
        return 1  # Not installed
    fi
}

# Detect the Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo $ID
    elif [ -f /etc/redhat-release ]; then
        echo "rhel"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

# Install mosquitto clients based on package manager
install_mosquitto_clients() {
    if check_installation; then
        print_success "mosquitto-clients are already installed!"
        show_version_info
        return 0
    fi

    print_status "Installing mosquitto MQTT client tools..."
    
    local distro=$(detect_distro)
    local install_cmd=""
    local package_name=""
    
    # Determine package manager and package name
    if command -v apt-get &> /dev/null; then
        install_cmd="sudo apt-get update && sudo apt-get install -y"
        package_name="mosquitto-clients"
        print_status "Detected Debian/Ubuntu system - using apt-get"
    elif command -v yum &> /dev/null; then
        install_cmd="sudo yum install -y"
        package_name="mosquitto"
        print_status "Detected RHEL/CentOS system - using yum"
    elif command -v dnf &> /dev/null; then
        install_cmd="sudo dnf install -y"
        package_name="mosquitto"
        print_status "Detected Fedora system - using dnf"
    elif command -v apk &> /dev/null; then
        install_cmd="sudo apk add"
        package_name="mosquitto-clients"
        print_status "Detected Alpine system - using apk"
    elif command -v pacman &> /dev/null; then
        install_cmd="sudo pacman -S --noconfirm"
        package_name="mosquitto"
        print_status "Detected Arch system - using pacman"
    elif command -v zypper &> /dev/null; then
        install_cmd="sudo zypper install -y"
        package_name="mosquitto"
        print_status "Detected openSUSE system - using zypper"
    else
        print_error "Could not detect a supported package manager"
        print_error "Please install mosquitto-clients manually for your distribution"
        show_manual_installation
        return 1
    fi
    
    print_status "Installing package: ${package_name}"
    print_status "Using command: ${install_cmd} ${package_name}"
    
    # Execute installation
    if eval "${install_cmd} ${package_name}"; then
        print_success "mosquitto-clients installed successfully!"
        
        # Verify installation
        if check_installation; then
            print_success "Installation verified - tools are working!"
            show_version_info
            show_usage_examples
            return 0
        else
            print_error "Installation completed but tools are not accessible"
            print_error "You may need to restart your terminal or check your PATH"
            return 1
        fi
    else
        print_error "Installation failed"
        print_error "You may need to run this script with sudo permissions"
        show_manual_installation
        return 1
    fi
}

# Show version information
show_version_info() {
    echo
    echo "=== Mosquitto Clients Information ==="
    
    if command -v mosquitto_pub &> /dev/null; then
        echo "mosquitto_pub: $(mosquitto_pub --help 2>&1 | head -n 1 | grep -o 'version [0-9.]*' || echo 'Available')"
    fi
    
    if command -v mosquitto_sub &> /dev/null; then
        echo "mosquitto_sub: $(mosquitto_sub --help 2>&1 | head -n 1 | grep -o 'version [0-9.]*' || echo 'Available')"
    fi
    
    echo "Location: $(which mosquitto_pub 2>/dev/null || echo 'Not found')"
    echo
}

# Show usage examples
show_usage_examples() {
    echo "=== Usage Examples ==="
    echo
    echo "📤 Publishing Messages:"
    echo "mosquitto_pub -h <broker_host> -p <port> -u <username> -P <password> -t <topic> -m <message>"
    echo
    echo "📥 Subscribing to Topics:"
    echo "mosquitto_sub -h <broker_host> -p <port> -u <username> -P <password> -t <topic>"
    echo
    echo "🔗 Common Examples:"
    echo "# Test with local broker (no auth)"
    echo "mosquitto_pub -h localhost -p 1883 -t test/topic -m \"Hello MQTT\""
    echo "mosquitto_sub -h localhost -p 1883 -t test/topic"
    echo
    echo "# Test with authentication"
    echo "mosquitto_pub -h localhost -p 1883 -u admin -P password -t test/topic -m \"Hello MQTT\""
    echo "mosquitto_sub -h localhost -p 1883 -u admin -P password -t test/topic"
    echo
    echo "# Test with remote broker"
    echo "mosquitto_pub -h broker.example.com -p 1883 -u user -P pass -t sensors/temperature -m \"22.5\""
    echo
    echo "🛠️  Advanced Options:"
    echo "# QoS levels (0, 1, 2)"
    echo "mosquitto_pub -h localhost -p 1883 -t test/topic -m \"Hello\" -q 1"
    echo
    echo "# Retain messages"
    echo "mosquitto_pub -h localhost -p 1883 -t test/topic -m \"Hello\" -r"
    echo
    echo "# Subscribe with specific count"
    echo "mosquitto_sub -h localhost -p 1883 -t test/topic -C 5  # Exit after 5 messages"
    echo
    echo "# Multiple topics"
    echo "mosquitto_sub -h localhost -p 1883 -t sensors/+ -t alerts/#"
    echo
}

# Show manual installation instructions
show_manual_installation() {
    echo
    echo "=== Manual Installation Instructions ==="
    echo
    echo "For Debian/Ubuntu:"
    echo "sudo apt update && sudo apt install mosquitto-clients"
    echo
    echo "For RHEL/CentOS/Fedora:"
    echo "sudo yum install mosquitto  # or sudo dnf install mosquitto"
    echo
    echo "For Alpine:"
    echo "sudo apk add mosquitto-clients"
    echo
    echo "For Arch:"
    echo "sudo pacman -S mosquitto"
    echo
    echo "For openSUSE:"
    echo "sudo zypper install mosquitto"
    echo
    echo "Alternative: Build from source"
    echo "Visit: https://mosquitto.org/download/"
    echo
}

# Test mosquitto clients installation
test_installation() {
    print_status "Testing mosquitto-clients installation..."
    
    if ! check_installation; then
        print_error "mosquitto-clients are not installed"
        print_status "Run '$0 install' to install them"
        return 1
    fi
    
    print_success "mosquitto-clients are installed and accessible"
    
    # Test basic functionality
    print_status "Testing basic functionality..."
    
    # Test mosquitto_pub help
    if mosquitto_pub --help &>/dev/null; then
        print_success "✅ mosquitto_pub is working"
    else
        print_warning "⚠️  mosquitto_pub may have issues"
    fi
    
    # Test mosquitto_sub help  
    if mosquitto_sub --help &>/dev/null; then
        print_success "✅ mosquitto_sub is working"
    else
        print_warning "⚠️  mosquitto_sub may have issues"
    fi
    
    show_version_info
    
    echo "🧪 To test with a real MQTT broker:"
    echo "1. Start an MQTT broker (like RabbitMQ with MQTT plugin)"
    echo "2. Use the examples shown above"
    echo "3. Or run a quick local test:"
    echo
    echo "# Terminal 1 (subscriber):"
    echo "mosquitto_sub -h localhost -p 1883 -t test/topic"
    echo
    echo "# Terminal 2 (publisher):"
    echo "mosquitto_pub -h localhost -p 1883 -t test/topic -m \"Hello World\""
    echo
}

# Show help information
show_help() {
    echo "Mosquitto MQTT Clients Installation Script"
    echo
    echo "This script installs mosquitto_pub and mosquitto_sub, which are"
    echo "universal MQTT client tools that work with any MQTT broker."
    echo
    echo "Usage: $0 [COMMAND]"
    echo
    echo "Commands:"
    echo "  install   - Install mosquitto-clients package"
    echo "  test      - Test if mosquitto-clients are installed and working"
    echo "  help      - Show this help message"
    echo
    echo "What are mosquitto-clients?"
    echo "• mosquitto_pub: Command-line MQTT publisher"
    echo "• mosquitto_sub: Command-line MQTT subscriber"
    echo "• Universal tools that work with ANY MQTT broker"
    echo "• Essential for MQTT testing and automation"
    echo
    echo "Compatible MQTT Brokers:"
    echo "• RabbitMQ (with MQTT plugin)"
    echo "• Eclipse Mosquitto"
    echo "• HiveMQ"
    echo "• AWS IoT Core"
    echo "• Azure IoT Hub"
    echo "• Google Cloud IoT Core"
    echo "• Any MQTT 3.1.1 or 5.0 compliant broker"
    echo
    echo "Examples after installation:"
    echo "• Test publish: mosquitto_pub -h localhost -p 1883 -t test -m \"hello\""
    echo "• Test subscribe: mosquitto_sub -h localhost -p 1883 -t test"
    echo
}

# Generate installation log
generate_installation_log() {
    local log_file="/tmp/mosquitto_clients_installation_$(date +%Y%m%d_%H%M%S).log"
    
    {
        echo "=========================================="
        echo "Mosquitto MQTT Clients - Installation Log"
        echo "Generated: $(date)"
        echo "=========================================="
        echo
        
        echo "=== SYSTEM INFORMATION ==="
        echo "OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"' || uname -s)"
        echo "Kernel: $(uname -r)"
        echo "Architecture: $(uname -m)"
        echo "Distribution: $(detect_distro)"
        echo
        
        echo "=== INSTALLATION STATUS ==="
        if check_installation; then
            echo "✅ mosquitto-clients: INSTALLED"
            echo "mosquitto_pub: $(which mosquitto_pub)"
            echo "mosquitto_sub: $(which mosquitto_sub)"
            
            # Try to get version
            local version=$(mosquitto_pub --help 2>&1 | head -n 1 | grep -o 'version [0-9.]*' || echo 'Unknown version')
            echo "Version: ${version}"
        else
            echo "❌ mosquitto-clients: NOT INSTALLED"
        fi
        echo
        
        echo "=== PACKAGE MANAGER ==="
        if command -v apt-get &> /dev/null; then
            echo "Package Manager: apt-get (Debian/Ubuntu)"
        elif command -v yum &> /dev/null; then
            echo "Package Manager: yum (RHEL/CentOS)"
        elif command -v dnf &> /dev/null; then
            echo "Package Manager: dnf (Fedora)"
        elif command -v apk &> /dev/null; then
            echo "Package Manager: apk (Alpine)"
        elif command -v pacman &> /dev/null; then
            echo "Package Manager: pacman (Arch)"
        elif command -v zypper &> /dev/null; then
            echo "Package Manager: zypper (openSUSE)"
        else
            echo "Package Manager: Unknown/Unsupported"
        fi
        echo
        
        echo "=== USAGE EXAMPLES ==="
        echo "# Basic publish/subscribe test"
        echo "mosquitto_pub -h localhost -p 1883 -t test/topic -m \"Hello MQTT\""
        echo "mosquitto_sub -h localhost -p 1883 -t test/topic"
        echo
        echo "# With authentication"
        echo "mosquitto_pub -h localhost -p 1883 -u username -P password -t test/topic -m \"Hello\""
        echo "mosquitto_sub -h localhost -p 1883 -u username -P password -t test/topic"
        echo
        
        echo "=== TROUBLESHOOTING ==="
        echo "If tools are not found after installation:"
        echo "1. Restart your terminal session"
        echo "2. Check PATH: echo \$PATH"
        echo "3. Verify installation: which mosquitto_pub"
        echo "4. Try absolute path: /usr/bin/mosquitto_pub --help"
        echo
        echo "Common issues:"
        echo "- Permission denied: Use sudo for installation"
        echo "- Package not found: Update package cache first"
        echo "- Command not found: Check if /usr/bin is in PATH"
        echo
        
        echo "=== LOG COMPLETED ==="
        echo "Timestamp: $(date)"
        echo "Log file: ${log_file}"
        echo "=========================================="
        
    } > "${log_file}"
    
    print_success "Installation log saved to: ${log_file}"
}

# Main script logic
case "${1:-}" in
    "install")
        install_mosquitto_clients
        if [ $? -eq 0 ]; then
            generate_installation_log
        fi
        ;;
    "test")
        test_installation
        ;;
    "help"|"--help"|"-h")
        show_help
        ;;
    "")
        echo "🦟 Mosquitto MQTT Clients Installer"
        echo "===================================="
        echo
        if check_installation; then
            print_success "mosquitto-clients are already installed!"
            show_version_info
            echo "Run '$0 test' for detailed testing"
            echo "Run '$0 help' for usage examples"
        else
            print_status "mosquitto-clients are not installed"
            echo
            echo "These tools allow you to test MQTT connections with any broker:"
            echo "• mosquitto_pub - Publish messages to MQTT topics"
            echo "• mosquitto_sub - Subscribe to MQTT topics"
            echo
            read -p "Would you like to install mosquitto-clients now? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                install_mosquitto_clients
                if [ $? -eq 0 ]; then
                    generate_installation_log
                fi
            else
                print_status "You can install later by running: $0 install"
                echo
                show_help
            fi
        fi
        ;;
    *)
        print_error "Unknown command: $1"
        echo
        show_help
        exit 1
        ;;
esac
