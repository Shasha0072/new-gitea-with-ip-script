#!/bin/bash
#
# Automated Gitea Installation Script with HTTPS using IP Address or Domain
# ======================================================================
#
# This script automates the installation of Gitea with HTTPS using Nginx as a reverse proxy,
# configuring it to use either a server's IP address or a domain name.
# Compatible with both Docker and Podman container engines.
#
# Usage:
#   ./install-gitea-domain.sh [-p "StrongPassword123"] [-i /path/to/install] [-s SSH_PORT] [-I IP_ADDRESS] [-d DOMAIN]
#
# Options:
#   -p PASSWORD      Database and initial admin password (default: auto-generated)
#   -i INSTALL_DIR   Installation directory (default: /opt/gitea)
#   -s SSH_PORT      SSH port for Git operations (default: 222)
#   -I IP_ADDRESS    Server IP address (default: auto-detected)
#   -d DOMAIN        Domain name for Gitea (optional)
#   -h               Display this help and exit

# Key Improvements:

# Container Engine Detection: The script now automatically detects if Docker or Podman is available and configures the environment accordingly.
# Podman Compatibility: If Podman is detected, the script sets up the necessary symlinks and configurations to make it work seamlessly.
# Flexible Image References: The script uses fully qualified image names with docker.io/ prefixes for better compatibility with both engines.
# Smart Command Selection: It automatically uses the appropriate commands (docker/podman, docker-compose/podman-compose) based on what's available.
# Detailed Feedback: The script provides clear information about which container engine is being used and how to interact with it.
# Improved Error Handling: Better handling of various edge cases and potential failures during the setup process.

set -e

# Default values
DB_PASSWORD=""
INSTALL_DIR="/opt/gitea"
SSH_PORT=222
IP_ADDRESS=""
DOMAIN=""
AUTO_PASSWORD=false
CONTAINER_ENGINE=""

# Parse command-line options
while getopts "p:i:s:I:d:h" opt; do
  case ${opt} in
    p) DB_PASSWORD=$OPTARG ;;
    i) INSTALL_DIR=$OPTARG ;;
    s) SSH_PORT=$OPTARG ;;
    I) IP_ADDRESS=$OPTARG ;;
    d) DOMAIN=$OPTARG ;;
    h)
      echo "Usage: $0 [-p \"StrongPassword123\"] [-i /path/to/install] [-s SSH_PORT] [-I IP_ADDRESS] [-d DOMAIN]"
      echo
      echo "Options:"
      echo "  -p PASSWORD      Database and initial admin password (default: auto-generated)"
      echo "  -i INSTALL_DIR   Installation directory (default: /opt/gitea)"
      echo "  -s SSH_PORT      SSH port for Git operations (default: 222)"
      echo "  -I IP_ADDRESS    Server IP address (default: auto-detected)"
      echo "  -d DOMAIN        Domain name for Gitea (optional)"
      echo "  -h               Display this help and exit"
      exit 0
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

# Auto-detect IP if not provided
if [ -z "$IP_ADDRESS" ]; then
  echo "Auto-detecting server IP address..."
  IP_ADDRESS=$(ip addr show | grep -E "inet .* scope global" | head -1 | awk '{print $2}' | cut -d/ -f1)

  if [ -z "$IP_ADDRESS" ]; then
    echo "Error: Could not detect server IP address. Please provide it with -I option."
    exit 1
  fi

  echo "Detected IP address: $IP_ADDRESS"
fi

# Determine server name to use (domain or IP)
if [ -n "$DOMAIN" ]; then
  SERVER_NAME="$DOMAIN"
  echo "Using domain name: $DOMAIN"
  
  # If not already in hosts file, suggest adding it
  if ! grep -q "$DOMAIN" /etc/hosts; then
    echo "Note: You may want to add this entry to /etc/hosts on client machines:"
    echo "$IP_ADDRESS $DOMAIN"
  fi
else
  SERVER_NAME="$IP_ADDRESS"
  echo "Using IP address as server name: $IP_ADDRESS"
fi

# Generate random password if not provided
if [ -z "$DB_PASSWORD" ]; then
  DB_PASSWORD=$(openssl rand -base64 16 | tr -d '/+=' | cut -c1-16)
  AUTO_PASSWORD=true
fi

