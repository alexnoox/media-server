#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Logger function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

# Check if script is run as root and exit if it is
if [ "$(id -u)" = "0" ]; then
    error "This script should not be run as root or with sudo"
    error "It will ask for your password when necessary"
    exit 1
fi

# Function to check command existence
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if system is Ubuntu/Debian based
if ! command_exists apt-get; then
    error "This script is designed for Ubuntu/Debian-based systems"
    error "Your system doesn't have apt-get, cannot continue"
    exit 1
fi

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    if [ -f .env.tmpl ]; then
        log "Creating .env file from .env.tmpl"
        cp .env.tmpl .env
        # Set USER_ID and GROUP_ID in .env
        sed -i.bak "s/^USER_ID=.*/USER_ID=$(id -u)/" .env
        sed -i.bak "s/^GROUP_ID=.*/GROUP_ID=$(id -g)/" .env
        rm .env.bak
        log "Updated .env with your user ID ($(id -u)) and group ID ($(id -g))"
        warning "Please review and update other settings in the .env file before starting the stack"
    else
        error ".env.tmpl not found, cannot create .env file"
        error "Please create a .env file manually before running this script"
        exit 1
    fi
fi

# Set timezone
log "Setting timezone to Australia/Brisbane"
sudo timedatectl set-timezone Australia/Brisbane || {
    warning "Failed to set timezone, continuing anyway"
}

# Install Docker
log "Removing any conflicting Docker packages"
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do 
    sudo apt-get remove -y $pkg >/dev/null 2>&1 || true
done

log "Installing Docker dependencies"
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

log "Setting up Docker repository"
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

log "Installing Docker"
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add user to docker group
log "Adding user to docker group"
sudo usermod -aG docker $USER
warning "You may need to log out and back in for docker group changes to take effect"

# Check for NVIDIA GPU
if lspci | grep -i nvidia >/dev/null 2>&1; then
    log "NVIDIA GPU detected, installing drivers and container toolkit"
    
    # Install NVIDIA drivers
    log "Installing NVIDIA drivers"
    sudo ubuntu-drivers install --gpgpu nvidia:535 || {
        warning "Failed to install NVIDIA drivers, you may need to install them manually"
    }
    
    # Install NVIDIA Container Toolkit
    log "Installing NVIDIA Container Toolkit"
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
      && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list \
      && \
        sudo apt-get update
    sudo apt-get install -y nvidia-container-toolkit
    
    # Install nvtop for monitoring
    log "Installing nvtop for GPU monitoring"
    sudo snap install nvtop || {
        warning "Failed to install nvtop, skipping"
    }
else
    warning "No NVIDIA GPU detected, skipping NVIDIA driver and toolkit installation"
    warning "If you have an NVIDIA GPU and it wasn't detected, install drivers manually"
fi

# Make scripts executable
log "Making scripts executable"
chmod +x update-config.sh

log "${GREEN}Installation complete!${NC}"
log "Next steps:"
log "1. Review settings in .env file"
log "2. Start containers with: docker compose up -d"
log "3. After startup completes, run: ./update-config.sh"
log "4. Access Homepage at https://media.YOUR_DOMAIN"

warning "You may need to log out and back in for docker group changes to take effect"