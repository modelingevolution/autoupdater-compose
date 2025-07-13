#!/bin/bash

# Update Checksums Script
# This script generates installation.sh from installation.template
# by replacing placeholders with actual SHA256 checksums of dependent scripts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/install.template"
OUTPUT_FILE="$SCRIPT_DIR/install.sh"
CHECKSUMS_FILE="$SCRIPT_DIR/checksums.txt"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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

# Check if template exists
if [ ! -f "$TEMPLATE_FILE" ]; then
    log_error "Template file not found: $TEMPLATE_FILE"
    exit 1
fi

log_info "Generating checksums for dependent scripts..."

# Calculate checksums for all dependent scripts
INSTALL_UPDATER_CHECKSUM=""
if [ -f "$SCRIPT_DIR/install-updater.sh" ]; then
    INSTALL_UPDATER_CHECKSUM=$(sha256sum "$SCRIPT_DIR/install-updater.sh" | cut -d' ' -f1)
    log_info "install-updater.sh checksum: $INSTALL_UPDATER_CHECKSUM"
else
    log_error "install-updater.sh not found!"
    exit 1
fi

# Update checksums.txt file
log_info "Updating $CHECKSUMS_FILE..."
echo "# SHA256 checksums for dependent scripts" > "$CHECKSUMS_FILE"
echo "# Generated on $(date)" >> "$CHECKSUMS_FILE"
echo "" >> "$CHECKSUMS_FILE"
echo "$INSTALL_UPDATER_CHECKSUM  install-updater.sh" >> "$CHECKSUMS_FILE"

log_info "Generating $OUTPUT_FILE from template..."

# Replace placeholders in template
sed -e "s/{{INSTALL_UPDATER_CHECKSUM}}/$INSTALL_UPDATER_CHECKSUM/g" \
    "$TEMPLATE_FILE" > "$OUTPUT_FILE"

# Make the output file executable
chmod +x "$OUTPUT_FILE"

log_info "Successfully generated $OUTPUT_FILE with updated checksums"

# Verify the generated file
if [ -f "$OUTPUT_FILE" ]; then
    # Check if all placeholders were replaced
    if grep -q "{{.*}}" "$OUTPUT_FILE"; then
        log_warn "Warning: Some placeholders may not have been replaced in $OUTPUT_FILE"
        grep "{{.*}}" "$OUTPUT_FILE" || true
    else
        log_info "All placeholders successfully replaced"
    fi
else
    log_error "Failed to generate $OUTPUT_FILE"
    exit 1
fi

log_info "Checksum update completed successfully!"