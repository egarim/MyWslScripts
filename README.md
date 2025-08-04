# MyWslScripts

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

1. Save the script to a file (e.g., `install_mailhog.sh`)
2. Make it executable: `chmod +x install_mailhog.sh`
3. Run the script: `./install_mailhog.sh`

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

1. Save the script to a file (e.g., `install_postgres.sh`)
2. Make it executable: `chmod +x install_postgres.sh`
3. Run the script: `./install_postgres.sh`

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