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