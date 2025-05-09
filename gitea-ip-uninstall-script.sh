#!/bin/bash
#
# Gitea Uninstallation Script for IP-Based Installation
# ============================================
#
# This script removes a Gitea installation that was set up using the install-gitea-ip.sh script.
#
# Usage:
#   ./uninstall-gitea-ip.sh -i /path/to/install [-r]
#
# Options:
#   -i INSTALL_DIR   Installation directory (default: /opt/gitea)
#   -r               Remove data volumes (CAUTION: This will delete all repositories and data)
#   -h               Display this help and exit

set -e

# Default values
INSTALL_DIR="/opt/gitea"
REMOVE_DATA=false

# Parse command-line options
while getopts "i:rh" opt; do
  case ${opt} in
    i) INSTALL_DIR=$OPTARG ;;
    r) REMOVE_DATA=true ;;
    h)
      echo "Usage: $0 -i /path/to/install [-r]"
      echo
      echo "Options:"
      echo "  -i INSTALL_DIR   Installation directory (default: /opt/gitea)"
      echo "  -r               Remove data volumes (CAUTION: This will delete all repositories and data)"
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

# Check if installation directory exists
if [ ! -d "$INSTALL_DIR" ]; then
  echo "Error: Installation directory $INSTALL_DIR does not exist."
  exit 1
fi

# Check if docker-compose.yml exists
if [ ! -f "$INSTALL_DIR/docker-compose.yml" ]; then
  echo "Error: docker-compose.yml not found in $INSTALL_DIR."
  echo "This doesn't appear to be a valid Gitea installation directory."
  exit 1
fi

# Get IP address from docker-compose file for firewall rules
IP_ADDRESS=$(grep -o 'GITEA__server__DOMAIN=[^ ]*' "$INSTALL_DIR/docker-compose.yml" | cut -d= -f2)
SSH_PORT=$(grep -P '"([0-9]+):22"' "$INSTALL_DIR/docker-compose.yml" | grep -o '[0-9]\+:22' | cut -d: -f1)

# Display uninstallation plan
echo "Gitea Uninstallation Plan:"
echo "=========================="
echo "Installation Dir:  $INSTALL_DIR"
if [ "$REMOVE_DATA" = true ]; then
  echo "Data Volumes:     Will be removed (all repositories and data will be deleted)"
else
  echo "Data Volumes:     Will be preserved (use -r to remove them)"
fi
if [ -n "$IP_ADDRESS" ]; then
  echo "IP Address:       $IP_ADDRESS"
fi
if [ -n "$SSH_PORT" ]; then
  echo "SSH Port:         $SSH_PORT"
fi

echo
echo "The uninstallation will begin in 5 seconds. Press Ctrl+C to cancel."
sleep 5

# Change to installation directory
cd "$INSTALL_DIR"

# Stop and remove containers
echo "Stopping and removing containers..."
docker-compose down

# Remove volumes if requested
if [ "$REMOVE_DATA" = true ]; then
  echo "Removing data volumes..."
  docker volume rm $(docker volume ls -q | grep "gitea-data\|postgres-data") 2>/dev/null || true
fi

# Remove firewall rules if applicable
if command -v firewall-cmd &> /dev/null; then
  echo "Removing firewall rules..."
  firewall-cmd --permanent --remove-service=http || true
  firewall-cmd --permanent --remove-service=https || true
  if [ -n "$SSH_PORT" ]; then
    firewall-cmd --permanent --remove-port=${SSH_PORT}/tcp || true
  fi
  firewall-cmd --reload
elif command -v ufw &> /dev/null; then
  echo "Removing UFW firewall rules..."
  ufw delete allow http || true
  ufw delete allow https || true
  if [ -n "$SSH_PORT" ]; then
    ufw delete allow ${SSH_PORT}/tcp || true
  fi
fi

# Optionally remove the installation directory
echo "Do you want to remove the installation directory ($INSTALL_DIR)? [y/N]"
read -r remove_dir

if [[ "$remove_dir" =~ ^[Yy]$ ]]; then
  echo "Removing installation directory..."
  cd ..
  rm -rf "$INSTALL_DIR"
fi

echo ""
echo "==================================================="
echo "Gitea has been successfully uninstalled!"
echo "==================================================="
echo ""
if [ "$REMOVE_DATA" = false ]; then
  echo "Data volumes have been preserved. To remove them manually, run:"
  echo "docker volume rm \$(docker volume ls -q | grep \"gitea-data\|postgres-data\")"
  echo ""
fi

exit 0
