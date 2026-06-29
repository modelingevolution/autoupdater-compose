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

## Deploying an Additional Package (Co-located)

`install.sh` / `install-updater.sh` provision a machine with a **single** application
package — they overwrite `appsettings.Production.json` with one `Packages[]` entry. To
run a second service on a machine that already runs one (e.g. deploying `roma-matcher`
next to `rocket-welder`), use `add-package.sh`, which adds or replaces a single package
entry **without clobbering** the existing ones.

```bash
# On a production machine that already runs rocket-welder, add roma-matcher:
sudo ./add-package.sh roma-matcher \
  https://github.com/modelingevolution/roma-matcher-compose.git \
  "<harbor-auth>" docker.modelingevolution.com
```

Parameters: `<app-name> <compose-git-url> [docker-auth] [docker-registry-url] [docker-compose-dir]`
(`docker-compose-dir` defaults to `./`).

The script is **idempotent** — re-running with the same arguments is a no-op; running it
with a changed auth/registry replaces that package's entry in place. `ComputerName` and
all other packages are preserved. AutoUpdater clones the package repository into
`/data/<app-name>` on its next cycle, so `add-package.sh` only writes configuration.

For a **standalone** machine (roma-matcher only, no rocket-welder), use the normal
installer instead — one package is all it writes:

```bash
sudo ./install-updater.sh roma-matcher \
  https://github.com/modelingevolution/roma-matcher-compose.git <computer-name> \
  "<harbor-auth>" docker.modelingevolution.com <autoupdater-version>
```

### Harbor / private registry authentication (`<harbor-auth>`)

`roma-matcher` images are **private** on Harbor at
`docker.modelingevolution.com/roma-matcher/roma-matcher`, so registration needs both
`DockerRegistryUrl=docker.modelingevolution.com` and a pull credential.

`docker-auth` is the **base64 encoding of `username:password`** (a Docker registry auth
token — same value Docker stores in `~/.docker/config.json`). Build it from a Harbor
robot account:

```bash
# Replace with the real Harbor robot account name + token (from Harbor → Robot Accounts)
echo -n 'robot$roma-matcher+pull:HARBOR_ROBOT_TOKEN' | base64
```

Pass that string as `<harbor-auth>`. Do **not** commit the real token anywhere; the
credential comes from the Harbor project's robot account with pull permission on
`roma-matcher/roma-matcher`.

### Automatic fleet-wide rollout (recommended for many devices)

Instead of running `add-package.sh` on every machine, let AutoUpdater register roma-matcher
during its **self-update** via the `up-1.0.79.sh` migration:

1. **Seed the credential** on each machine that should run roma-matcher — add
   `ROMA_MATCHER_DOCKER_AUTH=<harbor-auth>` to
   `/var/docker/configuration/autoupdater/.env`. This variable is the **opt-in gate**:
   machines without it are skipped.
2. **Cut an autoupdater-compose release:** `./release.sh 1.0.79`.
3. Devices self-update, run the migration, and auto-register roma-matcher (opted-in only).
   AutoUpdater then clones and deploys it.

> Seed the credential **before** the release reaches a device. The migration runs once
> (tracked in `deployment.state.json`); a device that updates before the variable is set
> won't retry — register it later with `add-package.sh`. The migration always exits 0 and
> never rolls back the autoupdater self-update.

See the project [README](README.md#automatic-fleet-wide-registration-migration-scripts) for
the full mechanism.

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