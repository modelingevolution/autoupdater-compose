#!/bin/bash

# AutoUpdater Installation Script
# Usage: ./installation.sh <app-name> <git-compose-url> <computer-name>
# Example: ./installation.sh rocket-welder https://github.com/modelingevolution/rocketwelder-compose.git POC-400

set -e

# Check parameters
if [ $# -ne 3 ]; then
    echo "Usage: $0 <app-name> <git-compose-url> <computer-name>"
    echo "Example: $0 rocket-welder https://github.com/modelingevolution/rocketwelder-compose.git POC-400"
    exit 1
fi

APP_NAME="$1"
GIT_COMPOSE_URL="$2"
COMPUTER_NAME="$3"

# Configuration
DEFAULT_USER="deploy"
CONFIG_BASE="/var/docker/configuration"
AUTOUPDATER_CONFIG="$CONFIG_BASE/autoupdater"
DOCKER_COMPOSE_CMD="docker-compose"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Create deploy user
create_deploy_user() {
    local username=${1:-$DEFAULT_USER}
    
    log_info "Creating deploy user: $username"
    
    if id "$username" &>/dev/null; then
        log_warn "User $username already exists"
    else
        # Create user with home directory
        useradd -m -s /bin/bash "$username"
        
        # Add user to docker group
        usermod -aG docker "$username"
        
        log_info "User $username created and added to docker group"
    fi
    
    # Ensure user can access docker socket
    if [ -S /var/run/docker.sock ]; then
        chown root:docker /var/run/docker.sock
        chmod 660 /var/run/docker.sock
    fi
}

# Create directory structure
create_directories() {
    log_info "Creating directory structure"
    
    # Create base configuration directory
    mkdir -p "$CONFIG_BASE"
    mkdir -p "$AUTOUPDATER_CONFIG"
    mkdir -p "$AUTOUPDATER_CONFIG/.ssh"
    mkdir -p "$CONFIG_BASE/repositories"
    
    # Set proper permissions
    chown -R "$DEFAULT_USER:$DEFAULT_USER" "$CONFIG_BASE"
    chmod 755 "$CONFIG_BASE"
    chmod 700 "$AUTOUPDATER_CONFIG/.ssh"
    
    log_info "Directory structure created at $CONFIG_BASE"
}

# Generate SSH keys
generate_ssh_keys() {
    local ssh_dir="$AUTOUPDATER_CONFIG/.ssh"
    local private_key="$ssh_dir/id_rsa"
    local public_key="$ssh_dir/id_rsa.pub"
    
    log_info "Generating SSH keys for autoupdater"
    
    if [ -f "$private_key" ]; then
        log_warn "SSH key already exists at $private_key"
        return 0
    fi
    
    # Generate SSH key pair
    sudo -u "$DEFAULT_USER" ssh-keygen -t rsa -b 4096 -f "$private_key" -N "" -C "autoupdater@$COMPUTER_NAME"
    
    # Set proper permissions
    chmod 600 "$private_key"
    chmod 644 "$public_key"
    chown "$DEFAULT_USER:$DEFAULT_USER" "$private_key" "$public_key"
    
    log_info "SSH keys generated:"
    log_info "  Private key: $private_key"
    log_info "  Public key: $public_key"
    
    # Install public key locally for the deploy user
    local deploy_ssh_dir="/home/$DEFAULT_USER/.ssh"
    sudo mkdir -p "$deploy_ssh_dir"
    sudo sh -c "cat \"$public_key\" >> \"$deploy_ssh_dir/authorized_keys\""
    sudo chmod 700 "$deploy_ssh_dir"
    sudo chmod 600 "$deploy_ssh_dir/authorized_keys"
    sudo chown -R "$DEFAULT_USER:$DEFAULT_USER" "$deploy_ssh_dir"
    
    log_info "SSH public key installed for local deploy user"
}

# Create configuration files
create_configuration() {
    log_info "Creating configuration files for $APP_NAME on $COMPUTER_NAME"
    
    # Create docker-compose.yml
    cat > "$AUTOUPDATER_CONFIG/docker-compose.yml" << EOF
services:
  modelingevolution.autoupdater.host:
    image: modelingevolution/autoupdater:latest
    container_name: autoupdater
    restart: unless-stopped
    ports:
      - "8080:8080"
    volumes:
      # Mount Docker socket for container management
      - /var/run/docker.sock:/var/run/docker.sock
      # Data volume for persistent storage
      - /var/docker/configuration:/data
      # SSH keys for authentication
      - /var/docker/configuration/autoupdater/.ssh:/data/ssh:ro
      # Production configuration
      - /var/docker/configuration/autoupdater/appsettings.Production.json:/app/appsettings.Production.json:ro
    environment:
      - ASPNETCORE_ENVIRONMENT=Production
      - ASPNETCORE_URLS=http://+:8080
      # SSH Configuration
      - SshUser=$DEFAULT_USER
      - SshAuthMethod=PrivateKey
      - SshKeyPath=/data/ssh/id_rsa
      # Host configuration
      - HostAddress=172.17.0.1
      - ComputerName=$COMPUTER_NAME
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    networks:
      - autoupdater-network

networks:
  autoupdater-network:
    driver: bridge
EOF

    # Create appsettings.Production.json
    cat > "$AUTOUPDATER_CONFIG/appsettings.Production.json" << EOF
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  },
  "SshUser": "$DEFAULT_USER",
  "SshPwd": "dummy",
  "SshAuthMethod": "PrivateKey",
  "SshKeyPath": "/data/ssh/id_rsa",
  "HostAddress": "172.17.0.1",
  "ComputerName": "$COMPUTER_NAME",
  "StdPackages": [
    {
      "RepositoryLocation": "/data/repositories/autoupdater-compose",
      "RepositoryUrl": "https://github.com/modelingevolution/autoupdater-compose.git",
      "DockerComposeDirectory": "./",
      "DockerAuth": "",
      "DockerRegistryUrl": ""
    }
  ],
  "Packages": [
    {
      "RepositoryLocation": "/data/repositories/$APP_NAME-compose",
      "RepositoryUrl": "$GIT_COMPOSE_URL",
      "DockerComposeDirectory": "./",
      "DockerAuth": "",
      "DockerRegistryUrl": ""
    }
  ]
}
EOF

    # Create .env file
    cat > "$AUTOUPDATER_CONFIG/.env" << EOF
