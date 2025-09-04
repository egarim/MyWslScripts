#!/bin/bash

# RabbitMQ Docker Manager Script
# Usage: ./rabbitmq-manager.sh [start|stop|restart|status|logs|remove|install]

CONTAINER_NAME="rabbitmq"
IMAGE_NAME="rabbitmq:3-management"
VOLUME_NAME="rabbitmq_data"
AMQP_PORT="5672"
MGMT_PORT="15672"
DEFAULT_USER="admin"
DEFAULT_PASS="password"

# MQTT Configuration
MQTT_PORT="1883"           # Non-TLS MQTT port
MQTT_TLS_PORT="8883"       # TLS MQTT port  
MQTT_WS_PORT="15675"       # MQTT over WebSockets
ENABLE_MQTT_TLS="false"    # Set to true to enable TLS

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

check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running"
        exit 1
    fi
}

container_exists() {
    docker ps -a --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"
}

container_running() {
    docker ps --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"
}

volume_exists() {
    docker volume ls --format "table {{.Name}}" | grep -q "^${VOLUME_NAME}$"
}

create_volume() {
    if ! volume_exists; then
        print_status "Creating volume ${VOLUME_NAME}..."
        docker volume create ${VOLUME_NAME}
        print_success "Volume ${VOLUME_NAME} created"
    else
        print_status "Volume ${VOLUME_NAME} already exists"
    fi
}

# MQTT Plugin Management Functions
check_mqtt_plugin() {
    if ! container_running; then
        return 1
    fi
    
    # Check if MQTT plugin is enabled
    docker exec ${CONTAINER_NAME} rabbitmq-plugins list | grep -q "E.*rabbitmq_mqtt"
    return $?
}

enable_mqtt_plugin() {
    if ! container_running; then
        print_error "Container is not running"
        return 1
    fi
    
    print_status "Enabling MQTT plugins..."
    docker exec ${CONTAINER_NAME} rabbitmq-plugins enable rabbitmq_mqtt rabbitmq_web_mqtt
    
    if [ $? -eq 0 ]; then
        print_success "MQTT plugins enabled successfully"
        return 0
    else
        print_error "Failed to enable MQTT plugins"
        return 1
    fi
}

test_mqtt_connection() {
    if ! container_running; then
        print_error "Container is not running"
        return 1
    fi
    
    print_status "Testing MQTT connection..."
    
    # Check if mosquitto clients are available
    if ! command -v mosquitto_pub &> /dev/null; then
        print_status "Installing mosquitto-clients for testing..."
        install_mqtt_clients
    fi
    
    # Test MQTT connection
    local test_topic="test/rabbitmq/$(date +%s)"
    local test_message="Hello from RabbitMQ MQTT at $(date)"
    
    print_status "Publishing test message to topic: ${test_topic}"
    timeout 10 mosquitto_pub -h localhost -p ${MQTT_PORT} -u ${DEFAULT_USER} -P ${DEFAULT_PASS} -t "${test_topic}" -m "${test_message}" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        print_success "✅ MQTT publish test successful"
        
        # Test subscribe
        print_status "Testing MQTT subscribe (will timeout after 5 seconds)..."
        timeout 5 mosquitto_sub -h localhost -p ${MQTT_PORT} -u ${DEFAULT_USER} -P ${DEFAULT_PASS} -t "${test_topic}" -C 1 2>/dev/null
        
        if [ $? -eq 0 ] || [ $? -eq 124 ]; then  # 124 is timeout exit code
            print_success "✅ MQTT subscribe test completed"
            return 0
        else
            print_warning "⚠️  MQTT subscribe test had issues"
            return 1
        fi
    else
        print_error "❌ MQTT publish test failed"
        return 1
    fi
}

install_mqtt_clients() {
    if command -v mosquitto_pub &> /dev/null; then
        print_status "mosquitto-clients already installed"
        return 0
    fi
    
    print_status "Installing mosquitto-clients..."
    print_status "Note: You can also use './install_mosquitto_clients.sh' for standalone installation"
    
    # Detect package manager and install
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y mosquitto-clients
    elif command -v yum &> /dev/null; then
        sudo yum install -y mosquitto
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y mosquitto
    elif command -v apk &> /dev/null; then
        sudo apk add mosquitto-clients
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm mosquitto
    elif command -v zypper &> /dev/null; then
        sudo zypper install -y mosquitto
    else
        print_warning "Could not detect package manager."
        print_status "You can install mosquitto-clients using the standalone script:"
        print_status "./install_mosquitto_clients.sh install"
        return 1
    fi
    
    if [ $? -eq 0 ]; then
        print_success "mosquitto-clients installed successfully"
        return 0
    else
        print_error "Failed to install mosquitto-clients"
        print_status "Try using the standalone installer: ./install_mosquitto_clients.sh install"
        return 1
    fi
}

show_mqtt_status() {
    if ! container_running; then
        print_error "Container is not running"
        return 1
    fi
    
    echo
    echo "=== MQTT Status ==="
    
    # Check plugin status
    if check_mqtt_plugin; then
        print_success "MQTT plugin is enabled"
    else
        print_error "MQTT plugin is not enabled"
        echo "Run '$0 mqtt-enable' to enable MQTT plugins"
        return 1
    fi
    
    # Show MQTT ports
    echo "MQTT Ports:"
    echo "  • Non-TLS MQTT: ${MQTT_PORT}"
    echo "  • WebSocket MQTT: ${MQTT_WS_PORT}"
    if [ "$ENABLE_MQTT_TLS" = "true" ]; then
        echo "  • TLS MQTT: ${MQTT_TLS_PORT}"
    else
        echo "  • TLS MQTT: Disabled (set ENABLE_MQTT_TLS=true to enable)"
    fi
    
    # Test connections
    echo
    echo "Connection Examples:"
    echo "  • mosquitto_pub -h localhost -p ${MQTT_PORT} -u ${DEFAULT_USER} -P ${DEFAULT_PASS} -t test/topic -m \"Hello\""
    echo "  • mosquitto_sub -h localhost -p ${MQTT_PORT} -u ${DEFAULT_USER} -P ${DEFAULT_PASS} -t test/topic"
    
    # Get WSL2 IP for remote access
    if command -v hostname &> /dev/null; then
        WSL_IP=$(hostname -I | awk '{print $1}')
        if [ ! -z "$WSL_IP" ]; then
            echo
            echo "Remote Access (from Windows host):"
            echo "  • mosquitto_pub -h ${WSL_IP} -p ${MQTT_PORT} -u ${DEFAULT_USER} -P ${DEFAULT_PASS} -t test/topic -m \"Hello\""
        fi
    fi
    
    echo
}

