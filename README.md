# MyWslScripts

## install_keycloak.sh

This script installs and configures Keycloak with PostgreSQL integration on WSL2.

### Usage

#### Option 1: Download and Run Locally

1. Save the script to a file (e.g., `install_keycloak.sh`)
2. Make it executable: `chmod +x install_keycloak.sh`
3. Run the script: `./install_keycloak.sh`

#### Option 2: Run Directly from Remote URL

You can run the script directly from your GitHub repository using `curl` and `bash -c`:

```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/egarim/MyWslScripts/refs/heads/master/install_keycloak.sh)"
```

This will download and execute the latest version of `install_keycloak.sh` from your repository.

## install_seq.sh

This script installs and configures Seq Log Server with Docker integration on WSL2.

### Usage

#### Option 1: Download and Run Locally

1. Save the script to a file (e.g., `install_seq.sh`)
2. Make it executable: `chmod +x install_seq.sh`
3. Run the script: `./install_seq.sh`

#### Option 2: Run Directly from Remote URL

You can run the script directly from your GitHub repository using `curl` and `bash -c`:

```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/egarim/MyWslScripts/refs/heads/master/ProductionLinux/SeqSerilogServer/install_seq.sh)"
```

This will download and execute the latest version of `install_seq.sh` from your repository.

## postgres-remote-access.sh

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

This script provides a comprehensive management interface for running RabbitMQ in Docker on WSL2. It handles installation, configuration, and management of a RabbitMQ instance with the management UI enabled. The script features an interactive installation process and provides detailed connection information upon completion.

### Prerequisites

- Docker must be installed and running
- WSL2 environment

### Default Configuration

- Container Name: rabbitmq
- Image: rabbitmq:3-management
- AMQP Port: 5672
- Management UI Port: 15672
- Default Username: admin
- Default Password: password
- Data Volume: rabbitmq_data

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

# Install and start RabbitMQ directly
./install_rabbitmq_docker.sh install

# Check status
./install_rabbitmq_docker.sh status

# View logs
./install_rabbitmq_docker.sh logs

# Stop RabbitMQ
./install_rabbitmq_docker.sh stop

# Start RabbitMQ
./install_rabbitmq_docker.sh start

# Restart RabbitMQ
./install_rabbitmq_docker.sh restart

# Remove everything
./install_rabbitmq_docker.sh remove
```

### What the Script Does

Upon successful installation, the script will display:

- Complete connection information (local and remote access)
- Management commands for controlling the container
- Direct links to the Management UI
- WSL2 IP address for remote access from Windows host
- Real-time accessibility check of the Management UI
- Quick action suggestions

### Available Commands

- `install` - Installs and starts RabbitMQ container with persistence
- `start` - Starts an existing RabbitMQ container
- `stop` - Stops the running RabbitMQ container
- `restart` - Restarts the RabbitMQ container
- `status` - Shows current status, ports, and connection details
- `logs` - Displays container logs in follow mode
- `remove` - Removes the container and optionally the data volume
- `help` - Shows usage information and configuration details

### Features

- **Interactive Installation**: User-friendly prompts for first-time setup
- **Comprehensive Information Display**: Shows all connection details and management commands after installation
- **Remote Access Support**: Provides WSL2 IP for access from Windows host
- **Real-time Health Checks**: Automatically verifies Management UI accessibility
- **Persistent Data Storage**: Uses Docker volumes for data persistence
- **Management UI Interface**: Enabled by default with admin credentials
- **Automatic Container Restart**: Container restarts on failure
- **Colored Status Output**: Better readability with color-coded messages
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
- Configuration settings

When removing the container using the `remove` command, you'll be given the option to preserve or delete this data.

### Security Notes

- Default credentials (admin/password) should be changed in production
- Management UI is exposed on all interfaces
- Consider configuring firewall rules for port access
- The container restarts automatically unless explicitly stopped
- Use strong passwords and proper authentication in production environments