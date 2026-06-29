#!/bin/bash

# AutoUpdater migration v1.0.79
# Auto-registers the roma-matcher package on GPU-capable devices.
#
# Run automatically by AutoUpdater during its own self-update (migration phase), on the host
# via SSH, in the working directory /var/docker/configuration/autoupdater. This script is
# best-effort and ADDITIVE: it MUST NOT fail the autoupdater self-update, so it always exits 0
# (a non-zero exit would roll the whole self-update back).
#
# Gate: roma-matcher's compose requires the NVIDIA docker runtime (runtime: nvidia). Only
# devices where that runtime is registered with Docker register roma-matcher; the rest skip.
#
# Auth: no per-package credential. roma-matcher lives on the same Harbor registry as
# rocket-welder, and the device already performed a host-level
# `docker login docker.modelingevolution.com` at rocket-welder install (install.sh), so the
# existing login authorizes the pull.

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