generate_installation_log() {
    local log_file="/tmp/rabbitmq_mqtt_installation_$(date +%Y%m%d_%H%M%S).log"
    
    print_status "Generating comprehensive installation log..."
    
    {
        echo "=========================================="
        echo "RabbitMQ with MQTT Support - Installation Log"
        echo "Generated: $(date)"
        echo "=========================================="
        echo
        
        echo "=== CONFIGURATION ==="
        echo "Container Name: ${CONTAINER_NAME}"
        echo "Image: ${IMAGE_NAME}"
        echo "Volume: ${VOLUME_NAME}"
        echo "AMQP Port: ${AMQP_PORT}"
        echo "Management Port: ${MGMT_PORT}"
        echo "MQTT Port: ${MQTT_PORT}"
        echo "MQTT WebSocket Port: ${MQTT_WS_PORT}"
        echo "MQTT TLS Port: ${MQTT_TLS_PORT} (Enabled: ${ENABLE_MQTT_TLS})"
        echo "Default User: ${DEFAULT_USER}"
        echo "Default Password: ${DEFAULT_PASS}"
        echo
        
        echo "=== CONTAINER STATUS ==="
        if container_running; then
            echo "✅ Container is running"
            CONTAINER_ID=$(docker ps --filter "name=${CONTAINER_NAME}" --format "{{.ID}}")
            UPTIME=$(docker ps --filter "name=${CONTAINER_NAME}" --format "{{.Status}}")
            echo "Container ID: ${CONTAINER_ID}"
            echo "Uptime: ${UPTIME}"
        else
            echo "❌ Container is not running"
        fi
        echo
        
        echo "=== PORTS AND ACCESSIBILITY ==="
        # Check each port
        for port in ${AMQP_PORT} ${MGMT_PORT} ${MQTT_PORT} ${MQTT_WS_PORT}; do
            if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
                echo "✅ Port ${port} is listening"
            else
                echo "❌ Port ${port} is not accessible"
            fi
        done
        echo
        
        echo "=== MQTT PLUGIN STATUS ==="
        if container_running; then
            echo "Checking MQTT plugins..."
            docker exec ${CONTAINER_NAME} rabbitmq-plugins list 2>/dev/null | grep -E "(rabbitmq_mqtt|rabbitmq_web_mqtt)" || echo "❌ Could not check plugin status"
            echo
            
            echo "Enabled plugins:"
            docker exec ${CONTAINER_NAME} rabbitmq-plugins list -E 2>/dev/null || echo "❌ Could not list enabled plugins"
        else
            echo "❌ Cannot check plugins - container not running"
        fi
        echo
        
        echo "=== NETWORK INFORMATION ==="
        if command -v hostname &> /dev/null; then
            WSL_IP=$(hostname -I | awk '{print $1}')
            if [ ! -z "$WSL_IP" ]; then
                echo "WSL IP Address: ${WSL_IP}"
                echo "Remote MQTT Access: ${WSL_IP}:${MQTT_PORT}"
                echo "Remote Management: http://${WSL_IP}:${MGMT_PORT}"
            fi
        fi
        echo "Localhost MQTT: localhost:${MQTT_PORT}"
        echo "Localhost Management: http://localhost:${MGMT_PORT}"
        echo
        
        echo "=== TESTING COMMANDS ==="
        echo "MQTT Publish Test:"
        echo "mosquitto_pub -h localhost -p ${MQTT_PORT} -u ${DEFAULT_USER} -P ${DEFAULT_PASS} -t test/topic -m \"Hello RabbitMQ MQTT\""
        echo
        echo "MQTT Subscribe Test:"
        echo "mosquitto_sub -h localhost -p ${MQTT_PORT} -u ${DEFAULT_USER} -P ${DEFAULT_PASS} -t test/topic"
        echo
        echo "Script Management Commands:"
        echo "$0 status        # Check status"
        echo "$0 mqtt-test     # Test MQTT functionality"
        echo "$0 mqtt-status   # Detailed MQTT status"
        echo "$0 logs          # View logs"
        echo
        
        echo "=== VOLUME INFORMATION ==="
        if volume_exists; then
            echo "✅ Data volume exists: ${VOLUME_NAME}"
            docker volume inspect ${VOLUME_NAME} 2>/dev/null | grep -E "(Name|Mountpoint)" || echo "❌ Could not inspect volume"
        else
            echo "❌ Data volume missing: ${VOLUME_NAME}"
        fi
        echo
        
        echo "=== TROUBLESHOOTING ==="
        echo "If MQTT connection fails:"
        echo "1. Check if container is running: $0 status"
        echo "2. Check MQTT plugin status: $0 mqtt-status"
        echo "3. Enable MQTT plugins: $0 mqtt-enable"
        echo "4. Test MQTT connection: $0 mqtt-test"
        echo "5. Check container logs: $0 logs"
        echo
        echo "Common issues:"
        echo "- Plugin not enabled: Run '$0 mqtt-enable'"
        echo "- Port blocked: Check firewall settings"
        echo "- Authentication failed: Verify username/password"
        echo "- Container not ready: Wait 30 seconds after start"
        echo
        
        echo "=== INSTALLATION COMPLETED ==="
        echo "Timestamp: $(date)"
        echo "Log file: ${log_file}"
        echo "=========================================="
        
    } > "${log_file}"
    
    print_success "Installation log saved to: ${log_file}"
    echo
}

