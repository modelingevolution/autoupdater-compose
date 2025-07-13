#!/bin/bash

# AutoUpdater Uninstall Script
# Usage: sudo ./uninstall.sh [--json]
# This script removes AutoUpdater installation but keeps Docker and Docker Compose

set -e

# Global variables
JSON_OUTPUT=false

# Parse arguments
parse_arguments() {
    if [[ "$1" == "--json" ]]; then
        JSON_OUTPUT=true
        shift
    fi
}

# Logging functions
log_json() {
    local level="$1"
    local message="$2"
    local step="${3:-}"
    
    if [ "$JSON_OUTPUT" = true ]; then
        if [ -n "$step" ]; then
            echo "{\"status\":\"$level\",\"step\":\"$step\",\"message\":\"$message\"}"
        else
            echo "{\"status\":\"$level\",\"message\":\"$message\"}"
        fi
    else
        case $level in
            "info") echo -e "\e[32m[INFO]\e[0m $message" ;;
            "warn") echo -e "\e[33m[WARN]\e[0m $message" ;;
            "error") echo -e "\e[31m[ERROR]\e[0m $message" ;;
            *) echo "$message" ;;
        esac
    fi
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_json "error" "This script must be run as root"
        exit 1
    fi
}

# Stop and remove AutoUpdater container
stop_containers() {
    log_json "info" "Stopping and removing AutoUpdater containers" "containers"
    
    # Stop AutoUpdater container if running
    if docker ps -q -f name=autoupdater | grep -q .; then
        log_json "info" "Stopping AutoUpdater container"
        docker stop autoupdater || true
    fi
    
    # Remove AutoUpdater container if exists
    if docker ps -a -q -f name=autoupdater | grep -q .; then
        log_json "info" "Removing AutoUpdater container"
        docker rm autoupdater || true
    fi
    
    # Remove AutoUpdater network if exists
    if docker network ls -q -f name=autoupdater-network | grep -q .; then
        log_json "info" "Removing AutoUpdater network"
        docker network rm autoupdater-network || true
    fi
    
    log_json "info" "Container cleanup completed" "containers"
}

# Remove configuration directories
remove_configuration() {
    log_json "info" "Removing configuration directories" "configuration"
    
    # Remove AutoUpdater configuration
    if [ -d "/var/docker/configuration" ]; then
        log_json "info" "Removing /var/docker/configuration"
        rm -rf /var/docker/configuration
    fi
    
    # Remove AutoUpdater data
    if [ -d "/var/docker/data" ]; then
        log_json "info" "Removing /var/docker/data"
        rm -rf /var/docker/data
    fi
    
    # Remove parent directory if empty
    if [ -d "/var/docker" ] && [ -z "$(ls -A /var/docker)" ]; then
        log_json "info" "Removing empty /var/docker directory"
        rmdir /var/docker
    fi
    
    log_json "info" "Configuration cleanup completed" "configuration"
}

# Remove deploy user
remove_deploy_user() {
    log_json "info" "Removing deploy user" "user"
    
    # Check if deploy user exists
    if id "deploy" &>/dev/null; then
        # Stop any processes running as deploy user
        log_json "info" "Stopping processes for deploy user"
        pkill -u deploy || true
        sleep 2
        
        # Remove user and home directory
        log_json "info" "Removing deploy user and home directory"
        userdel -r deploy 2>/dev/null || {
            # If userdel fails, try to remove home directory manually
            log_json "warn" "Failed to remove user with userdel, cleaning up manually"
            userdel deploy 2>/dev/null || true
            rm -rf /home/deploy 2>/dev/null || true
        }
        
        log_json "info" "Deploy user removed"
    else
        log_json "info" "Deploy user does not exist"
    fi
    
    log_json "info" "User cleanup completed" "user"
}

# Clean up Docker images (optional)
cleanup_docker_images() {
    log_json "info" "Cleaning up AutoUpdater Docker images" "images"
    
    # Remove AutoUpdater images
    if docker images -q modelingevolution/autoupdater | grep -q .; then
        log_json "info" "Removing AutoUpdater Docker images"
        docker rmi $(docker images -q modelingevolution/autoupdater) || true
    fi
    
    # Clean up unused Docker resources
    log_json "info" "Cleaning up unused Docker resources"
    docker system prune -f || true
    
    log_json "info" "Docker cleanup completed" "images"
}

# Restore Docker socket permissions
restore_docker_permissions() {
    log_json "info" "Restoring Docker socket permissions" "permissions"
    
    if [ -S /var/run/docker.sock ]; then
        chown root:docker /var/run/docker.sock
        chmod 660 /var/run/docker.sock
        log_json "info" "Docker socket permissions restored"
    fi
    
    log_json "info" "Permissions restored" "permissions"
}

# Main uninstall function
main() {
    parse_arguments "$@"
    
    log_json "info" "Starting AutoUpdater uninstallation"
    
    # Check prerequisites
    check_root
    
    # Confirm uninstallation
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo "This will remove:"
        echo "  - AutoUpdater containers and networks"
        echo "  - All configuration files and repositories"
        echo "  - Deploy user and SSH keys"
        echo "  - AutoUpdater Docker images"
        echo ""
        echo "Docker and Docker Compose will NOT be removed."
        echo ""
        read -p "Are you sure you want to continue? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_json "info" "Uninstallation cancelled by user"
            exit 0
        fi
    fi
    
    # Perform uninstallation steps
    stop_containers
    remove_configuration
    remove_deploy_user
    cleanup_docker_images
    restore_docker_permissions
    
    if [ "$JSON_OUTPUT" = true ]; then
        echo '{"status":"success","message":"AutoUpdater uninstallation completed successfully"}'
    else
        log_json "info" "Uninstallation completed successfully!"
        echo ""
        log_json "info" "Summary:"
        log_json "info" "  - AutoUpdater containers: Removed"
        log_json "info" "  - Configuration files: Removed"
        log_json "info" "  - Deploy user: Removed"
        log_json "info" "  - Docker images: Cleaned up"
        log_json "info" "  - Docker & Docker Compose: Preserved"
        echo ""
        log_json "info" "System cleaned up successfully!"
    fi
}

# Run main function
main "$@"