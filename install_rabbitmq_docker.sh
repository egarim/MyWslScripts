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
    print_status "Creating and starting RabbitMQ container..."
    docker run -d \
        --name ${CONTAINER_NAME} \
        --hostname ${CONTAINER_NAME} \
        -p ${AMQP_PORT}:5672 \
        -p ${MGMT_PORT}:15672 \
        -v ${VOLUME_NAME}:/var/lib/rabbitmq \
        -e RABBITMQ_DEFAULT_USER=${DEFAULT_USER} \
        -e RABBITMQ_DEFAULT_PASS=${DEFAULT_PASS} \
        --restart unless-stopped \
        ${IMAGE_NAME}
    
    if [ $? -eq 0 ]; then
        print_success "RabbitMQ installed and started successfully!"
        print_status "Waiting for RabbitMQ to be ready..."
        sleep 15
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
    echo "   • Username: ${DEFAULT_USER}"
    echo "   • Password: ${DEFAULT_PASS}"
    echo
    echo "🔧 Management Commands:"
    echo "   • Start:    $0 start"
    echo "   • Stop:     $0 stop"
    echo "   • Restart:  $0 restart"
    echo "   • Status:   $0 status"
    echo "   • Logs:     $0 logs"
    echo "   • Remove:   $0 remove"
    echo
    echo "📊 Quick Actions:"
    echo "   • View Management UI: Open http://localhost:${MGMT_PORT} in your browser"
    echo "   • Check Status: $0 status"
    echo "   • View Real-time Logs: $0 logs"
    echo
    
    # Get WSL2 IP for remote access
    if command -v hostname &> /dev/null; then
        WSL_IP=$(hostname -I | awk '{print $1}')
        if [ ! -z "$WSL_IP" ]; then
            echo "🌐 Remote Access (from Windows host):"
            echo "   • Management UI: http://${WSL_IP}:${MGMT_PORT}"
            echo "   • AMQP Connection: ${WSL_IP}:${AMQP_PORT}"
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
    echo "  install   - Install and start RabbitMQ container"
    echo "  start     - Start existing RabbitMQ container"
    echo "  stop      - Stop running RabbitMQ container"
    echo "  restart   - Restart RabbitMQ container"
    echo "  status    - Show RabbitMQ status and connection info"
    echo "  logs      - Show RabbitMQ logs (follow mode)"
    echo "  remove    - Remove RabbitMQ container (and optionally volume)"
    echo "  help      - Show this help message"
    echo
    echo "Configuration:"
    echo "  Container: ${CONTAINER_NAME}"
    echo "  Image: ${IMAGE_NAME}"
    echo "  AMQP Port: ${AMQP_PORT}"
    echo "  Management Port: ${MGMT_PORT}"
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