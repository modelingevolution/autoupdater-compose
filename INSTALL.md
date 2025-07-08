# AutoUpdater Installation Guide

## One-Command Installation

```bash
wget https://raw.githubusercontent.com/modelingevolution/autoupdater-compose/main/installation.sh
sudo ./installation.sh <app-name> <git-compose-url> <computer-name>
```

## Examples

```bash
# RocketWelder on POC-400
sudo ./installation.sh rocket-welder https://github.com/modelingevolution/rocketwelder-compose.git POC-400

# Custom app
sudo ./installation.sh my-app https://github.com/myorg/my-app-compose.git PROD-001
```

## What It Does

1. Creates `deploy` user with docker access
2. Sets up `/var/docker/configuration/` directory structure
3. Generates SSH keys for deployments
4. Configures autoupdater to manage:
   - **Itself** (StdPackages)
   - **Your app** (Packages)
5. Starts the autoupdater container

## Result

- Web UI: http://localhost:8080
- Config: `/var/docker/configuration/autoupdater/`
- Logs: `docker logs -f autoupdater`

The autoupdater will automatically pull and deploy updates when new Git tags are detected.