install_rabbitmq() {
    check_docker
    
    if container_exists; then
        print_warning "Container ${CONTAINER_NAME} already exists"
        if container_running; then
            print_status "Container is already running"
        else
            print_status "Container exists but is stopped. Use 'start' to run it"
        fi
        return 0
    fi
    
    print_status "Installing RabbitMQ..."
    
    # Create volume
    create_volume
    
    # Pull image
    print_status "Pulling ${IMAGE_NAME}..."
    docker pull ${IMAGE_NAME}
    
    # Run container
    print_status "Creating and starting RabbitMQ container with MQTT support..."
    
    # Build port mappings
    MQTT_PORTS="-p ${MQTT_PORT}:1883 -p ${MQTT_WS_PORT}:15675"
    if [ "$ENABLE_MQTT_TLS" = "true" ]; then
        MQTT_PORTS="$MQTT_PORTS -p ${MQTT_TLS_PORT}:8883"
    fi
    
    docker run -d \
        --name ${CONTAINER_NAME} \
        --hostname ${CONTAINER_NAME} \
        -p ${AMQP_PORT}:5672 \
        -p ${MGMT_PORT}:15672 \
        ${MQTT_PORTS} \
        -v ${VOLUME_NAME}:/var/lib/rabbitmq \
        -e RABBITMQ_DEFAULT_USER=${DEFAULT_USER} \
        -e RABBITMQ_DEFAULT_PASS=${DEFAULT_PASS} \
        --restart unless-stopped \
        ${IMAGE_NAME}
    
    if [ $? -eq 0 ]; then
        print_success "RabbitMQ installed and started successfully!"
        print_status "Waiting for RabbitMQ to be ready..."
        sleep 15
        
        # Enable MQTT plugins
        print_status "Enabling MQTT plugins..."
        enable_mqtt_plugin
        
        # Wait for MQTT plugins to be fully loaded
        print_status "Verifying MQTT plugin status..."
        sleep 5
        
        # Generate comprehensive installation log
        generate_installation_log
        
        show_installation_info
    else
        print_error "Failed to install RabbitMQ"
        exit 1
    fi
}

start_rabbitmq() {
    check_docker
    
    if ! container_exists; then
        print_error "Container ${CONTAINER_NAME} does not exist. Run 'install' first."
        exit 1
    fi
    
    if container_running; then
        print_warning "Container ${CONTAINER_NAME} is already running"
        return 0
    fi
    
    print_status "Starting RabbitMQ container..."
    docker start ${CONTAINER_NAME}
    
    if [ $? -eq 0 ]; then
        print_success "RabbitMQ started successfully!"
        sleep 5
        show_status
    else
        print_error "Failed to start RabbitMQ"
        exit 1
    fi
}

stop_rabbitmq() {
    check_docker
    
    if ! container_running; then
        print_warning "Container ${CONTAINER_NAME} is not running"
        return 0
    fi
    
    print_status "Stopping RabbitMQ container..."
    docker stop ${CONTAINER_NAME}
    
    if [ $? -eq 0 ]; then
        print_success "RabbitMQ stopped successfully!"
    else
        print_error "Failed to stop RabbitMQ"
        exit 1
    fi
}

restart_rabbitmq() {
    print_status "Restarting RabbitMQ..."
    stop_rabbitmq
    start_rabbitmq
}

show_status() {
    check_docker
    
    if ! container_exists; then
        print_error "Container ${CONTAINER_NAME} does not exist"
        return 1
    fi
    
    echo
    echo "=== RabbitMQ Status ==="
    
    if container_running; then
        print_success "RabbitMQ is running"
        
        # Get container info
        CONTAINER_ID=$(docker ps --filter "name=${CONTAINER_NAME}" --format "{{.ID}}")
        UPTIME=$(docker ps --filter "name=${CONTAINER_NAME}" --format "{{.Status}}")
        
        echo "Container ID: ${CONTAINER_ID}"
        echo "Status: ${UPTIME}"
        echo "AMQP Port: ${AMQP_PORT}"
        echo "Management UI: http://localhost:${MGMT_PORT}"
        echo "MQTT Port: ${MQTT_PORT}"
        echo "MQTT WebSocket: ${MQTT_WS_PORT}"
        if [ "$ENABLE_MQTT_TLS" = "true" ]; then
            echo "MQTT TLS Port: ${MQTT_TLS_PORT}"
        fi
        echo "Username: ${DEFAULT_USER}"
        echo "Password: ${DEFAULT_PASS}"
        
        # Check if management UI is accessible
        if command -v curl &> /dev/null; then
            if curl -s -o /dev/null -w "%{http_code}" http://localhost:${MGMT_PORT} | grep -q "200"; then
                print_success "Management UI is accessible"
            else
                print_warning "Management UI might not be ready yet"
            fi
        fi
        
        # Check MQTT plugin status
        echo
        if check_mqtt_plugin; then
            print_success "MQTT plugin is enabled and ready"
        else
            print_warning "MQTT plugin is not enabled. Run '$0 mqtt-enable' to enable it"
        fi
    else
        print_error "RabbitMQ is not running"
    fi
    echo
}

