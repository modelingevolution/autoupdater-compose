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