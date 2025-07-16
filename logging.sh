#!/bin/bash

# Shared logging library for AutoUpdater scripts
# Provides consistent logging across all bash scripts
# 
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
#   init_logging [--verbose|-v]
#
# Environment Variables:
#   VERBOSE - Set to "true" to enable verbose output
#   JSON_OUTPUT - Set to "true" for JSON formatted output

# Initialize verbose mode from environment or arguments
init_logging() {
    # Check environment variable first
    VERBOSE="${VERBOSE:-false}"
    JSON_OUTPUT="${JSON_OUTPUT:-false}"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose)
                VERBOSE="true"
                shift
                ;;
            --json)
                JSON_OUTPUT="true"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    export VERBOSE
    export JSON_OUTPUT
}

# Color codes (disabled in JSON mode)
set_colors() {
    if [ "$JSON_OUTPUT" = "true" ]; then
        RED=""
        GREEN=""
        YELLOW=""
        BLUE=""
        NC=""
    else
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        NC='\033[0m' # No Color
    fi
}

# Initialize colors
set_colors

# Core logging functions
log_info() {
    local message="$1"
    local step="${2:-}"
    
    if [ "$JSON_OUTPUT" = "true" ]; then
        if [ -n "$step" ]; then
            echo "{\"status\":\"info\",\"step\":\"$step\",\"message\":\"$message\"}"
        else
            echo "{\"status\":\"info\",\"message\":\"$message\"}"
        fi
    else
        echo -e "${GREEN}[INFO]${NC} $message"
    fi
}

log_warn() {
    local message="$1"
    local step="${2:-}"
    
    if [ "$JSON_OUTPUT" = "true" ]; then
        if [ -n "$step" ]; then
            echo "{\"status\":\"warn\",\"step\":\"$step\",\"message\":\"$message\"}"
        else
            echo "{\"status\":\"warn\",\"message\":\"$message\"}"
        fi
    else
        echo -e "${YELLOW}[WARN]${NC} $message"
    fi
}

log_error() {
    local message="$1"
    local step="${2:-}"
    
    if [ "$JSON_OUTPUT" = "true" ]; then
        if [ -n "$step" ]; then
            echo "{\"status\":\"error\",\"step\":\"$step\",\"message\":\"$message\"}"
        else
            echo "{\"status\":\"error\",\"message\":\"$message\"}"
        fi
    else
        echo -e "${RED}[ERROR]${NC} $message" >&2
    fi
}

log_debug() {
    if [ "$VERBOSE" = "true" ]; then
        local message="$1"
        
        if [ "$JSON_OUTPUT" = "true" ]; then
            echo "{\"status\":\"debug\",\"message\":\"$message\"}"
        else
            echo -e "${BLUE}[DEBUG]${NC} $message"
        fi
    fi
}

# Execute command with output control
exec_cmd() {
    local description="$1"
    shift
    
    log_debug "Executing: $*"
    
    if [ "$VERBOSE" = "true" ]; then
        "$@"
    else
        "$@" >/dev/null 2>&1
    fi
    
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_debug "Command failed with exit code: $exit_code"
    fi
    
    return $exit_code
}

# Execute command and capture output for conditional display
run_with_output() {
    local description="$1"
    shift
    
    log_info "$description"
    
    local temp_file=$(mktemp)
    local exit_code
    
    # Execute command and capture output
    if [ "$VERBOSE" = "true" ]; then
        # In verbose mode, show output in real-time
        "$@" 2>&1 | tee "$temp_file"
        exit_code=${PIPESTATUS[0]}
    else
        # In quiet mode, capture output
        "$@" > "$temp_file" 2>&1
        exit_code=$?
    fi
    
    # On error, always show output
    if [ $exit_code -ne 0 ] && [ "$VERBOSE" != "true" ]; then
        log_error "Command failed: $*"
        cat "$temp_file"
    fi
    
    rm -f "$temp_file"
    return $exit_code
}

# Execute command quietly unless verbose
run_quiet() {
    local description="$1"
    shift
    
    if [ -n "$description" ]; then
        log_info "$description"
    fi
    
    if [ "$VERBOSE" = "true" ]; then
        "$@"
    else
        "$@" >/dev/null 2>&1
    fi
}

# Execute command and only show stderr on error
run_capture_errors() {
    local description="$1"
    shift
    
    if [ -n "$description" ]; then
        log_info "$description"
    fi
    
    local error_file=$(mktemp)
    local exit_code
    
    if [ "$VERBOSE" = "true" ]; then
        "$@"
        exit_code=$?
    else
        "$@" 2>"$error_file" >/dev/null
        exit_code=$?
        
        if [ $exit_code -ne 0 ]; then
            log_error "Command failed: $*"
            cat "$error_file" >&2
        fi
    fi
    
    rm -f "$error_file"
    return $exit_code
}

# Special handler for Docker operations
docker_quiet() {
    if [ "$VERBOSE" = "true" ]; then
        docker "$@"
    else
        # Docker commands with progress suppression
        case "$1" in
            pull)
                docker "$@" --quiet
                ;;
            build)
                docker "$@" --quiet
                ;;
            compose)
                # Handle docker-compose commands
                shift
                if [ "$1" = "up" ]; then
                    docker compose up --quiet-pull "$@"
                else
                    docker compose "$@"
                fi
                ;;
            *)
                docker "$@" 2>&1 | grep -v "WARNING! Your password will be stored unencrypted" || true
                ;;
        esac
    fi
}

# Special handler for apt-get
apt_quiet() {
    if [ "$VERBOSE" = "true" ]; then
        apt-get "$@"
    else
        DEBIAN_FRONTEND=noninteractive apt-get -qq "$@" >/dev/null 2>&1
    fi
}

# Special handler for git operations
git_quiet() {
    if [ "$VERBOSE" = "true" ]; then
        git "$@"
    else
        git "$@" --quiet 2>&1 | grep -v "Cloning into" || true
    fi
}

# Progress indicator for long operations (only in non-verbose mode)
with_progress() {
    local description="$1"
    shift
    
    if [ "$VERBOSE" = "true" ] || [ "$JSON_OUTPUT" = "true" ]; then
        "$@"
    else
        log_info "$description"
        "$@" &
        local pid=$!
        
        while kill -0 $pid 2>/dev/null; do
            echo -n "."
            sleep 1
        done
        echo " done"
        
        wait $pid
    fi
}