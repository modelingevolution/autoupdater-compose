#!/bin/bash

# AutoUpdater Complete Installation Script (Bootstrapper)
# This script acts as a bootstrapper that:
# 1. Downloads required scripts if not present locally (with checksum verification)
# 2. Installs Docker and Docker Compose
# 3. Installs VPN (OpenVPN for Ubuntu 20.04, WireGuard for 22.04+)
# 4. Installs AutoUpdater
#
# Security: All downloaded scripts are verified using SHA256 checksums
# Checksums are automatically updated by update-checksums.sh (run via pre-commit hook)
#
# Usage: ./install.sh [--json] [--verbose|-v] [--docker-username <username>] <app-name> <git-compose-url> <computer-name>
# Example: ./install.sh rocket-welder https://github.com/modelingevolution/rocketwelder-compose.git RESRV-AI
# Example with verbose: ./install.sh -v rocket-welder https://github.com/modelingevolution/rocketwelder-compose.git RESRV-AI
# Example with docker auth: ./install.sh --docker-username RESRV-AI-token rocket-welder https://github.com/modelingevolution/rocketwelder-compose.git RESRV-AI token123 registry.azurecr.io

set -e

# Configuration variables
AUTOUPDATER_VERSION="1.0.42"  # Replaced from autoupdater.version file

# Global variables
JSON_OUTPUT=false
VERBOSE=false
DOCKER_USERNAME=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Download logging.sh first if not present
if [ ! -f "$SCRIPT_DIR/logging.sh" ]; then
    echo "Downloading logging.sh..."
    curl -fsSL "https://raw.githubusercontent.com/modelingevolution/autoupdater-compose/master/logging.sh" -o "$SCRIPT_DIR/logging.sh"
    chmod +x "$SCRIPT_DIR/logging.sh"
fi

# Source logging library
source "$SCRIPT_DIR/logging.sh"

# Parse arguments
parse_arguments() {
    # Process flags
    while [[ "$1" =~ ^- ]]; do
        case "$1" in
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --docker-username)
                DOCKER_USERNAME="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    if [ $# -lt 3 ] || [ $# -gt 5 ]; then
        if [ "$JSON_OUTPUT" = true ]; then
            echo '{"status":"error","message":"Usage: ./install.sh [--json] [--verbose|-v] [--docker-username <username>] <app-name> <git-compose-url> <computer-name> [docker-auth] [docker-registry-url]"}'
        else
            echo "Usage: $0 [--json] [--verbose|-v] [--docker-username <username>] <app-name> <git-compose-url> <computer-name> [docker-auth] [docker-registry-url]"
            echo "Example: $0 rocket-welder https://github.com/modelingevolution/rocketwelder-compose.git RESRV-AI"
            echo "Example with Docker auth: $0 --docker-username RESRV-AI-token rocket-welder https://github.com/modelingevolution/rocketwelder-compose.git RESRV-AI token123 registry.azurecr.io"
            echo "Options:"
            echo "  --json                    Output in JSON format"
            echo "  --verbose, -v             Show detailed output"
            echo "  --docker-username <name>  Docker registry username (overrides auto-detection)"
            echo "  -v          Same as --verbose"
        fi
        exit 1
    fi
    
    APP_NAME="$1"
    GIT_COMPOSE_URL="$2"
    COMPUTER_NAME="$3"
    DOCKER_AUTH="${4:-}"
    DOCKER_REGISTRY_URL="${5:-}"
    
    # Validate Docker parameters - both must be provided or both empty
    if [ -n "$DOCKER_AUTH" ] && [ -z "$DOCKER_REGISTRY_URL" ]; then
        log_error "docker-registry-url must be provided when docker-auth is specified"
        exit 1
    fi
    if [ -z "$DOCKER_AUTH" ] && [ -n "$DOCKER_REGISTRY_URL" ]; then
        log_error "docker-auth must be provided when docker-registry-url is specified"
        exit 1
    fi
    
    # Initialize logging with parsed options
    init_logging
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Detect Ubuntu version
detect_ubuntu_version() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" == "ubuntu" ]]; then
            UBUNTU_VERSION="$VERSION_ID"
            log_info "Detected Ubuntu $UBUNTU_VERSION"
            return 0
        fi
    fi
    log_error "This script only supports Ubuntu"
    exit 1
}

