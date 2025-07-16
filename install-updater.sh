#!/bin/bash

# AutoUpdater Installation Script
# Usage: ./install-updater.sh <app-name> <git-compose-url> <computer-name> [docker-auth] [docker-registry-url] [autoupdater-version]
# Example: ./install-updater.sh rocket-welder https://github.com/modelingevolution/rocketwelder-compose.git RESRV-AI
# Example with Docker auth: ./install-updater.sh rocket-welder https://github.com/modelingevolution/rocketwelder-compose.git RESRV-AI ghp_token123 ghcr.io/myorg
# Example with version: ./install-updater.sh rocket-welder https://github.com/modelingevolution/rocketwelder-compose.git RESRV-AI "" "" 1.0.32

set -e

# Source logging library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"

# Initialize logging with environment variables
init_logging

# Check parameters
if [ $# -lt 3 ] || [ $# -gt 6 ]; then
    echo "Usage: $0 <app-name> <git-compose-url> <computer-name> [docker-auth] [docker-registry-url] [autoupdater-version]"
    echo "Example: $0 rocket-welder https://github.com/modelingevolution/rocketwelder-compose.git RESRV-AI"
    echo "Example with Docker auth: $0 rocket-welder https://github.com/modelingevolution/rocketwelder-compose.git RESRV-AI ghp_token123 ghcr.io/myorg"
    echo "Example with version: $0 rocket-welder https://github.com/modelingevolution/rocketwelder-compose.git RESRV-AI \"\" \"\" 1.0.32"
    exit 1
fi

APP_NAME="$1"
GIT_COMPOSE_URL="$2"
COMPUTER_NAME="$3"
DOCKER_AUTH="${4:-}"
DOCKER_REGISTRY_URL="${5:-}"
AUTOUPDATER_VERSION="$6"  # Must be passed from install.sh

# Validate required parameters
if [ -z "$AUTOUPDATER_VERSION" ]; then
    log_error "AUTOUPDATER_VERSION must be provided as 6th parameter"
    exit 1
fi

# Validate Docker parameters - both must be provided or both empty
if [ -n "$DOCKER_AUTH" ] && [ -z "$DOCKER_REGISTRY_URL" ]; then
    log_error "docker-registry-url must be provided when docker-auth is specified"
    exit 1
fi
if [ -z "$DOCKER_AUTH" ] && [ -n "$DOCKER_REGISTRY_URL" ]; then
    log_error "docker-auth must be provided when docker-registry-url is specified"
    exit 1
fi

# Configuration
DEFAULT_USER="deploy"
CONFIG_BASE="/var/docker/configuration"
AUTOUPDATER_CONFIG="$CONFIG_BASE/autoupdater"
DOCKER_COMPOSE_CMD="docker-compose"

# Logging functions are provided by logging.sh

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
    mkdir -p "/var/docker/data/autoupdater/.ssh"
    
    # Set proper permissions
    chown -R "$DEFAULT_USER:$DEFAULT_USER" "$CONFIG_BASE"
    chown -R "$DEFAULT_USER:$DEFAULT_USER" "/var/docker/data"
    chmod 755 "$CONFIG_BASE"
    chmod 700 "/var/docker/data/autoupdater/.ssh"
    
    log_info "Directory structure created at $CONFIG_BASE"
}

