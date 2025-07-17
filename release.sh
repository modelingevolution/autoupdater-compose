#!/bin/bash

# AutoUpdater Compose Release Script
# Manages version tagging for the docker-compose repository

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_usage() {
    echo -e "${BLUE}AutoUpdater Compose Release Script${NC}"
    echo
    echo "Usage: ./release.sh [VERSION] [OPTIONS]"
    echo
    echo "Arguments:"
    echo "  VERSION     Semantic version (e.g., 1.2.3, 2.0.0)"
    echo "              If not provided, script will auto-increment patch version"
    echo
    echo "Options:"
    echo "  -m, --message TEXT    Commit message (default: 'Release vX.Y.Z')"
    echo "  -p, --patch           Auto-increment patch version (default)"
    echo "  -n, --minor           Auto-increment minor version"
    echo "  -M, --major           Auto-increment major version"
    echo "  --no-image-update     Skip updating autoupdater image version"
    echo "  --dry-run             Show what would be done without executing"
    echo "  -h, --help            Show this help message"
    echo
    echo "Examples:"
    echo "  ./release.sh 1.2.3                           # Release specific version"
    echo "  ./release.sh 1.2.3 -m \"Added new features\"   # With custom message"
    echo "  ./release.sh --minor -m \"New components\"     # Auto-increment minor"
    echo "  ./release.sh --patch                         # Auto-increment patch"
    echo "  ./release.sh --no-image-update               # Skip image version update"
    echo "  ./release.sh --dry-run                       # Preview release"
}

print_error() {
    echo -e "${RED}Error: $1${NC}" >&2
}

print_warning() {
    echo -e "${YELLOW}Warning: $1${NC}"
}

print_success() {
    echo -e "${GREEN}$1${NC}"
}

print_info() {
    echo -e "${BLUE}$1${NC}"
}

# Validate semantic version format
validate_version() {
    if [[ ! $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_error "Invalid version format: $1. Expected format: X.Y.Z (e.g., 1.2.3)"
        return 1
    fi
}

# Get the latest version tag for this repository
get_latest_version() {
    git tag --sort=-version:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 | sed 's/^v//' || echo "0.0.0"
}

# Increment version
increment_version() {
    local version=$1
    local part=$2
    
    IFS='.' read -ra VERSION_PARTS <<< "$version"
    local major=${VERSION_PARTS[0]}
    local minor=${VERSION_PARTS[1]}
    local patch=${VERSION_PARTS[2]}
    
    case $part in
        "major")
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        "minor")
            minor=$((minor + 1))
            patch=0
            ;;
        "patch"|*)
            patch=$((patch + 1))
            ;;
    esac
    
    echo "$major.$minor.$patch"
}

# Check if working directory is clean (no longer used, kept for reference)
check_working_directory() {
    if [[ -n $(git status --porcelain) ]]; then
        print_warning "Working directory has uncommitted changes:"
        git status --short
        return 0
    fi
}

# Update autoupdater image version
update_image_version() {
    local skip_update=$1
    
    if [[ "$skip_update" == "true" ]]; then
        print_info "Skipping autoupdater image version update (--no-image-update)"
        return 0
    fi
    
    print_info "Updating autoupdater image version..."
    if [[ -f "./update-version.sh" ]]; then
        ./update-version.sh update
        print_success "✓ Updated autoupdater image version"
    else
        print_error "update-version.sh not found"
        return 1
    fi
}

# Commit changes
commit_changes() {
    local version=$1
    local message=$2
    
    # Check if there are changes to commit
    if [[ -z $(git status --porcelain) ]]; then
        print_warning "No changes to commit"
        return 0
    fi
    
    print_info "Committing changes..."
    git add .
    
    if [[ -n "$message" ]]; then
        git commit -m "$message"
    else
        git commit -m "Release v$version"
    fi
    
    print_success "✓ Changes committed"
}

# Create and push tag
create_tag() {
    local version=$1
    local tag="v$version"
    
    if git tag -l | grep -q "^$tag$"; then
        print_error "Tag $tag already exists"
        return 1
    fi
    
    print_info "Creating tag: $tag"
    git tag "$tag"
    
    print_info "Pushing tag to origin..."
    git push origin "$tag"
    
    print_success "✅ Tag $tag created and pushed successfully"
}

# Main script logic
main() {
    local version=""
    local increment_type="patch"
    local message=""
    local dry_run=false
    local no_image_update=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                print_usage
                exit 0
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --no-image-update)
                no_image_update=true
                shift
                ;;
            -m|--message)
                message="$2"
                shift 2
                ;;
            -p|--patch)
                increment_type="patch"
                shift
                ;;
            -n|--minor)
                increment_type="minor"
                shift
                ;;
            -M|--major)
                increment_type="major"
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
            *)
                if [[ -z "$version" ]]; then
                    version="$1"
                else
                    print_error "Too many arguments"
                    print_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # If no version specified, auto-increment
    if [[ -z "$version" ]]; then
        local latest_version=$(get_latest_version)
        version=$(increment_version "$latest_version" "$increment_type")
        print_info "Auto-incrementing $increment_type version: $latest_version → $version"
    fi
    
    # Validate version format
    validate_version "$version" || exit 1
    
    # Check if tag already exists
    if git tag -l | grep -q "^v$version$"; then
        print_error "Tag v$version already exists"
        exit 1
    fi
    
    if [[ "$dry_run" == true ]]; then
        print_info "🔍 DRY RUN - Would perform the following actions:"
        print_info "1. Update autoupdater image version: $([ "$no_image_update" == "true" ] && echo "SKIP" || echo "YES")"
        print_info "2. Commit changes with message: ${message:-"Release v$version"}"
        print_info "3. Create and push tag: v$version"
        exit 0
    fi
    
    print_info "🚀 Starting AutoUpdater Compose release process..."
    print_info "Version: $version"
    if [[ -n "$message" ]]; then
        print_info "Message: $message"
    fi
    
    # Update autoupdater image version (unless skipped)
    update_image_version "$no_image_update" || exit 1
    
    # Commit changes (this will add all changes including any uncommitted files)
    commit_changes "$version" "$message" || exit 1
    
    # Create and push tag
    create_tag "$version" || exit 1
    
    print_success "🎉 Release $version completed successfully!"
    print_info ""
    print_info "Tag v$version has been created and pushed."
    print_info "View tags: https://github.com/modelingevolution/autoupdater-compose/tags"
}

# Run main function
main "$@"