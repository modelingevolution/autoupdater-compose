#!/bin/bash

# AutoUpdater Version Update Script
# This script fetches the latest semantic version from Docker Hub and updates all relevant files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_REPO="modelingevolution/autoupdater"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Function to get latest semantic version from Docker Hub
get_latest_version() {
    log_info "Fetching latest version from Docker Hub..."
    
    # Get all tags from Docker Hub API
    local tags_response=$(curl -s "https://hub.docker.com/v2/repositories/${DOCKER_REPO}/tags?page_size=100")
    
    if [ $? -ne 0 ]; then
        log_error "Failed to fetch tags from Docker Hub"
        return 1
    fi
    
    # Extract semantic version tags (x.y.z format) and sort them
    local latest_version=$(echo "$tags_response" | \
        grep -o '"name":"[^"]*"' | \
        grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | \
        sort -V | \
        tail -n1)
    
    if [ -z "$latest_version" ]; then
        log_error "No semantic version found in Docker Hub tags"
        return 1
    fi
    
    log_info "Latest version found: $latest_version"
    echo "$latest_version"
}

# Function to update version in a file
update_version_in_file() {
    local file_path="$1"
    local old_version="$2"
    local new_version="$3"
    local pattern="$4"
    
    if [ ! -f "$file_path" ]; then
        log_warn "File not found: $file_path"
        return 1
    fi
    
    log_debug "Updating $file_path: $old_version -> $new_version"
    
    # Create backup
    cp "$file_path" "$file_path.backup"
    
    # Update the version using the provided pattern
    sed -i "s/$pattern/$new_version/" "$file_path"
    
    # Verify the change
    if grep -q "$new_version" "$file_path"; then
        log_info "✓ Updated $file_path"
        rm "$file_path.backup"
        return 0
    else
        log_error "✗ Failed to update $file_path"
        mv "$file_path.backup" "$file_path"
        return 1
    fi
}

# Function to find current version in files
find_current_version() {
    local file_path="$1"
    local pattern="$2"
    
    if [ ! -f "$file_path" ]; then
        return 1
    fi
    
    grep -o "$pattern" "$file_path" | head -n1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' || echo ""
}

# Main update function
update_versions() {
    local new_version="$1"
    
    log_info "Updating AutoUpdater version to $new_version in all files..."
    
    # Files to update with their patterns
    declare -A files_to_update=(
        ["$SCRIPT_DIR/install.template"]="AUTOUPDATER_VERSION=\"[0-9]\+\.[0-9]\+\.[0-9]\+\""
        ["$SCRIPT_DIR/install-updater.sh"]="AUTOUPDATER_VERSION=\"\${6:-[0-9]\+\.[0-9]\+\.[0-9]\+}\""
    )
    
    local updated_files=0
    local total_files=${#files_to_update[@]}
    
    for file_path in "${!files_to_update[@]}"; do
        local pattern="${files_to_update[$file_path]}"
        local current_version=$(find_current_version "$file_path" "$pattern")
        
        if [ -n "$current_version" ]; then
            if [ "$current_version" != "$new_version" ]; then
                local update_pattern=$(echo "$pattern" | sed "s/[0-9]\\+\\.[0-9]\\+\\.[0-9]\\+/$current_version/")
                local replacement=$(echo "$pattern" | sed "s/[0-9]\\+\\.[0-9]\\+\\.[0-9]\\+/$new_version/")
                
                if update_version_in_file "$file_path" "$current_version" "$replacement" "$update_pattern"; then
                    ((updated_files++))
                fi
            else
                log_info "✓ $file_path already has version $new_version"
                ((updated_files++))
            fi
        else
            log_warn "Could not find version pattern in $file_path"
        fi
    done
    
    log_info "Updated $updated_files of $total_files files"
    
    # Regenerate install.sh from template
    if [ -f "$SCRIPT_DIR/update-checksums.sh" ]; then
        log_info "Regenerating install.sh from template..."
        cd "$SCRIPT_DIR"
        ./update-checksums.sh
        log_info "✓ install.sh regenerated"
    fi
}

# Function to show current versions
show_current_versions() {
    log_info "Current versions in files:"
    
    local files=(
        "$SCRIPT_DIR/install.template"
        "$SCRIPT_DIR/install-updater.sh"
        "$SCRIPT_DIR/docker-compose.yml"
    )
    
    for file_path in "${files[@]}"; do
        if [ -f "$file_path" ]; then
            local version=$(grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' "$file_path" | head -n1)
            if [ -n "$version" ]; then
                log_info "  $(basename "$file_path"): $version"
            else
                log_warn "  $(basename "$file_path"): No version found"
            fi
        else
            log_warn "  $(basename "$file_path"): File not found"
        fi
    done
}

# Help function
show_help() {
    cat << EOF
AutoUpdater Version Update Script

USAGE:
    $0 [command] [options]

COMMANDS:
    check                   Show current versions in files
    update                  Update to latest version from Docker Hub
    set <version>           Set specific version (e.g., 1.0.33)
    help                    Show this help message

EXAMPLES:
    $0 check                # Show current versions
    $0 update               # Update to latest version
    $0 set 1.0.33           # Set to specific version

EOF
}

# Main command dispatcher
main() {
    local command="$1"
    
    case "$command" in
        check)
            show_current_versions
            ;;
        update)
            local latest_version=$(get_latest_version)
            if [ -n "$latest_version" ]; then
                update_versions "$latest_version"
            else
                log_error "Failed to get latest version"
                exit 1
            fi
            ;;
        set)
            local version="$2"
            if [ -z "$version" ]; then
                log_error "Version is required"
                show_help
                exit 1
            fi
            
            # Validate version format
            if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                log_error "Invalid version format. Expected: x.y.z"
                exit 1
            fi
            
            update_versions "$version"
            ;;
        help|--help|-h)
            show_help
            ;;
        "")
            log_error "No command provided"
            show_help
            exit 1
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"