show_installation_info() {
    echo
    echo "=========================================="
    echo "     RabbitMQ Docker Installation Complete"
    echo "=========================================="
    echo
    print_success "RabbitMQ is now running in Docker!"
    echo
    echo "📋 Connection Information:"
    echo "   • Management UI: http://localhost:${MGMT_PORT}"
    echo "   • AMQP Connection: localhost:${AMQP_PORT}"
    echo "   • MQTT Connection: localhost:${MQTT_PORT}"
    echo "   • MQTT WebSocket: localhost:${MQTT_WS_PORT}"
    if [ "$ENABLE_MQTT_TLS" = "true" ]; then
        echo "   • MQTT TLS: localhost:${MQTT_TLS_PORT}"
    fi
    echo "   • Username: ${DEFAULT_USER}"
    echo "   • Password: ${DEFAULT_PASS}"
    echo
    echo "🔧 Management Commands:"
    echo "   • Start:       $0 start"
    echo "   • Stop:        $0 stop"
    echo "   • Restart:     $0 restart"
    echo "   • Status:      $0 status"
    echo "   • Logs:        $0 logs"
    echo "   • Remove:      $0 remove"
    echo "   • MQTT Test:   $0 mqtt-test"
    echo "   • MQTT Status: $0 mqtt-status"
    echo "   • MQTT Enable: $0 mqtt-enable"
    echo
    echo "📊 Quick Actions:"
    echo "   • View Management UI: Open http://localhost:${MGMT_PORT} in your browser"
    echo "   • Check Status: $0 status"
    echo "   • View Real-time Logs: $0 logs"
    echo "   • Test MQTT: $0 mqtt-test"
    echo "   • MQTT Status: $0 mqtt-status"
    echo
    echo "🔗 MQTT Examples:"
    echo "   • Publish: mosquitto_pub -h localhost -p ${MQTT_PORT} -u ${DEFAULT_USER} -P ${DEFAULT_PASS} -t test/topic -m \"Hello\""
    echo "   • Subscribe: mosquitto_sub -h localhost -p ${MQTT_PORT} -u ${DEFAULT_USER} -P ${DEFAULT_PASS} -t test/topic"
    echo
    
    # Get WSL2 IP for remote access
    if command -v hostname &> /dev/null; then
        WSL_IP=$(hostname -I | awk '{print $1}')
        if [ ! -z "$WSL_IP" ]; then
            echo "🌐 Remote Access (from Windows host):"
            echo "   • Management UI: http://${WSL_IP}:${MGMT_PORT}"
            echo "   • AMQP Connection: ${WSL_IP}:${AMQP_PORT}"
            echo "   • MQTT Connection: ${WSL_IP}:${MQTT_PORT}"
            echo "   • MQTT WebSocket: ${WSL_IP}:${MQTT_WS_PORT}"
            echo
        fi
    fi
    
    # Check if management UI is accessible
    print_status "Checking Management UI accessibility..."
    if command -v curl &> /dev/null; then
        sleep 5  # Give it a moment to fully start
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${MGMT_PORT} 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ]; then
            print_success "✅ Management UI is accessible at http://localhost:${MGMT_PORT}"
        else
            print_warning "⚠️  Management UI might not be ready yet. Please wait a moment and try again."
        fi
    else
        print_status "💡 Install curl to test Management UI accessibility automatically"
    fi
    
    echo
    echo "🐰 Happy messaging with RabbitMQ!"
    echo "=========================================="
}