# Check for container engine (Docker or Podman)
setup_container_engine() {
  # Check for Docker first
  if command -v docker &> /dev/null && systemctl is-active --quiet docker; then
    echo "Docker is installed and running."
    CONTAINER_ENGINE="docker"
    return 0
  elif command -v docker &> /dev/null; then
    echo "Docker is installed but not running. Attempting to start..."
    systemctl start docker
    if systemctl is-active --quiet docker; then
      echo "Docker started successfully."
      CONTAINER_ENGINE="docker"
      return 0
    else
      echo "Failed to start Docker."
    fi
  fi
  
  # Check for Podman
  if command -v podman &> /dev/null; then
    echo "Podman detected. Setting up Podman to work as Docker replacement..."
    CONTAINER_ENGINE="podman"
    
    # Check if podman-docker is installed (provides docker command)
    if ! command -v docker &> /dev/null; then
      echo "Creating symbolic link for docker command..."
      ln -sf $(which podman) /usr/local/bin/docker
      export PATH=$PATH:/usr/local/bin
    fi
    
    # Check for docker-compose or podman-compose
    if ! command -v docker-compose &> /dev/null; then
      if command -v podman-compose &> /dev/null; then
        echo "Creating symbolic link for docker-compose command..."
        ln -sf $(which podman-compose) /usr/local/bin/docker-compose
      else
        echo "Installing podman-compose..."
        if command -v pip3 &> /dev/null; then
          pip3 install podman-compose
          ln -sf $(which podman-compose) /usr/local/bin/docker-compose
        else
          echo "Error: pip3 not found. Please install python3-pip first."
          exit 1
        fi
      fi
    fi
    
    # Create socket directory if it doesn't exist
    RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
    mkdir -p ${RUNTIME_DIR}/podman
    
    # Create docker socket symlink
    if [ ! -e /var/run/docker.sock ]; then
      echo "Creating docker socket symlink..."
      mkdir -p /var/run
      ln -sf ${RUNTIME_DIR}/podman/podman.sock /var/run/docker.sock 2>/dev/null || {
        echo "Warning: Could not create symlink to Docker socket. Running as root may be required."
        sudo ln -sf ${RUNTIME_DIR}/podman/podman.sock /var/run/docker.sock 2>/dev/null || true
      }
    fi
    
    return 0
  fi
  
  # No container engine found, attempt to install Docker
  echo "No container engine found. Attempting to install Docker..."
  
  if command -v apt-get &> /dev/null; then
    # Debian/Ubuntu
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io
  elif command -v dnf &> /dev/null; then
    # RHEL/CentOS/AlmaLinux
    if rpm -q podman-docker &> /dev/null; then
      echo "podman-docker is installed. Using Podman instead of Docker."
      CONTAINER_ENGINE="podman"
      setup_container_engine
      return 0
    fi
    
    dnf -y install dnf-plugins-core
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    dnf install -y docker-ce docker-ce-cli containerd.io
  elif command -v yum &> /dev/null; then
    # Older RHEL/CentOS
    yum install -y yum-utils
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    yum install -y docker-ce docker-ce-cli containerd.io
  else
    echo "Error: Unsupported package manager. Please install Docker or Podman manually."
    exit 1
  fi
  
  # Start and enable Docker service
  systemctl start docker
  systemctl enable docker
  
  # Check if Docker is now running
  if systemctl is-active --quiet docker; then
    echo "Docker installed and started successfully."
    CONTAINER_ENGINE="docker"
    return 0
  else
    echo "Error: Failed to install or start Docker."
    exit 1
  fi
}

# Check for Docker Compose
ensure_docker_compose() {
  if ! command -v docker-compose &> /dev/null; then
    echo "Docker Compose is not installed. Installing..."
    curl -L "https://github.com/docker/compose/releases/download/v2.24.6/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
  fi
}

# Check for OpenSSL
check_command() {
  if ! command -v $1 &> /dev/null; then
    echo "$1 is not installed. Installing..."
    if command -v apt-get &> /dev/null; then
      # Debian/Ubuntu
      apt-get update
      apt-get install -y $2
    elif command -v dnf &> /dev/null; then
      # RHEL/CentOS/AlmaLinux
      dnf install -y $2
    elif command -v yum &> /dev/null; then
      # Older RHEL/CentOS
      yum install -y $2
    else
      echo "Unable to install $1. Please install it manually."
      exit 1
    fi
  fi
}

# Display installation plan
echo "Gitea Installation Plan:"
echo "========================"
echo "Server IP:         $IP_ADDRESS"
if [ -n "$DOMAIN" ]; then
  echo "Domain Name:       $DOMAIN"
fi
if [ "$AUTO_PASSWORD" = true ]; then
  echo "Database Password: $DB_PASSWORD (auto-generated)"
else
  echo "Database Password: (as provided)"
fi
echo "Installation Dir:  $INSTALL_DIR"
echo "SSH Port:          $SSH_PORT"

echo
echo "The installation will begin in 5 seconds. Press Ctrl+C to cancel."
sleep 5

# Setup container engine (Docker or Podman)
setup_container_engine

# Check for required commands
check_command openssl openssl

# If using Docker, ensure Docker Compose is installed
if [ "$CONTAINER_ENGINE" = "docker" ]; then
  ensure_docker_compose
fi

