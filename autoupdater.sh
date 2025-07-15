#!/bin/bash

# AutoUpdater API Client Script
# Generated from OpenAPI specification

set -e

# Default configuration
AUTOUPDATER_BASE_URL="${AUTOUPDATER_BASE_URL:-http://localhost:8080}"
AUTOUPDATER_API_BASE="$AUTOUPDATER_BASE_URL/api"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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
    if [ "$AUTOUPDATER_DEBUG" = "true" ]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

# Help function
show_help() {
    cat << EOF
AutoUpdater API Client

USAGE:
    $0 <command> [options]

COMMANDS:
    health                      Check AutoUpdater health
    packages                    List all configured packages
    status <package>            Get upgrade status for a package
    update <package>            Trigger update for a specific package
    update-all                  Trigger updates for all packages
    debug                       Test API connectivity

ENVIRONMENT VARIABLES:
    AUTOUPDATER_BASE_URL       Base URL for AutoUpdater (default: http://localhost:8080)
    AUTOUPDATER_DEBUG          Enable debug output (true/false)

EXAMPLES:
    $0 health
    $0 packages
    $0 status rocket-welder
    $0 update rocket-welder
    $0 update-all

EOF
}

# API call wrapper
api_call() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    
    local url="$AUTOUPDATER_API_BASE$endpoint"
    log_debug "Making $method request to: $url"
    
    local curl_args=(-s)
    
    if [ "$method" = "POST" ]; then
        curl_args+=(-X POST)
        if [ -n "$data" ]; then
            curl_args+=(-H "Content-Type: application/json" -d "$data")
        fi
    fi
    
    local response
    local http_code
    
    response=$(curl "${curl_args[@]}" -w "\n%{http_code}" "$url")
    http_code=$(echo "$response" | tail -n1)
    response=$(echo "$response" | sed '$d')
    
    log_debug "HTTP Status: $http_code"
    log_debug "Response: $response"
    
    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        echo "$response"
        return 0
    elif [ "$http_code" = "404" ]; then
        log_error "Package not found"
        return 1
    else
        log_error "API call failed with status $http_code"
        echo "$response" | jq -r '.title // .error // .' 2>/dev/null || echo "$response"
        return 1
    fi
}

# Command implementations
cmd_health() {
    log_info "Checking AutoUpdater health..."
    if api_call GET "/health"; then
        log_info "AutoUpdater is healthy"
    else
        log_error "Health check failed"
        return 1
    fi
}

cmd_packages() {
    log_info "Getting configured packages..."
    api_call GET "/packages"
}

cmd_status() {
    local package_name="$1"
    if [ -z "$package_name" ]; then
        log_error "Package name is required"
        echo "Usage: $0 status <package-name>"
        return 1
    fi
    
    log_info "Getting upgrade status for package: $package_name"
    api_call GET "/upgrades/$package_name"
}

cmd_update() {
    local package_name="$1"
    if [ -z "$package_name" ]; then
        log_error "Package name is required"
        echo "Usage: $0 update <package-name>"
        return 1
    fi
    
    log_info "Triggering update for package: $package_name"
    api_call POST "/update/$package_name"
}

cmd_update_all() {
    log_info "Triggering updates for all packages..."
    api_call POST "/update-all"
}

cmd_debug() {
    log_info "Testing API connectivity..."
    if api_call GET "/debug"; then
        log_info "API connectivity test successful"
    else
        log_error "API connectivity test failed"
        return 1
    fi
}

# Main command dispatcher
main() {
    local command="$1"
    shift
    
    case "$command" in
        health)
            cmd_health "$@"
            ;;
        packages)
            cmd_packages "$@"
            ;;
        status)
            cmd_status "$@"
            ;;
        update)
            cmd_update "$@"
            ;;
        update-all)
            cmd_update_all "$@"
            ;;
        debug)
            cmd_debug "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        "")
            log_error "No command provided"
            show_help
            return 1
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            return 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"