show_logs() {
    check_docker
    
    if ! container_exists; then
        print_error "Container ${CONTAINER_NAME} does not exist"
        exit 1
    fi
    
    print_status "Showing RabbitMQ logs (Press Ctrl+C to exit)..."
    docker logs -f ${CONTAINER_NAME}
}

remove_rabbitmq() {
    check_docker
    
    if container_running; then
        print_status "Stopping running container..."
        stop_rabbitmq
    fi
    
    if container_exists; then
        print_status "Removing container ${CONTAINER_NAME}..."
        docker rm ${CONTAINER_NAME}
        print_success "Container removed"
    else
        print_warning "Container ${CONTAINER_NAME} does not exist"
    fi
    
    # Ask about volume removal
    echo
    read -p "Do you want to remove the data volume as well? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if volume_exists; then
            print_status "Removing volume ${VOLUME_NAME}..."
            docker volume rm ${VOLUME_NAME}
            print_success "Volume removed"
        fi
    else
        print_status "Volume ${VOLUME_NAME} preserved"
    fi
}

show_help() {
    echo "RabbitMQ Docker Manager"
    echo
    echo "Usage: $0 [COMMAND]"
    echo
    echo "Commands:"
    echo "  install     - Install and start RabbitMQ container with MQTT support"
    echo "  start       - Start existing RabbitMQ container"
    echo "  stop        - Stop running RabbitMQ container"
    echo "  restart     - Restart RabbitMQ container"
    echo "  status      - Show RabbitMQ status and connection info"
    echo "  logs        - Show RabbitMQ logs (follow mode)"
    echo "  remove      - Remove RabbitMQ container (and optionally volume)"
    echo "  mqtt-test   - Test MQTT connection and functionality"
    echo "  mqtt-status - Show detailed MQTT status and examples"
    echo "  mqtt-enable - Enable MQTT plugins (if not already enabled)"
    echo "  help        - Show this help message"
    echo
    echo "Configuration:"
    echo "  Container: ${CONTAINER_NAME}"
    echo "  Image: ${IMAGE_NAME}"
    echo "  AMQP Port: ${AMQP_PORT}"
    echo "  Management Port: ${MGMT_PORT}"
    echo "  MQTT Port: ${MQTT_PORT}"
    echo "  MQTT WebSocket Port: ${MQTT_WS_PORT}"
    if [ "$ENABLE_MQTT_TLS" = "true" ]; then
        echo "  MQTT TLS Port: ${MQTT_TLS_PORT}"
    fi
    echo "  Default User: ${DEFAULT_USER}"
    echo "  Default Password: ${DEFAULT_PASS}"
}

# Main script logic
case "${1:-}" in
    "install")
        install_rabbitmq
        ;;
    "start")
        start_rabbitmq
        ;;
    "stop")
        stop_rabbitmq
        ;;
    "restart")
        restart_rabbitmq
        ;;
    "status")
        show_status
        ;;
    "logs")
        show_logs
        ;;
    "remove")
        remove_rabbitmq
        ;;
    "mqtt-test")
        test_mqtt_connection
        ;;
    "mqtt-status")
        show_mqtt_status
        ;;
    "mqtt-enable")
        enable_mqtt_plugin
        ;;
    "help"|"--help"|"-h")
        show_help
        ;;
    "")
        echo "🐰 RabbitMQ Docker Manager"
        echo "=========================="
        echo
        if container_exists; then
            print_status "RabbitMQ container already exists"
            show_status
        else
            print_status "RabbitMQ is not installed yet"
            echo
            echo "To get started, run one of these commands:"
            echo "  $0 install   - Install and start RabbitMQ"
            echo "  $0 help      - Show all available commands"
            echo
            read -p "Would you like to install RabbitMQ now? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                install_rabbitmq
            else
                print_status "You can install RabbitMQ later by running: $0 install"
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