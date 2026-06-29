#!/bin/bash

# AutoUpdater migration v1.0.79 — registers roma-matcher on GPU-capable devices.
# Best-effort and additive: always exits 0, since a non-zero exit rolls back the whole
# autoupdater self-update. Gate: only devices with the NVIDIA docker runtime register it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"
init_logging

ROMA_MATCHER_REPO="https://github.com/modelingevolution/roma-matcher-compose.git"

# True when the NVIDIA container runtime is registered with Docker (so `runtime: nvidia` works).
has_nvidia_runtime() {
    command -v docker >/dev/null 2>&1 || return 1
    if docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"'; then
        return 0
    fi
    if docker info 2>/dev/null | grep -qiE 'Runtimes:[[:space:]].*nvidia'; then
        return 0
    fi
    return 1
}

if ! has_nvidia_runtime; then
    log_info "No NVIDIA docker runtime detected - skipping roma-matcher on this device"
    log_info "Exiting 0 so the AutoUpdater self-update is not rolled back."
    exit 0
fi

log_info "NVIDIA docker runtime present - registering roma-matcher (migration v1.0.79)"
if "$SCRIPT_DIR/add-package.sh" roma-matcher "$ROMA_MATCHER_REPO"; then
    log_info "roma-matcher registered - AutoUpdater will clone and deploy it on its next cycle"
else
    log_error "add-package.sh failed for roma-matcher - autoupdater self-update is NOT rolled back"
    log_error "Inspect the error above and re-run add-package.sh manually once resolved"
fi

exit 0
