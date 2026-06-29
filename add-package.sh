#!/bin/bash

# AutoUpdater - package registration engine (used by up-X.Y.Z.sh migrations)
# Adds (or replaces) a single Packages[] entry in appsettings.Production.json
# without clobbering existing packages. Idempotent. Invoked by migration scripts
# (e.g. up-1.0.79.sh) during the AutoUpdater self-update; not a manual deploy step.
#
# Usage: ./add-package.sh <app-name> <compose-git-url> [docker-auth] [docker-registry-url] [docker-compose-dir]

set -e

# Source logging library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"

init_logging

# Check parameters
if [ $# -lt 2 ] || [ $# -gt 5 ]; then
    echo "Usage: $0 <app-name> <compose-git-url> [docker-auth] [docker-registry-url] [docker-compose-dir]"
    echo "Example: $0 roma-matcher https://github.com/modelingevolution/roma-matcher-compose.git \"<harbor-auth>\" docker.modelingevolution.com"
    exit 1
fi

APP_NAME="$1"
GIT_COMPOSE_URL="$2"
DOCKER_AUTH="${3:-}"
DOCKER_REGISTRY_URL="${4:-}"
DOCKER_COMPOSE_DIR="${5:-./}"

# Validate Docker parameters - both must be provided or both empty (mirror install-updater.sh)
if [ -n "$DOCKER_AUTH" ] && [ -z "$DOCKER_REGISTRY_URL" ]; then
    log_error "docker-registry-url must be provided when docker-auth is specified"
    exit 1
fi
if [ -z "$DOCKER_AUTH" ] && [ -n "$DOCKER_REGISTRY_URL" ]; then
    log_error "docker-auth must be provided when docker-registry-url is specified"
    exit 1
fi

# Same configuration path install-updater.sh writes (override CONFIG_BASE for testing)
CONFIG_BASE="${CONFIG_BASE:-/var/docker/configuration}"
AUTOUPDATER_CONFIG="$CONFIG_BASE/autoupdater"
SETTINGS_FILE="$AUTOUPDATER_CONFIG/appsettings.Production.json"

REPOSITORY_LOCATION="/data/$APP_NAME"

# Ensure jq is present (mirror install.sh pattern)
if ! command -v jq &> /dev/null; then
    log_info "Installing jq"
    run_quiet "Updating package index" apt-get update
    run_quiet "Installing jq" apt-get install -y jq
fi

# Read existing settings or start from an empty object
if [ -f "$SETTINGS_FILE" ]; then
    if ! jq empty "$SETTINGS_FILE" 2>/dev/null; then
        log_error "Existing $SETTINGS_FILE is not valid JSON"
        exit 1
    fi
    BEFORE_COUNT=$(jq '(.Packages // []) | length' "$SETTINGS_FILE")
    INPUT_FILE="$SETTINGS_FILE"
else
    log_warn "$SETTINGS_FILE not found - creating a new configuration file"
    mkdir -p "$AUTOUPDATER_CONFIG"
    BEFORE_COUNT=0
    INPUT_FILE=""
fi

log_info "Registering package '$APP_NAME' at $REPOSITORY_LOCATION (current package count: $BEFORE_COUNT)"

# Merge: replace entry with the same RepositoryLocation, otherwise append.
# ComputerName and all other Packages entries are preserved.
TMP_FILE="$(mktemp "${SETTINGS_FILE}.XXXXXX")"
trap 'rm -f "$TMP_FILE"' EXIT

JQ_FILTER='
  .Packages = (.Packages // []) |
  {
    RepositoryLocation: $loc,
    RepositoryUrl: $url,
    DockerComposeDirectory: $dir,
    DockerAuth: $auth,
    DockerRegistryUrl: $registry
  } as $entry |
  if any(.Packages[]; .RepositoryLocation == $loc)
  then .Packages = (.Packages | map(if .RepositoryLocation == $loc then $entry else . end))
  else .Packages += [$entry]
  end
'

if [ -n "$INPUT_FILE" ]; then
    jq \
        --arg loc "$REPOSITORY_LOCATION" \
        --arg url "$GIT_COMPOSE_URL" \
        --arg dir "$DOCKER_COMPOSE_DIR" \
        --arg auth "$DOCKER_AUTH" \
        --arg registry "$DOCKER_REGISTRY_URL" \
        "$JQ_FILTER" "$INPUT_FILE" > "$TMP_FILE"
else
    jq -n \
        --arg loc "$REPOSITORY_LOCATION" \
        --arg url "$GIT_COMPOSE_URL" \
        --arg dir "$DOCKER_COMPOSE_DIR" \
        --arg auth "$DOCKER_AUTH" \
        --arg registry "$DOCKER_REGISTRY_URL" \
        "{} | $JQ_FILTER" > "$TMP_FILE"
fi

# Validate the result parses before swapping it in
if ! jq empty "$TMP_FILE" 2>/dev/null; then
    log_error "Generated configuration is not valid JSON - aborting, original file untouched"
    exit 1
fi

mv "$TMP_FILE" "$SETTINGS_FILE"
trap - EXIT

AFTER_COUNT=$(jq '(.Packages // []) | length' "$SETTINGS_FILE")
log_info "Package '$APP_NAME' registered (package count: $BEFORE_COUNT -> $AFTER_COUNT)"
log_info "AutoUpdater will clone $GIT_COMPOSE_URL into $REPOSITORY_LOCATION on its next cycle"
log_info "Configuration: $SETTINGS_FILE"
