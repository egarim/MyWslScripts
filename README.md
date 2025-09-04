# MyWslScripts

## Quick Reference

| Script | Category | Purpose | Quick Install |
|--------|----------|---------|---------------|
| `install_rabbitmq_docker.sh` | Messaging | RabbitMQ with MQTT support | [📖 Docs](#install_rabbitmq_dockersh) |
| `install_mosquitto_clients.sh` | MQTT Tools | Universal MQTT testing tools | [📖 Docs](#install_mosquitto_clientssh) |
| `install_keycloakp.sh` | Production | Keycloak with PostgreSQL & SSL | [📖 Docs](#install_keycloakpsh-production-keycloak) |
| `install_seq.sh` | Production | Seq Log Server with Docker | [📖 Docs](#install_seqsh-production-seq-log-server) |
| `postgres-remote-access.sh` | Database | PostgreSQL remote configuration | [📖 Docs](#postgres-remote-accesssh) |

## Production-Ready Scripts

The following scripts are production-ready with enhanced security, monitoring, and enterprise features:

### install_keycloakp.sh (Production Keycloak)

This script installs and configures Keycloak Ultimate Production Edition with PostgreSQL integration, SSL support, Apache reverse proxy, and advanced security features on WSL2.

#### Features
- Apache reverse proxy with SSL/TLS support
- PostgreSQL database integration  
- Advanced security headers and CSP configuration
- Fail2ban integration for brute force protection
- UFW firewall configuration
- Health monitoring and diagnostics
- Let's Encrypt SSL certificate automation

#### Usage

##### Option 1: Download and Run Locally

1. Save the script to a file (e.g., `install_keycloakp.sh`)
2. Make it executable: `chmod +x install_keycloakp.sh`
3. Run the script: `./install_keycloakp.sh`

##### Option 2: Run Directly from Remote URL

```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/egarim/MyWslScripts/refs/heads/master/ProductionLinux/keycloak/install_keycloakp.sh)"
```

### install_seq.sh (Production Seq Log Server)

This script installs and configures Seq Log Server Ultimate with Docker integration, Apache reverse proxy, and production-grade features on WSL2.

#### Features
- Docker-based Seq deployment with persistent storage
- Apache reverse proxy configuration
- UFW firewall setup
- Fail2ban integration
- SSL/TLS support with Let's Encrypt
- Health monitoring and diagnostics
- TCP ingestion configuration

#### Usage

##### Option 1: Download and Run Locally

1. Save the script to a file (e.g., `install_seq.sh`)
2. Make it executable: `chmod +x install_seq.sh`
3. Run the script: `./install_seq.sh`

##### Option 2: Run Directly from Remote URL

```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/egarim/MyWslScripts/refs/heads/master/ProductionLinux/SeqSerilogServer/install_seq.sh)"
```

### fix_seq.sh (Seq Container Fix)

A quick utility script to recreate the Seq container with proper configuration.

#### Usage

##### Option 1: Download and Run Locally

1. Save the script to a file (e.g., `fix_seq.sh`)
2. Make it executable: `chmod +x fix_seq.sh`
3. Edit the script to set your hostname and password
4. Run the script: `./fix_seq.sh`

##### Option 2: Run Directly from Remote URL

```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/egarim/MyWslScripts/refs/heads/master/ProductionLinux/SeqSerilogServer/fix_seq.sh)"
```

### install_webmin.sh (Production Webmin Server)

This script installs and configures Webmin Ultimate with Apache reverse proxy, SSL support, and production-grade security features on WSL2.

#### Features
- Apache reverse proxy with SSL/TLS support
- Let's Encrypt SSL certificate automation
- UFW firewall configuration
- Secure backend binding (localhost only)
- Cookie and redirect handling for proxy setup
- Self-signed certificate acceptance for backend
- Health monitoring and diagnostics

#### Usage

##### Option 1: Download and Run Locally

1. Save the script to a file (e.g., `install_webmin.sh`)
2. Make it executable: `chmod +x install_webmin.sh`
3. Run the script: `./install_webmin.sh`

##### Option 2: Run Directly from Remote URL

```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/egarim/MyWslScripts/refs/heads/master/ProductionLinux/Webmin/install_webmin.sh)"
```

### all_in_one.sh (Comprehensive Production Suite)

This script is a comprehensive merge installer that combines Keycloak and Seq installations into a single guided setup process, perfect for deploying a complete identity and logging infrastructure.

#### Features
- **Unified Installation**: Installs both Keycloak (native) and Seq (Docker) in one run
- **Consolidated Configuration**: Single prompt session for all services
- **Shared Dependencies**: Installs common components once (Apache, PostgreSQL, Docker)
- **Complete Security Setup**: UFW firewall, fail2ban, SSL/TLS with Let's Encrypt
- **Production Logging**: Comprehensive setup log with credentials (for secure deletion)
- **Diagnostic Tools**: Individual diagnostic helpers for each service
- **Idempotent Design**: Safe to re-run, handles existing installations gracefully

#### Components Installed
- **Keycloak Ultimate Production Edition** with PostgreSQL backend
- **Seq Log Server** with Docker deployment
- **Apache Reverse Proxy** with SSL termination
- **Security Stack**: UFW firewall + fail2ban protection
- **Monitoring**: Health checks and diagnostic scripts

#### Usage

##### Option 1: Download and Run Locally

1. Save the script to a file (e.g., `all_in_one.sh`)
2. Make it executable: `chmod +x all_in_one.sh`
3. Run the script: `./all_in_one.sh`

##### Option 2: Run Directly from Remote URL

```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/egarim/MyWslScripts/refs/heads/master/ProductionLinux/AllInOne/all_in_one.sh)"
```

#### What You Get
- **Keycloak**: Full identity and access management server
- **Seq**: Centralized structured logging server
- **Unified Access**: Both services behind Apache with optional SSL
- **Security**: Production-grade firewall and intrusion detection
- **Diagnostics**: `/root/keycloak-diagnostic.sh` and `/root/seq-diagnostic.sh`
- **Setup Log**: `/root/setup.log` with all credentials (secure deletion recommended)

#### Post-Installation
- Access Keycloak: `https://your-auth-domain/admin/`
- Access Seq: `https://your-logs-domain/`
- Review setup log: `cat /root/setup.log`
- Secure cleanup: `shred -u /root/setup.log`

### testkeycloak_api.ps1 (Keycloak API Test)

A PowerShell script for testing Keycloak installation and API functionality.

#### Features
- Tests OpenID discovery endpoint
- Validates token endpoint functionality
- Tests admin REST API access
- Interactive prompts with defaults

#### Usage

1. Download the script: `testkeycloak_api.ps1`
2. Run in PowerShell: `.\testkeycloak_api.ps1`

## Development Scripts

The following scripts are for development and testing purposes:

### install_keycloak.sh

### install_keycloak.sh (Development)

This script installs and configures Keycloak with PostgreSQL integration on WSL2 for development purposes.

#### Usage

##### Option 1: Download and Run Locally

1. Save the script to a file (e.g., `install_keycloak.sh`)
2. Make it executable: `chmod +x install_keycloak.sh`
3. Run the script: `./install_keycloak.sh`

##### Option 2: Run Directly from Remote URL

```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/egarim/MyWslScripts/refs/heads/master/install_keycloak.sh)"
```

## General Purpose Scripts

### postgres-remote-access.sh

This script will configure your PostgreSQL server to accept remote connections. Here's how to use it:

### Usage

1. Save the script to a file (e.g., `postgres-remote-access.sh`)
2. Make it executable: `chmod +x postgres-remote-access.sh`
3. Run it with sudo: `sudo ./postgres-remote-access.sh your_secure_password` (Replace `your_secure_password` with an actual secure password)

### What the Script Does

The script performs these important tasks:

- Identifies your PostgreSQL version
- Backs up your configuration files
- Configures PostgreSQL to listen on all network interfaces
- Modifies the `pg_hba.conf` file to allow remote connections
- Opens the PostgreSQL port (5432) in the firewall if UFW is active
- Sets a password for the postgres user if provided
- Restarts the PostgreSQL service

### Connecting to PostgreSQL

After running the script, you'll be able to connect to your PostgreSQL server from remote machines using:

```
psql -h your_server_ip -U postgres -p 5432
```

### Security Considerations

For security reasons, consider restricting access to specific IP addresses in a production environment by modifying the `pg_hba.conf` file further.

### install_mosquitto_clients.sh

This script provides a comprehensive installer for mosquitto MQTT client tools that work with any MQTT broker. It's a utility script that installs `mosquitto_pub` and `mosquitto_sub` - essential tools for MQTT testing and development.

**Quick Install:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/egarim/MyWslScripts/refs/heads/master/install_mosquitto_clients.sh)"
```

**Key Features:**
- Universal MQTT client tools for any broker (RabbitMQ, Mosquitto, HiveMQ, AWS IoT, etc.)
- Auto-detects Linux distribution and package manager
- Interactive installation with comprehensive testing examples
- Works perfectly in WSL2 environment
- Essential for MQTT development and troubleshooting

**Usage Examples After Installation:**
```bash
# Test any MQTT broker
mosquitto_pub -h localhost -p 1883 -u admin -P password -t test/topic -m "Hello"
mosquitto_sub -h localhost -p 1883 -u admin -P password -t test/topic
```

See the full documentation below for detailed installation and usage instructions.

## install_ipfsnode.sh

This script installs and configures an IPFS (InterPlanetary File System) node on WSL2. It provides a customizable setup with configurable ports.

### Usage

1. Save the script to a file (e.g., `install_ipfsnode.sh`)
2. Make it executable: `chmod +x install_ipfsnode.sh`
3. Run the script: `./install_ipfsnode.sh`

### What the Script Does

The script performs these tasks:

- Detects system architecture and installs the appropriate IPFS version
- Initializes IPFS repository
- Configures custom ports for API, Gateway, and Swarm services
- Creates and enables a systemd service for IPFS
- Optimizes IPFS configuration for WSL2 environment
- Provides an interactive setup for port configuration

### Default Ports

- API Port: 5001 (Web UI and API calls)
- Gateway Port: 8080 (HTTP access to IPFS content)
- Swarm Port: 4001 (P2P connections)

### Managing IPFS Service

After installation, you can manage the IPFS service using these commands:

```bash
sudo systemctl start ipfs    # Start the service
sudo systemctl stop ipfs     # Stop the service
sudo systemctl status ipfs   # Check service status
journalctl -u ipfs -f       # View service logs
```

### Accessing IPFS

Once running, you can access IPFS through:

- Web UI: `http://localhost:5001/webui`
- Gateway: `http://localhost:8080`
- API: `http://localhost:5001`

### Basic IPFS Commands

```bash
ipfs add <filename>     # Add a file to IPFS
ipfs get <hash>        # Download a file from IPFS
ipfs cat <hash>        # View file contents
ipfs ls <hash>         # List directory contents
```

### Security Considerations

- The script configures IPFS to listen on all network interfaces
- Consider configuring firewall rules to restrict access to IPFS ports
- In production environments, configure specific allowed IP addresses
- Regularly update IPFS to the latest version for security patches

## install_mailhog.sh

This script installs and configures MailHog, a simple SMTP testing server with a web interface that captures and displays emails for development purposes.


### Usage

#### Option 1: Download and Run Locally

1. Save the script to a file (e.g., `install_mailhog.sh`)
2. Make it executable: `chmod +x install_mailhog.sh`
3. Run the script: `./install_mailhog.sh`

#### Option 2: Run Directly from Remote URL

You can run the script directly from your GitHub repository using `curl` and `bash -c`:

```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/egarim/MyWslScripts/refs/heads/master/install_mailhog.sh)"
```

This will download and execute the latest version of `install_mailhog.sh` from your repository.

### What the Script Does

The script performs these tasks:

- Checks for existing MailHog installation and offers reinstallation option
- Installs Go if not already present (required for MailHog)
- Installs MailHog from source
- Configures custom ports for SMTP and Web Interface
- Creates a convenient startup script
- Optionally creates and enables a systemd service
- Saves all configuration details to a reference file

### Default Ports

- SMTP Port: 1025 (For sending emails)
- Web Interface Port: 8025 (For viewing captured emails)

### Configuration Options

During installation, you can customize:
- Installation directory (default: ~/go/bin)
- SMTP port
- Web interface port
- Auto-start option
- Systemd service creation

### Managing MailHog

The script creates two ways to run MailHog:

1. Using the startup script:
```bash
~/start-mailhog.sh    # Start MailHog
pkill MailHog         # Stop MailHog
```

2. Using systemd service (if enabled during installation):
```bash
sudo systemctl start mailhog    # Start the service
sudo systemctl stop mailhog     # Stop the service
sudo systemctl status mailhog   # Check service status
sudo systemctl enable mailhog   # Enable on boot
sudo systemctl disable mailhog  # Disable on boot
```

### Accessing MailHog

Once running, you can access MailHog through:
- Web Interface: `http://localhost:8025` (or custom port if configured)
- SMTP Server: `localhost:1025` (or custom port if configured)

### Installation Details

After installation, a detailed configuration file is created at `~/mailhog_details.txt` containing:
- Installation directory
- Port configurations
- Service management commands
- SMTP settings for applications
- Web interface access URL
- WSL2 IP address information

### Security Considerations

- MailHog is designed for development and testing purposes only
- The SMTP server does not require authentication
- Consider firewall rules if exposing ports to external networks
- Not recommended for production environments

## install_postgres.sh

This script installs and configures PostgreSQL with TimescaleDB and pgvector extensions on WSL2. It provides a complete setup with all necessary components and extensions.


### Usage

#### Option 1: Download and Run Locally

1. Save the script to a file (e.g., `install_postgres.sh`)
2. Make it executable: `chmod +x install_postgres.sh`
3. Run the script: `./install_postgres.sh`

#### Option 2: Run Directly from Remote URL

You can run the script directly from your GitHub repository using `curl` and `bash -c`:

```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/egarim/MyWslScripts/refs/heads/master/install_postgres.sh)"
```

This will download and execute the latest version of `install_postgres.sh` from your repository.

### What the Script Does

The script performs these tasks:

- Updates system packages and installs required dependencies
- Installs PostgreSQL 17 with development packages
- Installs and configures TimescaleDB extension
- Compiles and installs pgvector extension from source
- Configures PostgreSQL for optimal performance using timescaledb-tune
- Sets up a default password for the postgres user
- Enables TimescaleDB and pgvector extensions in template1 database
- Saves all installation details to postgres_details.txt

### Default Configuration

- PostgreSQL Version: 17
- Default User: postgres
- Default Password: 1234567890
- Default Port: 5432
- Installed Extensions:
  - TimescaleDB
  - pgvector (for vector similarity search)

### Post-Installation Details

After installation, you can find all configuration details in `postgres_details.txt`, which includes:
- Installation date
- PostgreSQL version
- Installed extensions and their versions
- Database connection details
- Port configuration

### Managing PostgreSQL

You can manage the PostgreSQL service using these commands:

```bash
sudo systemctl start postgresql    # Start the service
sudo systemctl stop postgresql     # Stop the service
sudo systemctl status postgresql   # Check service status
sudo systemctl restart postgresql  # Restart the service
```

### Connecting to PostgreSQL

You can connect to your PostgreSQL server using:

```bash
psql -U postgres -h localhost
```

### Security Considerations

- The default password (1234567890) should be changed in production environments
- Consider configuring pg_hba.conf for stricter access control
- Regularly update PostgreSQL and extensions for security patches
- Use the postgres-remote-access.sh script if you need to configure remote access

## install_docker.sh
This script installs Docker CE (Community Edition) on WSL2, providing a complete setup compatible with both ARM64 and x64 architectures.

### Usage

#### Option 1: Download and Run Locally

1. Save the script to a file (e.g., `install_docker.sh`)
2. Make it executable: `chmod +x install_docker.sh`
3. Run the script: `./install_docker.sh`

#### Option 2: Run Directly from Remote URL

You can run the script directly from your GitHub repository using `curl` and `bash -c`:

```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/egarim/MyWslScripts/refs/heads/master/install_docker.sh)"
```

This will download and execute the latest version of `install_docker.sh` from your repository.

This script installs Docker CE (Community Edition) on WSL2, providing a complete setup compatible with both ARM64 and x64 architectures.

### Usage

1. Save the script to a file (e.g., `install_docker.sh`)
2. Make it executable: `chmod +x install_docker.sh`
3. Run the script: `./install_docker.sh`

### What the Script Does

The script performs these tasks in order:

- Verifies the WSL2 environment
- Updates system packages and installs prerequisites
- Adds Docker's official GPG key and repository
- Installs Docker CE, CLI tools, and containerd
- Starts the Docker service
- Adds the current user to the docker group
- Verifies the installation by running a test container
- Offers to configure Docker auto-start on WSL2 launch

### Post-Installation Features

- Automatically detects and configures for your system architecture
- Supports both bash and zsh shell configurations
- Adds Docker service auto-start capability (optional)
- Provides immediate verification of the installation

### Managing Docker

After installation, you can use these commands to manage Docker:

```bash
sudo service docker start     # Start Docker service
sudo service docker stop      # Stop Docker service
sudo service docker status    # Check Docker service status
docker ps                     # List running containers
docker images                # List available images
```

### Important Notes

- WSL2 is required for Docker to function properly
- You may need to restart your WSL2 session after installation for group changes to take effect
- Docker runs in command-line mode (no Desktop UI) in WSL2
- The script automatically handles architecture-specific requirements

### Security Considerations

- Only use the official Docker repository (handled automatically by the script)
- The script adds your user to the docker group for non-root access
- Regular updates are recommended for security patches
- Review container permissions and network exposure when deploying containers

### Troubleshooting

If you encounter issues after installation:
1. Verify WSL2 is running: `wsl --status`
2. Ensure Docker service is running: `sudo service docker status`
3. Try restarting your WSL2 session
4. Verify group membership: `groups $USER`

## install_rabbitmq_docker.sh

This script provides a comprehensive management interface for running RabbitMQ in Docker on WSL2 with full MQTT support. It handles installation, configuration, and management of a RabbitMQ instance with both AMQP and MQTT protocols enabled, including the management UI. The script features an interactive installation process and provides detailed connection information upon completion.

### Prerequisites

- Docker must be installed and running
- WSL2 environment
- Optional: mosquitto-clients for MQTT testing (auto-installed by script)

### Default Configuration

- Container Name: rabbitmq
- Image: rabbitmq:3-management
- AMQP Port: 5672
- Management UI Port: 15672
- **MQTT Port: 1883** (Non-TLS)
- **MQTT WebSocket Port: 15675**
- **MQTT TLS Port: 8883** (Optional, disabled by default)
- Default Username: admin
- Default Password: password
- Data Volume: rabbitmq_data
- **MQTT Plugins: rabbitmq_mqtt, rabbitmq_web_mqtt (auto-enabled)**

### Usage

#### Option 1: Download and Run Locally

1. Save the script to a file (e.g., `install_rabbitmq_docker.sh`)
2. Make it executable: `chmod +x install_rabbitmq_docker.sh`
3. Run the script: `./install_rabbitmq_docker.sh [command]`

#### Option 2: Run Directly from Remote URL

You can run the script directly from your GitHub repository using `curl` and `bash -c`:

```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/egarim/MyWslScripts/refs/heads/master/install_rabbitmq_docker.sh)"
```

This will download and execute the latest version of `install_rabbitmq_docker.sh` from your repository.

#### Option 3: Interactive Installation

Simply run the script without any commands for an interactive installation:

```bash
./install_rabbitmq_docker.sh
```

This will check if RabbitMQ is already installed and prompt you to install it if it's not present.

### Usage Examples

First, make the script executable:
```bash
chmod +x install_rabbitmq_docker.sh
```

Then you can use any of these commands:
```bash
# Interactive mode (recommended for first-time users)
./install_rabbitmq_docker.sh

# Install and start RabbitMQ with MQTT support directly
./install_rabbitmq_docker.sh install

# Check status (includes MQTT plugin status)
./install_rabbitmq_docker.sh status

# View logs
./install_rabbitmq_docker.sh logs

# Stop RabbitMQ
./install_rabbitmq_docker.sh stop

# Start RabbitMQ
./install_rabbitmq_docker.sh start

# Restart RabbitMQ
./install_rabbitmq_docker.sh restart

# MQTT-specific commands
./install_rabbitmq_docker.sh mqtt-test     # Test MQTT connectivity
./install_rabbitmq_docker.sh mqtt-status   # Detailed MQTT status
./install_rabbitmq_docker.sh mqtt-enable   # Enable MQTT plugins

# Remove everything
./install_rabbitmq_docker.sh remove
```

### MQTT Testing Examples

After installation, you can test MQTT functionality:

```bash
# Publish a message to MQTT topic
mosquitto_pub -h localhost -p 1883 -u admin -P password -t test/topic -m "Hello RabbitMQ MQTT"

# Subscribe to MQTT topic
mosquitto_sub -h localhost -p 1883 -u admin -P password -t test/topic

# Test from Windows host (replace WSL_IP with your WSL IP)
mosquitto_pub -h WSL_IP -p 1883 -u admin -P password -t test/topic -m "Hello from Windows"
```

### What the Script Does

Upon successful installation, the script will display:

- Complete connection information (AMQP, MQTT, and Management UI)
- **MQTT connection examples and testing commands**
- Management commands for controlling the container
- Direct links to the Management UI
- **MQTT plugin status and verification**
- WSL2 IP address for remote access from Windows host
- Real-time accessibility check of the Management UI and MQTT ports
- **Comprehensive installation log with troubleshooting information**
- Quick action suggestions

**New MQTT Features:**
- Automatic MQTT plugin enablement (rabbitmq_mqtt, rabbitmq_web_mqtt)
- MQTT connectivity testing with mosquitto-clients
- MQTT-specific status monitoring
- WebSocket MQTT support for web applications
- Detailed MQTT troubleshooting guide

### Available Commands

**Core Commands:**
- `install` - Installs and starts RabbitMQ container with MQTT support and persistence
- `start` - Starts an existing RabbitMQ container
- `stop` - Stops the running RabbitMQ container
- `restart` - Restarts the RabbitMQ container
- `status` - Shows current status, ports, MQTT plugin status, and connection details
- `logs` - Displays container logs in follow mode
- `remove` - Removes the container and optionally the data volume
- `help` - Shows usage information and configuration details

**MQTT-Specific Commands:**
- `mqtt-test` - Performs comprehensive MQTT connectivity testing (publish/subscribe)
- `mqtt-status` - Shows detailed MQTT status, plugin information, and connection examples
- `mqtt-enable` - Manually enables MQTT plugins (usually not needed as they're auto-enabled)

### Features

**Core Features:**
- **Interactive Installation**: User-friendly prompts for first-time setup
- **Comprehensive Information Display**: Shows all connection details and management commands after installation
- **Remote Access Support**: Provides WSL2 IP for access from Windows host
- **Real-time Health Checks**: Automatically verifies Management UI and MQTT accessibility
- **Persistent Data Storage**: Uses Docker volumes for data persistence
- **Management UI Interface**: Enabled by default with admin credentials
- **Automatic Container Restart**: Container restarts on failure
- **Colored Status Output**: Better readability with color-coded messages

**MQTT Features:**
- **Full MQTT Protocol Support**: MQTT 3.1.1 and 5.0 compatibility
- **WebSocket MQTT**: MQTT over WebSockets for web applications (port 15675)
- **Automatic Plugin Management**: Auto-enables rabbitmq_mqtt and rabbitmq_web_mqtt plugins
- **MQTT Testing Suite**: Built-in publish/subscribe testing with mosquitto-clients
- **TLS MQTT Support**: Optional secure MQTT connections (port 8883)
- **Comprehensive Logging**: Detailed installation and troubleshooting logs
- **MQTT Status Monitoring**: Real-time MQTT plugin and connectivity status
- **Cross-Platform Compatibility**: Works from WSL, Windows, and other MQTT clients
- **Volume Preservation**: Option to preserve or delete data during removal

### Accessing RabbitMQ

After installation, you can access:

- **Management UI**: http://localhost:15672
  - Username: admin
  - Password: password
- **AMQP Connection**: localhost:5672
- **Remote Access** (from Windows host): http://[WSL2-IP]:15672

### Post-Installation Information

The script provides detailed information after installation including:

- Management UI URL and credentials
- AMQP connection details
- Container management commands
- WSL2 IP address for remote access
- Quick action suggestions
- Real-time accessibility status

### Data Persistence

The script creates a Docker volume named `rabbitmq_data` to persist:
- Queue definitions
- Messages
- User accounts
- Virtual hosts

## install_mosquitto_clients.sh

This script provides a comprehensive installer for mosquitto MQTT client tools (`mosquitto_pub` and `mosquitto_sub`) that work with any MQTT broker. These are universal MQTT testing tools essential for MQTT development and troubleshooting, compatible with RabbitMQ, Eclipse Mosquitto, HiveMQ, AWS IoT Core, and any MQTT-compliant broker.

### Prerequisites

- Linux environment (WSL2, Ubuntu, CentOS, Fedora, Alpine, Arch, openSUSE)
- Package manager (apt, yum, dnf, apk, pacman, zypper)
- Internet connection for package installation

### What are mosquitto-clients?

**mosquitto-clients** is a package that provides two essential command-line MQTT tools:

- **mosquitto_pub**: Command-line MQTT publisher for sending messages to topics
- **mosquitto_sub**: Command-line MQTT subscriber for receiving messages from topics

**Important Note**: These are client tools that work with ANY MQTT broker, not just the Eclipse Mosquitto broker. They're the industry standard for MQTT testing regardless of which broker you're using.

### Default Installation

The script automatically detects your Linux distribution and installs the appropriate package:

- **Debian/Ubuntu**: `mosquitto-clients` package via apt-get
- **RHEL/CentOS/Fedora**: `mosquitto` package via yum/dnf
- **Alpine**: `mosquitto-clients` package via apk
- **Arch**: `mosquitto` package via pacman
- **openSUSE**: `mosquitto` package via zypper

### Usage

#### Option 1: Download and Run Locally

1. Save the script to a file (e.g., `install_mosquitto_clients.sh`)
2. Make it executable: `chmod +x install_mosquitto_clients.sh`
3. Run the script: `./install_mosquitto_clients.sh [command]`

#### Option 2: Run Directly from Remote URL

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/egarim/MyWslScripts/refs/heads/master/install_mosquitto_clients.sh)"
```

#### Option 3: Interactive Installation

Simply run the script without any commands for an interactive installation:

```bash
./install_mosquitto_clients.sh
```

This will check if mosquitto-clients are already installed and prompt you to install them if they're not present.

### Usage Examples

First, make the script executable:
```bash
chmod +x install_mosquitto_clients.sh
```

Then you can use any of these commands:
```bash
# Interactive mode (recommended for first-time users)
./install_mosquitto_clients.sh

# Install mosquitto-clients directly
./install_mosquitto_clients.sh install

# Test installation and show usage examples
./install_mosquitto_clients.sh test

# Show help and usage information
./install_mosquitto_clients.sh help
```

### MQTT Testing Examples

After installation, you can test any MQTT broker:

```bash
# Basic publish/subscribe (no authentication)
mosquitto_pub -h localhost -p 1883 -t test/topic -m "Hello MQTT"
mosquitto_sub -h localhost -p 1883 -t test/topic

# With authentication (RabbitMQ, HiveMQ, etc.)
mosquitto_pub -h localhost -p 1883 -u admin -P password -t test/topic -m "Hello MQTT"
mosquitto_sub -h localhost -p 1883 -u admin -P password -t test/topic

# Remote broker testing
mosquitto_pub -h broker.example.com -p 1883 -u user -P pass -t sensors/temperature -m "22.5"
mosquitto_sub -h broker.example.com -p 1883 -u user -P pass -t sensors/+

# Advanced options
mosquitto_pub -h localhost -p 1883 -t test/topic -m "Hello" -q 1 -r  # QoS 1, retain
mosquitto_sub -h localhost -p 1883 -t test/topic -C 5              # Exit after 5 messages
```

### What the Script Does

Upon successful installation, the script will display:

- **Installation Status**: Confirms successful installation and tool availability
- **Version Information**: Shows installed version and tool locations
- **Usage Examples**: Comprehensive MQTT testing examples for various scenarios
- **Advanced Options**: QoS levels, retain messages, multiple topics, etc.
- **Comprehensive Logging**: Detailed installation log with troubleshooting information
- **Multi-Broker Compatibility**: Examples for different MQTT broker types

### Available Commands

- `install` - Installs mosquitto-clients package for your Linux distribution
- `test` - Tests if mosquitto-clients are installed and shows usage examples
- `help` - Shows detailed help, usage examples, and broker compatibility info

### Features

**Installation Features:**
- **Multi-Distribution Support**: Automatic detection of Linux distribution and package manager
- **Interactive Installation**: User-friendly prompts for first-time setup
- **Verification Testing**: Automatically verifies tools work after installation
- **Comprehensive Logging**: Detailed installation log with system information and troubleshooting
- **Error Handling**: Graceful handling of installation failures with manual instructions

**MQTT Testing Features:**
- **Universal Compatibility**: Works with any MQTT 3.1.1 or 5.0 compliant broker
- **Authentication Support**: Username/password authentication for secure brokers
- **QoS Levels**: Support for Quality of Service levels 0, 1, and 2
- **Message Retention**: Ability to publish retained messages
- **Topic Wildcards**: Support for + (single level) and # (multi-level) wildcards
- **Timeout Handling**: Built-in timeout support for automated testing
- **Multiple Output Formats**: Various output formats for integration with scripts

**Supported MQTT Brokers:**
- RabbitMQ (with MQTT plugin)
- Eclipse Mosquitto
- HiveMQ Community & Enterprise
- AWS IoT Core
- Azure IoT Hub
- Google Cloud IoT Core
- EMQ X (EMQX)
- VerneMQ
- Any MQTT 3.1.1/5.0 compliant broker

### Integration with Other Scripts

This script is designed to work seamlessly with other MQTT-related scripts in this repository:

- **RabbitMQ Script**: The `install_rabbitmq_docker.sh` script automatically calls this installer when needed
- **Standalone Use**: Can be used independently to test any MQTT broker
- **Automation Ready**: Perfect for CI/CD pipelines and automated testing

### Troubleshooting

The script includes comprehensive troubleshooting information:

- **Installation Issues**: Permission problems, package manager issues, network connectivity
- **Tool Accessibility**: PATH issues, terminal restart requirements
- **MQTT Connection Issues**: Authentication, network, broker configuration problems
- **Manual Installation**: Step-by-step instructions for unsupported distributions
- Configuration settings

When removing the container using the `remove` command, you'll be given the option to preserve or delete this data.

### Security Notes

- Default credentials (admin/password) should be changed in production
- Management UI is exposed on all interfaces
- Consider configuring firewall rules for port access
- The container restarts automatically unless explicitly stopped
- Use strong passwords and proper authentication in production environments