# Clean up any existing installation
echo "Checking for existing installation..."
if [ -d "$INSTALL_DIR" ]; then
  read -p "Installation directory $INSTALL_DIR already exists. Remove it? [y/N] " remove_dir
  if [[ "$remove_dir" =~ ^[Yy]$ ]]; then
    echo "Stopping any running containers..."
    if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
      cd "$INSTALL_DIR"
      docker-compose down 2>/dev/null || podman-compose down 2>/dev/null || true
    fi

    echo "Removing existing installation directory..."
    rm -rf "$INSTALL_DIR"
  else
    echo "Installation aborted. Please choose a different directory or remove the existing one."
    exit 1
  fi
fi

# Create installation directory
echo "Creating installation directory..."
mkdir -p $INSTALL_DIR/{nginx/ssl,nginx/conf.d}
cd $INSTALL_DIR

# Create Docker Compose file
echo "Creating Docker Compose configuration..."
cat > docker-compose.yml << EOF
version: "3"

networks:
  gitea:
    external: false

volumes:
  gitea-data:
  postgres-data:

services:
  server:
    image: docker.io/gitea/gitea:1.23.7
    container_name: gitea
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - GITEA__database__DB_TYPE=postgres
      - GITEA__database__HOST=db:5432
      - GITEA__database__NAME=gitea
      - GITEA__database__USER=gitea
      - GITEA__database__PASSWD=${DB_PASSWORD}
      - GITEA__server__DOMAIN=${SERVER_NAME}
      - GITEA__server__ROOT_URL=https://${SERVER_NAME}/
      - GITEA__server__SSH_DOMAIN=${SERVER_NAME}
      - GITEA__server__SSH_PORT=22
      - GITEA__service__DISABLE_REGISTRATION=false
      - GITEA__log__MODE=console
    restart: unless-stopped
    networks:
      - gitea
    volumes:
      - gitea-data:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    expose:
      - "3000"
      - "22"
    ports:
      - "${SSH_PORT}:22"  # For SSH access
    depends_on:
      - db

  db:
    image: docker.io/postgres:14-alpine
    container_name: gitea-db
    restart: unless-stopped
    environment:
      - POSTGRES_USER=gitea
      - POSTGRES_PASSWORD=${DB_PASSWORD}
      - POSTGRES_DB=gitea
    networks:
      - gitea
    volumes:
      - postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "gitea"]
      interval: 10s
      timeout: 5s
      retries: 5

  nginx:
    image: docker.io/nginx:alpine
    container_name: gitea-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./nginx/ssl:/etc/nginx/ssl
    networks:
      - gitea
    depends_on:
      - server
EOF

# Create Nginx configuration
echo "Creating Nginx configuration..."
cat > nginx/conf.d/gitea.conf << EOF
server {
    listen 80;
    server_name ${SERVER_NAME};

    # Redirect all HTTP requests to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name ${SERVER_NAME};

    # SSL configuration
    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;

    # Security headers
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Proxy configuration
    location / {
        proxy_pass http://server:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket support
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        # Increase timeouts for large Git operations
        proxy_read_timeout 300;
        proxy_connect_timeout 300;
        proxy_send_timeout 300;

        client_max_body_size 100M;
    }
}
EOF

# Generate self-signed SSL certificates
echo "Generating self-signed SSL certificates..."
mkdir -p nginx/ssl
cd nginx/ssl
openssl genrsa -out key.pem 2048
openssl req -new -key key.pem -out csr.pem -subj "/CN=${SERVER_NAME}"
openssl x509 -req -days 365 -in csr.pem -signkey key.pem -out cert.pem
cd $INSTALL_DIR

# Start the containers
echo "Starting Gitea..."
if [ "$CONTAINER_ENGINE" = "docker" ]; then
  docker-compose up -d
else
  # If using Podman
  podman-compose up -d || docker-compose up -d
fi

# Configure firewall if needed
echo "Checking firewall configuration..."
if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
  echo "FirewallD is running, configuring rules..."
  firewall-cmd --permanent --add-service=http
  firewall-cmd --permanent --add-service=https
  firewall-cmd --permanent --add-port=${SSH_PORT}/tcp
  firewall-cmd --reload
  echo "Firewall configured successfully."
elif command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
  echo "UFW is running, configuring rules..."
  ufw allow http
  ufw allow https
  ufw allow ${SSH_PORT}/tcp
  echo "Firewall configured successfully."
else
  echo "No active firewall detected. No firewall rules added."
fi

# Create a simple README file
cat > README.md << EOF
# Gitea Installation

## Access Information

EOF

if [ -n "$DOMAIN" ]; then
  cat >> README.md << EOF
- Gitea Web Interface: https://${DOMAIN}
- SSH Access: ssh://git@${DOMAIN}:${SSH_PORT}
- IP Address: ${IP_ADDRESS}
EOF
else
  cat >> README.md << EOF
