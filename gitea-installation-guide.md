# Gitea IP-Based Installation Guide

This guide walks you through installing Gitea with HTTPS using your server's IP address, eliminating the need for domain name configuration.

## Prerequisites

- A Linux server with root/sudo access
- Docker and Docker Compose installed
- A stable IP address for your server
- Open ports: 80 (HTTP), 443 (HTTPS), and 222 (SSH)

## Installation Steps

### 1. Download the Installation Script

```bash
# Create a directory for the installation files
mkdir -p ~/gitea-install
cd ~/gitea-install

# Download the installation script
curl -O https://raw.githubusercontent.com/yourusername/gitea-secure-deploy/main/install-gitea-ip.sh

# Make it executable
chmod +x install-gitea-ip.sh
```

### 2. Run the Installation Script

For a basic installation with automatic IP detection:

```bash
./install-gitea-ip.sh
```

For a customized installation:

```bash
./install-gitea-ip.sh -p "YourSecurePassword" -i /opt/gitea -s 2222 -I 192.168.1.100
```

Options:
- `-p PASSWORD`: Set a specific database password
- `-i INSTALL_DIR`: Choose a custom installation directory (default: /opt/gitea)
- `-s SSH_PORT`: Define the SSH port for Git operations (default: 222)
- `-I IP_ADDRESS`: Specify an IP address (default: auto-detected)

### 3. Wait for Installation to Complete

The script will:
1. Check for required dependencies
2. Create necessary directories
3. Generate configuration files
4. Create self-signed SSL certificates
5. Start Docker containers
6. Configure firewall rules (if applicable)

### 4. Access Gitea and Complete Setup

1. Open your browser and navigate to `https://YOUR_SERVER_IP`
2. Accept the security warning about the self-signed certificate
3. Complete the initial setup form:
   - Database settings should be pre-filled (PostgreSQL)
   - Create an admin account (username and password)
   - Set your organization details
   - Configure site title and other options
   - Choose registration options (if you want to allow others to register)
4. Click "Install Gitea" to complete the setup

## Post-Installation Steps

### 1. Create Your First Repository

1. Log in with your admin account
2. Click the "+" icon in the upper right corner
3. Select "New Repository"
4. Fill in:
   - Repository name
   - Description (optional)
   - Visibility settings
   - Initialize repository (optional)
5. Click "Create Repository"

### 2. Configure Git on Your Local Machine

```bash
# Configure global Git settings if not already done
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"

# Clone a repository
git clone ssh://git@YOUR_SERVER_IP:222/username/repository.git

# Or push an existing repository
cd existing-repo
git remote add origin ssh://git@YOUR_SERVER_IP:222/username/repository.git
git push -u origin main
```

### 3. Set Up SSH Keys for Passwordless Access

```bash
# Generate SSH key if you don't have one
ssh-keygen -t ed25519 -C "your.email@example.com"

# Copy the public key
cat ~/.ssh/id_ed25519.pub
```

Then:
1. Log in to Gitea
2. Go to "Settings" → "SSH / GPG Keys"
3. Click "Add Key"
4. Paste your public key and add a title
5. Click "Add Key"

## Maintenance and Management

### Backup Your Gitea Instance

```bash
# Create a backup directory
mkdir -p /opt/gitea/backups

# Backup Gitea data
cd /opt/gitea
docker run --rm --volumes-from gitea -v $(pwd)/backups:/backup alpine sh -c "cd /data && tar czf /backup/gitea-data-$(date +%Y%m%d).tar.gz ."

# Backup PostgreSQL database
docker exec -t gitea-db pg_dumpall -c -U gitea | gzip > $(pwd)/backups/postgres-$(date +%Y%m%d).gz
```

### View Logs

```bash
# View Gitea logs
docker logs -f gitea

# View database logs
docker logs -f gitea-db

# View Nginx logs
docker logs -f gitea-nginx
```

### Restart Services

```bash
cd /opt/gitea
docker-compose restart
```

### Stop All Services

```bash
cd /opt/gitea
docker-compose down
```

### Start All Services

```bash
cd /opt/gitea
docker-compose up -d
```

## Troubleshooting

### Certificate Warnings

When accessing Gitea through HTTPS, you'll see a security warning because the installation uses self-signed certificates. This is normal and you can safely proceed.

For a production environment where you don't want warnings, consider:
1. Using a proper domain name
2. Obtaining a Let's Encrypt certificate

### Connection Issues

If you can't connect to Gitea:

1. **Verify containers are running**:
   ```bash
   docker ps | grep gitea
   ```

2. **Check if ports are open**:
   ```bash
   # Check if ports are open
   netstat -tulpn | grep -E ':(80|443|222)'
   ```

3. **Test direct access**:
   ```bash
   # Test HTTP access
   curl -I http://localhost
   
   # Test Gitea directly
   curl -I http://localhost:3000
   ```

4. **Check container logs for errors**:
   ```bash
   docker logs gitea
   ```

### Database Connection Issues

If Gitea can't connect to the database:

```bash
# Check database container status
docker logs gitea-db

# Test database connection
docker exec -it gitea-db psql -U gitea -c "SELECT 1"
```

## Uninstallation

If you need to remove Gitea:

```bash
# Download the uninstallation script
curl -O https://raw.githubusercontent.com/yourusername/gitea-secure-deploy/main/uninstall-gitea-ip.sh
chmod +x uninstall-gitea-ip.sh

# Run the uninstaller
./uninstall-gitea-ip.sh -i /opt/gitea

# Add -r to remove all data
./uninstall-gitea-ip.sh -i /opt/gitea -r
```

## Security Considerations

1. **Change Default Passwords**: Make sure to use strong, unique passwords for your admin account and database
2. **Regular Backups**: Implement regular backups of your Gitea data and database
3. **Updates**: Keep your containers updated with the latest security patches
4. **SSH Key Authentication**: Use SSH keys instead of passwords for Git operations
5. **Firewall Rules**: Ensure your firewall only allows necessary ports (80, 443, 222)

---

For more information and advanced configurations, visit the [Gitea Documentation](https://docs.gitea.io/).