# Generate SSH keys
generate_ssh_keys() {
    local ssh_dir="/var/docker/data/autoupdater/.ssh"
    local private_key="$ssh_dir/id_rsa"
    local public_key="$ssh_dir/id_rsa.pub"
    
    log_info "Generating SSH keys for autoupdater"
    
    if [ -f "$private_key" ]; then
        log_warn "SSH key already exists at $private_key"
        return 0
    fi
    
    # Generate SSH key pair
    run_quiet "Generating SSH keys" sudo -u "$DEFAULT_USER" ssh-keygen -t rsa -b 4096 -f "$private_key" -N "" -C "autoupdater@$COMPUTER_NAME"
    
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
    
    # Clone the autoupdater-compose repository to the autoupdater directory
    if [ ! -d "$AUTOUPDATER_CONFIG/.git" ]; then
        # Remove the directory if it exists but is not a git repo
        if [ -d "$AUTOUPDATER_CONFIG" ]; then
            rm -rf "$AUTOUPDATER_CONFIG"
        fi
        
        log_info "Cloning autoupdater-compose repository..."
        if ! git_quiet clone https://github.com/modelingevolution/autoupdater-compose.git "$AUTOUPDATER_CONFIG"; then
            log_error "Failed to clone autoupdater-compose repository"
            exit 1
        fi
    fi

    # Create appsettings.Production.json (gitignored file) - only overrides for this installation
    cat > "$AUTOUPDATER_CONFIG/appsettings.Production.json" << EOF
{
  "ComputerName": "$COMPUTER_NAME",
  "Packages": [
    {
      "RepositoryLocation": "/data/$APP_NAME",
      "RepositoryUrl": "$GIT_COMPOSE_URL",
      "DockerComposeDirectory": "./",
      "DockerAuth": "${DOCKER_AUTH:-}",
      "DockerRegistryUrl": "${DOCKER_REGISTRY_URL:-}"
    }
  ]
}
EOF

    # Create appsettings.override.json file for runtime configuration
    cat > "/var/docker/data/autoupdater/appsettings.override.json" << EOF
{
  "ComputerName": "$COMPUTER_NAME"
}
EOF

    # Create .env file
    cat > "$AUTOUPDATER_CONFIG/.env" << EOF
# AutoUpdater Configuration for $COMPUTER_NAME
SSH_USER=$DEFAULT_USER
HOST_ADDRESS=172.17.0.1
COMPUTER_NAME=$COMPUTER_NAME
AUTOUPDATER_VERSION=$AUTOUPDATER_VERSION
DOCKER_REGISTRY_URL=
EOF

    # Set proper ownership for the git repository (must be deploy user to allow git operations)
    chown -R "$DEFAULT_USER:$DEFAULT_USER" "$AUTOUPDATER_CONFIG"
    
    # Application repository will be cloned by AutoUpdater on first run
    # This maintains proper separation of concerns
    log_info "Application repository will be managed by AutoUpdater"
    
    # Keep autoupdater directory owned by deploy user for git operations
    if ! sudo chown -R "$DEFAULT_USER:$DEFAULT_USER" "$AUTOUPDATER_CONFIG"; then
        log_error "Failed to set proper ownership of autoupdater directory"
        exit 1
    fi
    
    log_info "Configuration files created"
}

# Start autoupdater
start_autoupdater() {
    log_info "Starting AutoUpdater container"
    
    cd "$AUTOUPDATER_CONFIG" || {
        log_error "Failed to change to directory: $AUTOUPDATER_CONFIG"
        exit 1
    }
    
    if [ "$VERBOSE" = "true" ]; then
        if ! sudo -u "$DEFAULT_USER" $DOCKER_COMPOSE_CMD up -d; then
            log_error "Failed to start AutoUpdater container"
            exit 1
        fi
    else
        if ! sudo -u "$DEFAULT_USER" $DOCKER_COMPOSE_CMD up -d --quiet-pull 2>&1 | grep -v "Network\|Container\|Creating\|Created\|Starting\|Started" || [ ${PIPESTATUS[0]} -ne 0 ]; then
            log_error "Failed to start AutoUpdater container"
            exit 1
        fi
    fi
    
    # Wait a moment for container to start
    sleep 5
    
    # Verify container is running
    if ! docker ps | grep -q "autoupdater"; then
        log_error "AutoUpdater container is not running"
        log_error "Check logs with: docker logs autoupdater"
        exit 1
    fi
    
    log_info "AutoUpdater started successfully"
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