# Install Docker and Docker Compose
install_docker() {
    log_info "Installing Docker and Docker Compose" "docker"
    
    # Check if Docker is already installed
    if command -v docker &> /dev/null; then
        log_info "Docker already installed, checking version"
        DOCKER_VERSION=$(docker --version)
        log_info "Current Docker version: $DOCKER_VERSION"
    else
        log_info "Installing Docker"
        
        # Update package index
        run_quiet "Updating package index" apt-get update
        
        # Install prerequisites
        run_quiet "Installing Docker prerequisites" apt-get install -y \
            apt-transport-https \
            ca-certificates \
            curl \
            gnupg \
            lsb-release
        
        # Add Docker's official GPG key
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        
        # Set up the repository
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Install Docker Engine
        run_quiet "Updating package index" apt-get update
        run_quiet "Installing Docker Engine" apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
        
        # Enable and start Docker
        systemctl enable docker
        systemctl start docker
        
        log_info "Docker installed successfully"
    fi
    
    # Check Docker Compose
    if command -v docker-compose &> /dev/null; then
        log_info "Docker Compose (standalone) already installed"
    elif docker compose version &> /dev/null 2>&1; then
        log_info "Docker Compose (plugin) already installed"
    else
        log_info "Installing Docker Compose"
        
        # For Ubuntu 20.04, install standalone docker-compose, for newer versions use plugin
        if [[ "$UBUNTU_VERSION" == "20.04" ]]; then
            # Install standalone docker-compose for Ubuntu 20.04
            DOCKER_COMPOSE_VERSION="2.20.2"
            # Detect architecture
            ARCH=$(uname -m)
            case $ARCH in
                x86_64) DOCKER_ARCH="x86_64" ;;
                aarch64|arm64) DOCKER_ARCH="aarch64" ;;
                *) 
                    log_error "Unsupported architecture: $ARCH"
                    exit 1
                    ;;
            esac
            curl -fsSL "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-linux-${DOCKER_ARCH}" -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
            log_info "Docker Compose standalone installed successfully for $ARCH"
        else
            # Install Docker Compose plugin for newer Ubuntu versions
            run_quiet "Installing Docker Compose plugin" apt-get install -y docker-compose-plugin
            log_info "Docker Compose plugin installed successfully"
        fi
    fi
    
    log_info "Docker installation completed" "docker"
}

# Install VPN based on Ubuntu version
install_vpn() {
    log_info "Installing VPN" "vpn"
    
    case "$UBUNTU_VERSION" in
        "20.04")
            install_openvpn
            ;;
        "22.04"|"24.04")
            install_wireguard
            ;;
        *)
            log_warn "Unsupported Ubuntu version for VPN installation: $UBUNTU_VERSION"
            ;;
    esac
    
    log_info "VPN installation completed" "vpn"
}

# Install OpenVPN for Ubuntu 20.04
install_openvpn() {
    if command -v openvpn &> /dev/null; then
        log_info "OpenVPN already installed"
        return 0
    fi
    
    log_info "Installing OpenVPN for Ubuntu 20.04"
    
    run_quiet "Updating package index" apt-get update
    run_quiet "Installing OpenVPN" apt-get install -y openvpn easy-rsa
    
    # Create easy-rsa directory
    if [ ! -d /etc/openvpn/easy-rsa ]; then
        make-cadir /etc/openvpn/easy-rsa
        log_info "OpenVPN easy-rsa directory created at /etc/openvpn/easy-rsa"
    fi
    
    log_info "OpenVPN installed successfully"
}

# Install WireGuard for Ubuntu 22.04/24.04
install_wireguard() {
    if command -v wg &> /dev/null; then
        log_info "WireGuard already installed"
        return 0
    fi
    
    log_info "Installing WireGuard for Ubuntu $UBUNTU_VERSION"
    
    run_quiet "Updating package index" apt-get update
    run_quiet "Installing WireGuard" apt-get install -y wireguard wireguard-tools
    
    # Create WireGuard directory
    if [ ! -d /etc/wireguard ]; then
        mkdir -p /etc/wireguard
        chmod 700 /etc/wireguard
    fi
    
    log_info "WireGuard installed successfully"
}