# AutoUpdater Configuration for $COMPUTER_NAME
SSH_USER=$DEFAULT_USER
HOST_ADDRESS=172.17.0.1
COMPUTER_NAME=$COMPUTER_NAME
EOF

    # Set proper ownership
    chown -R "$DEFAULT_USER:$DEFAULT_USER" "$AUTOUPDATER_CONFIG"
    
    log_info "Configuration files created"
}

# Start autoupdater
start_autoupdater() {
    log_info "Starting AutoUpdater container"
    
    cd "$AUTOUPDATER_CONFIG"
    sudo -u "$DEFAULT_USER" $DOCKER_COMPOSE_CMD up -d
    
    log_info "AutoUpdater started"
}

# Main installation function
main() {
    log_info "Starting AutoUpdater installation"
    log_info "  Application: $APP_NAME"
    log_info "  Repository: $GIT_COMPOSE_URL"
    log_info "  Computer: $COMPUTER_NAME"
    
    # Check prerequisites
    check_root
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check if Docker Compose is installed
    if ! command -v docker-compose &> /dev/null; then
        # Check for docker compose plugin
        if ! docker compose version &> /dev/null; then
            log_error "Docker Compose is not installed. Please install Docker Compose first."
            exit 1
        fi
        # Use docker compose instead of docker-compose
        DOCKER_COMPOSE_CMD="docker compose"
    else
        DOCKER_COMPOSE_CMD="docker-compose"
    fi
    
    # Perform installation steps
    create_deploy_user "$DEFAULT_USER"
    create_directories
    generate_ssh_keys
    create_configuration
    start_autoupdater
    
    log_info "Installation completed successfully!"
    echo ""
    log_info "AutoUpdater is now running and will manage:"
    log_info "  - Its own updates from: https://github.com/modelingevolution/autoupdater-compose.git"
    log_info "  - $APP_NAME updates from: $GIT_COMPOSE_URL"
    echo ""
    log_info "Access the web UI at: http://localhost:8080"
    log_info "Configuration directory: $AUTOUPDATER_CONFIG"
    log_info "Check logs: docker logs -f autoupdater"
}

# Run main function
main "$@"