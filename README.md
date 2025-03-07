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