# Download and verify script with checksum
download_script() {
    local script_name="$1"
    local expected_checksum="$2"
    local script_path="$SCRIPT_DIR/$script_name"
    local download_needed=false
    
    # Check if script exists and verify checksum
    if [ ! -f "$script_path" ]; then
        download_needed=true
        log_info "$script_name not found, downloading from GitHub repository"
    else
        # Verify existing script checksum
        local current_checksum=$(sha256sum "$script_path" | cut -d' ' -f1)
        if [ "$current_checksum" != "$expected_checksum" ]; then
            download_needed=true
            log_warn "$script_name checksum mismatch (expected: $expected_checksum, got: $current_checksum), re-downloading"
        else
            log_info "$script_name exists and checksum verified"
        fi
    fi
    
    if [ "$download_needed" = true ]; then
        local url="https://raw.githubusercontent.com/modelingevolution/autoupdater-compose/master/$script_name"
        
        if ! curl -fsSL "$url" -o "$script_path"; then
            log_error "Failed to download $script_name from $url"
            exit 1
        fi
        
        # Verify downloaded script checksum
        local downloaded_checksum=$(sha256sum "$script_path" | cut -d' ' -f1)
        if [ "$downloaded_checksum" != "$expected_checksum" ]; then
            log_error "Downloaded $script_name checksum verification failed (expected: $expected_checksum, got: $downloaded_checksum)"
            rm -f "$script_path"
            exit 1
        fi
        
        chmod +x "$script_path"
        log_info "Successfully downloaded and verified $script_name"
    fi
}

# Perform Docker login if credentials provided
docker_login() {
    if [ -n "$DOCKER_AUTH" ] && [ -n "$DOCKER_REGISTRY_URL" ]; then
        log_info "Logging into Docker registry: $DOCKER_REGISTRY_URL" "docker-login"
        
        # Determine username - use provided username or auto-detect
        local username="token"
        if [ -n "$DOCKER_USERNAME" ]; then
            username="$DOCKER_USERNAME"
            log_info "Using provided Docker username: $username"
        elif [[ "$DOCKER_REGISTRY_URL" == *".azurecr.io"* ]]; then
            # For Azure Container Registry, extract registry name as username
            username=$(echo "$DOCKER_REGISTRY_URL" | sed 's/\.azurecr\.io.*//')
            log_info "Auto-detected ACR username: $username"
        fi
        
        # Login to Docker registry using the provided credentials
        if echo "$DOCKER_AUTH" | docker_quiet login "$DOCKER_REGISTRY_URL" --username "$username" --password-stdin; then
            log_info "Successfully logged into Docker registry"
        else
            log_error "Failed to login to Docker registry $DOCKER_REGISTRY_URL"
            exit 1
        fi
    else
        log_info "No Docker registry credentials provided, skipping login"
    fi
}

# Install AutoUpdater
install_autoupdater() {
    log_info "Installing AutoUpdater" "autoupdater"
    
    # Expected checksums for dependent scripts (auto-generated by update-checksums.sh)
    local INSTALL_UPDATER_CHECKSUM="fb04af86ff851590e3e7ca604149822ea8ea63764d4eeb33b7e3d0dfaaf3aed1"
    local AUTOUPDATER_SH_CHECKSUM="c99fc6b70a7f6e1691dbdadf2b0369b3c2ad7564f6c59a1de42455e974f9cf6a"
    local LOGGING_SH_CHECKSUM="b488f9af1faaff4d5caa1837093b6e99c59df6751f8a0715a24f93afcbfae7e7"
    
    # Verify logging.sh checksum (already downloaded at script start)
    local current_logging_checksum=$(sha256sum "$SCRIPT_DIR/logging.sh" | cut -d' ' -f1)
    if [ "$current_logging_checksum" != "$LOGGING_SH_CHECKSUM" ]; then
        log_warn "logging.sh checksum mismatch, re-downloading"
        download_script "logging.sh" "$LOGGING_SH_CHECKSUM"
    else
        log_info "logging.sh checksum verified"
    fi
    
    # Download and verify install-updater.sh
    download_script "install-updater.sh" "$INSTALL_UPDATER_CHECKSUM"
    
    # Download and verify autoupdater.sh
    download_script "autoupdater.sh" "$AUTOUPDATER_SH_CHECKSUM"
    
    local updater_script="$SCRIPT_DIR/install-updater.sh"
    
    # Run the updater installation with Docker parameters
    log_info "Running AutoUpdater installation script"
    if [ -n "$DOCKER_AUTH" ] && [ -n "$DOCKER_REGISTRY_URL" ]; then
        if ! "$updater_script" "$APP_NAME" "$GIT_COMPOSE_URL" "$COMPUTER_NAME" "$DOCKER_AUTH" "$DOCKER_REGISTRY_URL" "$AUTOUPDATER_VERSION"; then
            log_error "AutoUpdater installation failed"
            exit 1
        fi
    else
        if ! "$updater_script" "$APP_NAME" "$GIT_COMPOSE_URL" "$COMPUTER_NAME" "" "" "$AUTOUPDATER_VERSION"; then
            log_error "AutoUpdater installation failed"
            exit 1
        fi
    fi
    
    log_info "AutoUpdater installation completed" "autoupdater"
}

