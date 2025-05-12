# Remove podman packages

sudo dnf remove -y podman podman-docker containers-common

# Clean up any leftover files

sudo rm -rf /var/run/docker.sock

# Install Docker repositories

sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# Install Docker CE

sudo dnf install -y docker-ce docker-ce-cli containerd.io

# Start and enable Docker service

sudo systemctl start docker
sudo systemctl enable docker
