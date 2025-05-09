# Gitea IP-Based Installation

This package provides scripts for automating the installation of Gitea with HTTPS using Nginx as a reverse proxy, configured to use your server's IP address instead of a domain name.

## Advantages of IP-Based Setup

- **No DNS Configuration Required**: Works without domain names or host file modifications
- **Direct Access**: Accessible from any computer on the same network
- **Simplified Setup**: Avoids potential domain resolution issues
- **Easier Testing**: Ideal for development and testing environments

## Installation Script

The `install-gitea-ip.sh` script automates the complete setup process:

- Installs prerequisites (Docker, Docker Compose, OpenSSL)
- Creates the necessary directory structure
- Generates configuration files for Docker Compose and Nginx
- Sets up self-signed SSL certificates for your server's IP
- Starts the containers
- Configures firewall rules (if applicable)

### Usage

```bash
chmod +x install-gitea-ip.sh
./install-gitea-ip.sh [options]
```

#### Options

| Option           | Description                                                   |
| ---------------- | ------------------------------------------------------------- |
| `-p PASSWORD`    | Database and initial admin password (default: auto-generated) |
| `-i INSTALL_DIR` | Installation directory (default: /opt/gitea)                  |
| `-s SSH_PORT`    | SSH port for Git operations (default: 222)                    |
| `-I IP_ADDRESS`  | Server IP address (default: auto-detected)                    |
| `-h`             | Display help and exit                                         |

### Examples

#### Basic Installation with Auto-Detected IP

```bash
./install-gitea-ip.sh
```

This will:

- Detect your server's IP address automatically
- Set up Gitea with a self-signed certificate for that IP
- Auto-generate a secure database password
- Install to the default location (/opt/gitea)

#### Custom Installation

```bash
./install-gitea-ip.sh -p "SecurePassword123" -i /srv/gitea -s 2222 -I 192.168.1.100
```

This will:

- Use the specified password for the database
- Install to the custom directory `/srv/gitea`
- Configure SSH on port 2222
- Use the specified IP address rather than auto-detecting

## Uninstallation Script

The `uninstall-gitea-ip.sh` script removes a Gitea installation:

- Stops and removes all containers
- Optionally removes data volumes
- Removes firewall rules
- Optionally removes the installation directory

### Usage

```bash
chmod +x uninstall-gitea-ip.sh
./uninstall-gitea-ip.sh -i /path/to/install [options]
```

#### Options

| Option           | Description                                                               |
| ---------------- | ------------------------------------------------------------------------- |
| `-i INSTALL_DIR` | Installation directory (default: /opt/gitea)                              |
| `-r`             | Remove data volumes (CAUTION: This will delete all repositories and data) |
| `-h`             | Display help and exit                                                     |

### Example

```bash
./uninstall-gitea-ip.sh -i /opt/gitea -r
```

This will completely remove the Gitea installation, including all data.

## Requirements

- Linux server with Docker and Docker Compose
- Root or sudo access
- A static or stable IP address for your server

## Post-Installation

After installation:

1. Access your Gitea instance at `https://your-server-ip`
   - You'll need to accept the security warning about the self-signed certificate
2. Complete the initial setup wizard
3. For SSH access, use: `git@your-server-ip:222` (or the port you specified)

## Maintenance

The installation creates a README.md file in the installation directory with:

- Access information
- Database password (if auto-generated)
- Common management commands
- Backup instructions

## Security Notes

1. This setup uses self-signed certificates which will generate browser warnings
2. For production use with a domain name, consider using Let's Encrypt certificates
3. The installation configures firewall rules automatically if firewalld or ufw is detected
4. Strong security headers are configured in Nginx

## Switching to Domain-Based Setup Later

If you later want to use a domain name instead of an IP address:

1. Configure DNS to point your domain to your server's IP
2. Update the configuration files with your domain instead of the IP address
3. Obtain a proper SSL certificate (e.g., Let's Encrypt)

## Troubleshooting

If you encounter issues:

- Check container logs: `docker logs gitea`, `docker logs gitea-db`, `docker logs gitea-nginx`
- Verify that the containers are running: `docker ps`
- Check firewall rules to ensure ports 80, 443, and your SSH port are open
- Ensure no other services are using the required ports