# Trigger application deployment via AutoUpdater REST API
trigger_application_deployment() {
    log_info "Triggering application deployment" "deployment"
    
    local autoupdater_script="$SCRIPT_DIR/autoupdater.sh"
    local max_retries=30
    local retry_delay=10
    
    # Wait for AutoUpdater to become healthy
    log_info "Waiting for AutoUpdater to become healthy..."
    local retry_count=0
    while [ $retry_count -lt $max_retries ]; do
        if "$autoupdater_script" health >/dev/null 2>&1; then
            log_info "AutoUpdater is healthy"
            break
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -ge $max_retries ]; then
            log_error "AutoUpdater health check failed after $max_retries attempts"
            log_info "Debugging: Let's check what the autoupdater.sh script outputs"
            "$autoupdater_script" health || true
            exit 1
        fi
        
        log_info "Waiting for AutoUpdater to become healthy... (attempt $retry_count/$max_retries)"
        sleep $retry_delay
    done
    
    # Trigger deployment for the application
    log_info "Triggering deployment for $APP_NAME"
    if ! "$autoupdater_script" update "$APP_NAME"; then
        log_warn "Failed to trigger deployment for $APP_NAME - this may be expected on first installation"
        log_info "AutoUpdater will automatically deploy the application on next update cycle"
    else
        log_info "Application deployment triggered successfully"
    fi
    
    log_info "Application deployment completed" "deployment"
}

# Main installation function
main() {
    parse_arguments "$@"
    
    log_info "Starting complete installation for $APP_NAME on $COMPUTER_NAME"
    
    # Check prerequisites
    check_root
    detect_ubuntu_version
    
    # Install curl if not present (needed for downloads)
    if ! command -v curl &> /dev/null; then
        log_info "Installing curl"
        run_quiet "Updating package index" apt-get update
        run_quiet "Installing curl" apt-get install -y curl
    fi
    
    # Step 1: Install Docker and Docker Compose
    install_docker
    
    # Step 2: Install VPN
    install_vpn
    
    # Step 3: Perform Docker login (if credentials provided)
    docker_login
    
    # Step 4: Install AutoUpdater
    install_autoupdater
    
    # Step 5: Trigger application deployment
    trigger_application_deployment
    
    if [ "$JSON_OUTPUT" = true ]; then
        echo '{"status":"success","message":"Installation completed successfully","app":"'$APP_NAME'","computer":"'$COMPUTER_NAME'","ubuntu_version":"'$UBUNTU_VERSION'"}'
    else
        log_info "Installation completed successfully!"
        echo ""
        log_info "Summary:"
        log_info "  - Ubuntu version: $UBUNTU_VERSION"
        log_info "  - Docker: Installed"
        log_info "  - VPN: Installed ($([ "$UBUNTU_VERSION" = "20.04" ] && echo "OpenVPN" || echo "WireGuard"))"
        log_info "  - AutoUpdater: Installed for $APP_NAME"
        log_info "  - Web UI: http://localhost:8080"
    fi
}

# Run main function
main "$@"