- Gitea Web Interface: https://${IP_ADDRESS}
- SSH Access: ssh://git@${IP_ADDRESS}:${SSH_PORT}
EOF
fi

cat >> README.md << EOF
- Installation Directory: ${INSTALL_DIR}
- Database Password: ${DB_PASSWORD}
- Container Engine: ${CONTAINER_ENGINE}

## Management Commands

EOF

if [ "$CONTAINER_ENGINE" = "docker" ]; then
  cat >> README.md << EOF
- View logs: \`docker-compose logs -f\`
- Restart services: \`docker-compose restart\`
- Stop services: \`docker-compose down\`
- Start services: \`docker-compose up -d\`
EOF
else
  cat >> README.md << EOF
- View logs: \`podman-compose logs -f\` or \`docker-compose logs -f\`
- Restart services: \`podman-compose restart\` or \`docker-compose restart\`
- Stop services: \`podman-compose down\` or \`docker-compose down\`
- Start services: \`podman-compose up -d\` or \`docker-compose up -d\`
EOF
fi

cat >> README.md << EOF

## Backup Commands

To backup your Gitea installation:

\`\`\`bash
# Backup Gitea data
EOF

if [ "$CONTAINER_ENGINE" = "docker" ]; then
  cat >> README.md << EOF
docker run --rm --volumes-from gitea -v \$(pwd)/backups:/backup alpine sh -c "cd /data && tar czf /backup/gitea-data-\$(date +%Y%m%d).tar.gz ."

# Backup PostgreSQL database
docker exec -t gitea-db pg_dumpall -c -U gitea | gzip > \$(pwd)/backups/postgres-\$(date +%Y%m%d).gz
EOF
else
  cat >> README.md << EOF
podman run --rm --volumes-from gitea -v \$(pwd)/backups:/backup alpine sh -c "cd /data && tar czf /backup/gitea-data-\$(date +%Y%m%d).tar.gz ."

# Backup PostgreSQL database
podman exec -t gitea-db pg_dumpall -c -U gitea | gzip > \$(pwd)/backups/postgres-\$(date +%Y%m%d).gz
EOF
fi

cat >> README.md << EOF
\`\`\`

EOF

if [ -n "$DOMAIN" ]; then
  cat >> README.md << EOF
## Domain Configuration

To access Gitea using the domain name ${DOMAIN}, add this entry to the hosts file on each client machine:

\`\`\`
${IP_ADDRESS} ${DOMAIN}
\`\`\`

- On Linux/macOS: Edit /etc/hosts
- On Windows: Edit C:\\Windows\\System32\\drivers\\etc\\hosts
EOF
fi

# Wait for services to start
echo "Waiting for services to start..."
sleep 10

# Check if all containers are running
CONTAINER_CMD="docker"
[ "$CONTAINER_ENGINE" = "podman" ] && CONTAINER_CMD="podman"

CONTAINERS_RUNNING=$(${CONTAINER_CMD} ps --filter "name=gitea" --format "{{.Names}}" | wc -l)
if [ "$CONTAINERS_RUNNING" -eq 3 ]; then
  echo ""
  echo "==================================================="
  echo "Gitea has been successfully installed!"
  echo "==================================================="
  echo ""
  if [ -n "$DOMAIN" ]; then
    echo "Access your Gitea instance at: https://${DOMAIN}"
    echo "(Make sure to add the IP-to-domain mapping in your hosts file)"
  else
    echo "Access your Gitea instance at: https://${IP_ADDRESS}"
  fi
  echo "SSH access port: ${SSH_PORT}"
  echo ""
  if [ "$AUTO_PASSWORD" = true ]; then
    echo "Database Password: ${DB_PASSWORD}"
    echo "(This password is also saved in the README.md file)"
  fi
  echo ""
  echo "Installation details saved to: ${INSTALL_DIR}/README.md"
  echo ""
  echo "You'll need to accept the self-signed certificate warning in your browser."
  echo ""
  echo "When you first access Gitea, you'll be directed to the setup page"
  echo "to create an admin account and configure other settings."
  echo ""
  echo "Container engine in use: ${CONTAINER_ENGINE}"
  echo ""
  
  if [ -n "$DOMAIN" ]; then
    echo "To access Gitea using the domain name, add this to your hosts file:"
    echo "${IP_ADDRESS} ${DOMAIN}"
    echo ""
  fi
else
  echo ""
  echo "==================================================="
  echo "Warning: Not all containers are running!"
  echo "==================================================="
  echo ""
  echo "Please check the container logs for errors:"
  echo "${CONTAINER_CMD} logs gitea"
  echo "${CONTAINER_CMD} logs gitea-db"
  echo "${CONTAINER_CMD} logs gitea-nginx"
  echo ""
  echo "Container engine in use: ${CONTAINER_ENGINE}"
  echo ""
fi

exit 0
