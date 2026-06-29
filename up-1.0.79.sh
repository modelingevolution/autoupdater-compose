#!/bin/bash

# AutoUpdater migration v1.0.79
# Auto-registers the roma-matcher package on devices opted in for it.
#
# Run automatically by AutoUpdater during its own self-update (migration phase),
# in the working directory /var/docker/configuration/autoupdater. This script is
# best-effort and ADDITIVE: it MUST NOT fail the autoupdater self-update, so it
# always exits 0 (a non-zero exit would roll the whole self-update back).
#
# Opt-in / gating: a device registers roma-matcher only if ROMA_MATCHER_DOCKER_AUTH
# is available (host env or the autoupdater .env). Seed it only on machines that
# should run roma-matcher (production rocket-welder hosts).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"
init_logging

ROMA_MATCHER_REPO="https://github.com/modelingevolution/roma-matcher-compose.git"
ROMA_MATCHER_REGISTRY="docker.modelingevolution.com"

# Device-local Harbor pull credential (base64 user:password). Never committed.
# Fall back to the autoupdater .env if not already exported in the host environment.
if [ -z "${ROMA_MATCHER_DOCKER_AUTH:-}" ] && [ -f "$SCRIPT_DIR/.env" ]; then
    ROMA_MATCHER_DOCKER_AUTH="$(grep -E '^ROMA_MATCHER_DOCKER_AUTH=' "$SCRIPT_DIR/.env" | tail -1 | cut -d= -f2-)"
    # Strip one pair of surrounding quotes operators often add in .env (base64 padding '=' is preserved by cut -f2-)
    ROMA_MATCHER_DOCKER_AUTH="${ROMA_MATCHER_DOCKER_AUTH%\"}"; ROMA_MATCHER_DOCKER_AUTH="${ROMA_MATCHER_DOCKER_AUTH#\"}"
    ROMA_MATCHER_DOCKER_AUTH="${ROMA_MATCHER_DOCKER_AUTH%\'}"; ROMA_MATCHER_DOCKER_AUTH="${ROMA_MATCHER_DOCKER_AUTH#\'}"
fi

if [ -z "${ROMA_MATCHER_DOCKER_AUTH:-}" ]; then
    log_warn "ROMA_MATCHER_DOCKER_AUTH not set - skipping roma-matcher auto-registration on this device"
    log_warn "This device is treated as NOT opted in for roma-matcher."
    log_warn "To register it later: seed ROMA_MATCHER_DOCKER_AUTH in $SCRIPT_DIR/.env then run:"
    log_warn "  sudo $SCRIPT_DIR/add-package.sh roma-matcher $ROMA_MATCHER_REPO \"\$ROMA_MATCHER_DOCKER_AUTH\" $ROMA_MATCHER_REGISTRY"
    log_warn "Exiting 0 so the AutoUpdater self-update is not rolled back."
    exit 0
fi

log_info "Auto-registering roma-matcher package (migration v1.0.79)"
if "$SCRIPT_DIR/add-package.sh" roma-matcher "$ROMA_MATCHER_REPO" "$ROMA_MATCHER_DOCKER_AUTH" "$ROMA_MATCHER_REGISTRY"; then
    log_info "roma-matcher registered - AutoUpdater will clone and deploy it on its next cycle"
else
    log_error "add-package.sh failed for roma-matcher - autoupdater self-update is NOT rolled back"
    log_error "Inspect the error above and re-run add-package.sh manually once resolved"
fi

exit 0
