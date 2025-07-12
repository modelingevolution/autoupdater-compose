# AutoUpdater Installation Guide

## One-Command Installation

```bash
wget https://raw.githubusercontent.com/modelingevolution/autoupdater-compose/master/installation.sh
chmod +x installation.sh
sudo ./installation.sh <app-name> <git-compose-url> <computer-name>
```

## Examples

```bash
# RocketWelder on RESRV-AI
sudo ./installation.sh rocket-welder https://github.com/modelingevolution/rocketwelder-compose.git RESRV-AI

# Custom app
sudo ./installation.sh my-app https://github.com/myorg/my-app-compose.git PROD-001
```

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