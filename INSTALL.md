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
automatic path, no manual per-device registration. The `up-1.0.79.sh` migration runs during
the autoupdater's own self-update and registers roma-matcher on machines that have opted in
via a seeded credential. AutoUpdater then clones and deploys it.

1. **Seed the credential** on each machine that should run roma-matcher — add
   `ROMA_MATCHER_DOCKER_AUTH=<harbor-auth>` to
   `/var/docker/configuration/autoupdater/.env`. This variable is the **opt-in gate**:
   machines without it are skipped. Seed it **before** the next step (the migration runs
   once per device).
2. **Cut an autoupdater-compose release:** `./release.sh 1.0.79` (creates and pushes tag
   `v1.0.79`).
3. **Trigger the self-update on each target device** — the `:8080` UI "Update" on the
   `autoupdater` package, or `./autoupdater.sh update autoupdater`. The `up-1.0.79.sh`
   migration runs automatically and registers roma-matcher.
4. **Deploy roma-matcher:** `./autoupdater.sh update-all` (or `./autoupdater.sh update
   roma-matcher`).

> **Detection caveat:** there is **no background poll** — a device only sees the new tag when
> AutoUpdater restarts or when its `:8080` UI / API is queried; applying it is an **explicit
> trigger**, so the operator triggers the self-update per device. Also seed the credential
> **before** triggering: the migration runs once (tracked in `deployment.state.json`) and a
> device updated before the variable is set won't retry. The migration always exits 0 and
> never rolls back the autoupdater self-update.

### Harbor credential (`<harbor-auth>`)

`roma-matcher` images are **private** on Harbor at
`docker.modelingevolution.com/roma-matcher/roma-matcher`. `ROMA_MATCHER_DOCKER_AUTH` is the
**base64 encoding of `username:password`** (a Docker registry auth token — same value Docker
stores in `~/.docker/config.json`), from a Harbor robot account with pull access to
`roma-matcher/roma-matcher`. Build it with:

```bash
# Replace with the real Harbor robot account name + token (from Harbor → Robot Accounts)
echo -n 'robot$roma-matcher+pull:HARBOR_ROBOT_TOKEN' | base64
```

Do **not** commit the real token anywhere — use a `<harbor-auth>` placeholder. See
[.env.example](.env.example) and the project
[README](README.md#deploying-roma-matcher-automatic-via-self-update-migration) for details.

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