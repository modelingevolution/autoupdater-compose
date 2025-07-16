#!/bin/bash

# AutoUpdater Version Update Script
# Updates the version in autoupdater.version file and docker-compose.yml

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

show_help() {
    cat << EOF
AutoUpdater Version Update Script

USAGE:
    ./update-version.sh [command] [options]

COMMANDS:
    check                   Show current version
    update                  Update to latest version from Docker Hub
    set <version>           Set specific version (e.g., 1.0.33)
    help                    Show this help message

EXAMPLES:
    ./update-version.sh check                # Show current version
    ./update-version.sh update               # Update to latest version
    ./update-version.sh set 1.0.33           # Set to specific version

EOF
}

get_current_version() {
    if [ -f "$SCRIPT_DIR/autoupdater.version" ]; then
        cat "$SCRIPT_DIR/autoupdater.version" | tr -d '\n'
    else
        echo "unknown"
    fi
}

get_latest_version() {
    log_info "Fetching latest version from Docker Hub..." >&2
    local latest_version=$(curl -s "https://registry.hub.docker.com/v2/repositories/modelingevolution/autoupdater/tags/?page_size=100" | \
        jq -r '.results[].name' | \
        grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | \
        sort -V | \
        tail -n1)
    
    if [ -z "$latest_version" ]; then
        log_error "Could not fetch latest version from Docker Hub"
        exit 1
    fi
    
    echo "$latest_version"
}

update_version() {
    local new_version="$1"
    
    log_info "Updating AutoUpdater version to $new_version"
    
    # Update the version file
    echo "$new_version" > "$SCRIPT_DIR/autoupdater.version"
    log_info "✓ Updated autoupdater.version to $new_version"
    
    # Update docker-compose.yml default version
    if [ -f "$SCRIPT_DIR/docker-compose.yml" ]; then
        local current_version=$(grep 'AUTOUPDATER_VERSION:-' "$SCRIPT_DIR/docker-compose.yml" | sed 's/.*AUTOUPDATER_VERSION:-\([^}]*\)}.*/\1/')
        if [ -n "$current_version" ] && [ "$current_version" != "$new_version" ]; then
            sed -i "s/AUTOUPDATER_VERSION:-$current_version}/AUTOUPDATER_VERSION:-$new_version}/" "$SCRIPT_DIR/docker-compose.yml"
            log_info "✓ Updated docker-compose.yml default: $current_version -> $new_version"
        fi
    fi
    
    # Regenerate install.sh from template
    if [ -f "$SCRIPT_DIR/update-checksums.sh" ]; then
        log_info "Regenerating install.sh from template..."
        "$SCRIPT_DIR/update-checksums.sh"
    fi
    
    log_info "Version update completed!"
}

# Main script logic
if [ $# -eq 0 ]; then
    log_error "No command provided"
    show_help
    exit 1
fi

case "$1" in
    "check")
        current_version=$(get_current_version)
        log_info "Current version: $current_version"
        ;;
    "update")
        latest_version=$(get_latest_version)
        log_info "Latest version found: $latest_version"
        update_version "$latest_version"
        ;;
    "set")
        if [ -z "$2" ]; then
            log_error "Please provide a version number"
            echo "Usage: $0 set <version>"
            exit 1
        fi
        update_version "$2"
        ;;
    "help")
        show_help
        ;;
    *)
        log_error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac