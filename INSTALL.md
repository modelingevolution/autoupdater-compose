# AutoUpdater Installation Guide

## One-Command Installation

```bash
wget https://raw.githubusercontent.com/modelingevolution/autoupdater-compose/master/install.sh
chmod +x install.sh
sudo ./install.sh <app-name> <git-compose-url> <computer-name> [docker-auth] [docker-registry-url]
```

## Examples

```bash
# RocketWelder on RESRV-AI (public registry)
sudo ./install.sh rocket-welder https://github.com/modelingevolution/rocketwelder-compose.git RESRV-AI

# Custom app with private registry authentication
sudo ./install.sh my-app https://github.com/myorg/my-app-compose.git PROD-001 ghp_token123 ghcr.io/myorg

# With JSON output for automation
sudo ./install.sh --json my-app https://github.com/myorg/my-app-compose.git PROD-001
```

## Parameters

- `app-name`: Your application name (e.g., `rocket-welder`)
- `git-compose-url`: Git repository URL for your app's Docker Compose configuration
- `computer-name`: Unique identifier for this deployment (e.g., `RESRV-AI`)
- `docker-auth` (optional): Docker registry PAT token for private registries
- `docker-registry-url` (optional): Docker registry URL (e.g., `ghcr.io/myorg`)

## Deploying roma-matcher (Automatic Self-Update Migration)

roma-matcher is deployed through the AutoUpdater **self-update migration** — a single
automatic path, no manual per-device registration and **no per-package credential**. The
`up-1.0.79.sh` migration runs during the autoupdater's own self-update and registers
roma-matcher **on GPU-capable devices only**. AutoUpdater then clones and deploys it.

1. **Merge** this PR to `master`.
2. **Cut an autoupdater-compose release:** `./release.sh 1.0.79` (creates and pushes tag
   `v1.0.79`).
3. **Trigger the self-update on each target device** — the `:8080` UI "Update" on the
   `autoupdater` package, or `./autoupdater.sh update autoupdater`. The `up-1.0.79.sh`
   migration runs automatically and registers roma-matcher on hosts with the NVIDIA docker
   runtime.
4. **Deploy roma-matcher:** `./autoupdater.sh update-all` (or `./autoupdater.sh update
   roma-matcher`).

**GPU gate:** roma-matcher's compose needs the **NVIDIA docker runtime** (`runtime: nvidia`).
The migration registers it only where that runtime is registered with Docker; devices without
a GPU are skipped.

> **Detection caveat:** there is **no background poll** — a device only sees the new tag when
> AutoUpdater restarts or when its `:8080` UI / API is queried; applying it is an **explicit
> trigger**, so the operator triggers the self-update per device. The migration runs once
> (tracked in `deployment.state.json`), always exits 0, and never rolls back the self-update.

See the project
[README](README.md#deploying-roma-matcher-automatic-via-self-update-migration) for the full
mechanism.

## What It Does

1. Creates `deploy` user with docker access
2. Sets up `/var/docker/configuration/` directory structure
3. Git clones autoupdater-compose repository to `/var/docker/configuration/autoupdater`
4. Generates SSH keys for deployments
5. Configures autoupdater to manage:
   - **Itself** (StdPackages) at `/data/autoupdater`
   - **Your app** (Packages) at `/data/<app-name>`
6. Starts the autoupdater container

## Result

- Web UI: http://localhost:8080
- Config: `/var/docker/configuration/autoupdater/`
- Logs: `docker logs -f autoupdater`

The autoupdater will automatically pull and deploy updates when new Git tags are detected.

## Troubleshooting

### Installation Stuck at Health Check

If the installation script gets stuck during health checks:

```bash
# Check if AutoUpdater is running
docker ps | grep autoupdater

# Test health endpoint manually
curl http://localhost:8080/health

# Check autoupdater logs
docker logs autoupdater

# Common issue: Health endpoint should be /health, not /api/health
# This was fixed in AutoUpdater version 1.0.32
```

### ACR Authentication Issues

For Azure Container Registry authentication:

```bash
# Verify Docker login worked
docker images | grep rocketwelder.azurecr.io

# Test ACR connectivity
docker pull rocketwelder.azurecr.io/rocketwelder:latest

# Note: Use repository-scoped tokens with username "RESRV-AI-token"
# not the registry name as username
```