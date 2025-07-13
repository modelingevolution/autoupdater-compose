# AutoUpdater Production Deployment

Production deployment configuration for [ModelingEvolution.AutoUpdater](https://github.com/modelingevolution/autoupdater).

> **Quick Install**: See [INSTALL.md](INSTALL.md) for a simplified installation guide.

## Quick Start

### Automated Installation (Recommended)

Use the installation script for a complete setup:

```bash
# Download and run the installation script
wget https://raw.githubusercontent.com/modelingevolution/autoupdater-compose/master/install.sh
chmod +x install.sh

# Run with your application details
sudo ./install.sh <app-name> <git-compose-url> <computer-name> [docker-auth] [docker-registry-url]

# Example for RocketWelder:
sudo ./install.sh rocket-welder https://github.com/modelingevolution/rocketwelder-compose.git RESRV-AI
```

The script will:
1. Install Docker and Docker Compose (if not present)
2. Install VPN (OpenVPN for Ubuntu 20.04, WireGuard for Ubuntu 22.04+)
3. Create the `deploy` user and add it to the docker group
4. Set up the directory structure at `/var/docker/configuration/`
5. Generate SSH keys for secure communication
6. Configure the autoupdater to manage both itself and your application
7. Start the autoupdater container

### Manual Installation

If you prefer manual setup:

1. **Create deploy user:**
   ```bash
   sudo useradd -m -s /bin/bash deploy
   sudo usermod -aG docker deploy
   ```

2. **Create directory structure:**
   ```bash
   sudo mkdir -p /var/docker/configuration/autoupdater/.ssh
   sudo mkdir -p /var/docker/configuration/repositories
   sudo chown -R deploy:deploy /var/docker/configuration
   ```

3. **Generate SSH keys:**
   ```bash
   sudo -u deploy ssh-keygen -t rsa -b 4096 -f /var/docker/configuration/autoupdater/.ssh/id_rsa -N ""
   ```

4. **Create configuration files:**
   - Copy `docker-compose.yml` to `/var/docker/configuration/autoupdater/`
   - Copy and customize `appsettings.Production.json`
   - Create `.env` file with your settings

5. **Start the autoupdater:**
   ```bash
   cd /var/docker/configuration/autoupdater
   sudo -u deploy docker-compose up -d
   ```

> **Note**: For manual installation, you'll need to install Docker, Docker Compose, and VPN separately. The automated script handles all prerequisites.

## Configuration Structure

### StdPackages vs Packages

The configuration separates packages into two categories:

- **StdPackages**: System-critical packages including the autoupdater itself
  - The autoupdater monitors its own repository here
  
- **Packages**: Application packages managed by the autoupdater
  - Your applications (like RocketWelder) go here
  - Updated after StdPackages are up-to-date

### Example Configuration

```json
{
  "StdPackages": [
    {
      "RepositoryLocation": "/data/autoupdater",
      "RepositoryUrl": "https://github.com/modelingevolution/autoupdater-compose.git",
      "DockerComposeDirectory": "./"
    }
  ],
  "Packages": [
    {
      "RepositoryLocation": "/data/rocket-welder",
      "RepositoryUrl": "https://github.com/modelingevolution/rocket-welder-compose.git",
      "DockerComposeDirectory": "./"
    }
  ]
}
```

## Installation Script Parameters

The installation script accepts three required parameters and two optional parameters:

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `app-name` | Name of your application (used in repository paths) | `rocket-welder` |
| `git-compose-url` | Git repository URL for your application's compose configuration | `https://github.com/modelingevolution/rocketwelder-compose.git` |
| `computer-name` | Unique identifier for this deployment/computer | `RESRV-AI` |

### Optional Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `docker-auth` | Docker registry Personal Access Token (PAT) for private registries | `ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx` |
| `docker-registry-url` | Docker registry URL (without trailing slash) | `ghcr.io/myorg` |

### Usage Syntax

```bash
# Basic usage (public registries only)
sudo ./install.sh [--json] <app-name> <git-compose-url> <computer-name>

# With Docker authentication (for private registries)
sudo ./install.sh [--json] <app-name> <git-compose-url> <computer-name> [docker-auth] [docker-registry-url]
```

### Example Usage

```bash
# For RocketWelder on RESRV-AI (public registry)
sudo ./install.sh rocket-welder https://github.com/modelingevolution/rocketwelder-compose.git RESRV-AI

# For a private registry with authentication
sudo ./install.sh rocket-welder https://github.com/modelingevolution/rocketwelder-compose.git RESRV-AI ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx ghcr.io/modelingevolution

# With JSON output for automation
sudo ./install.sh --json my-app https://github.com/myorg/my-app-compose.git PROD-001
```

### Docker Registry Authentication

When `docker-auth` and `docker-registry-url` are provided:

1. **Docker Login**: The script automatically logs into the specified Docker registry using the provided PAT
2. **Configuration Update**: The registry URL and authentication are added to the application configuration
3. **Image Access**: Enables pulling private Docker images from authenticated registries like GitHub Container Registry (GHCR)

**Security Note**: The Docker authentication token is used only for login and stored in the configuration for the AutoUpdater to access private registries. Ensure your PAT has only the necessary permissions (typically `read:packages`).

## Directory Structure

After installation, the following structure is created:

```
/var/docker/configuration/
├── autoupdater/ (GIT VERSIONED)
│   ├── docker-compose.yml           # Git compose file
│   ├── appsettings.Production.json  # Git configuration
│   └── .env                         # Environment variables (exploded from GIT with gitignore)
└── <app-name>/                      # Your application repository (maps to /data/<app-name>)
/var/docker/data/ (NO GIT)
├── autoupdater/app
│   ├── appsettings.override.json    # Autoupdater computer specific configuration for this installation
│   └── .ssh/                        # SSH keys 
│       ├── id_rsa                   # Private key (auto-generated)
│       └── id_rsa.pub               # Public key
└── <app-name>/<container-name>      # Your app specific data folder for this installation for a container defined within compose
    └── appsettings.override.json    # Additional configuration specific for this installation.
/var/data (NO GIT)                   # If present, second partition for user-data that would be used by containers. Use-case ? Recording for RocketWelder
├── <app-name>/<container-name>      # For example rocketwelder/app
│   └── <specific folder defined in docker-compose from the app>
```

**Important**: All Git repositories must be owned by `root:root` for the container to perform Git operations successfully.

### Key Paths

- **Configuration Base**: `/var/docker/configuration/`
- **AutoUpdater Config**: `/var/docker/configuration/autoupdater/`
- **SSH Keys**: `/var/docker/data/autoupdater/.ssh/`
- **Repositories**: `/var/docker/configuration/`

## Security Considerations

1. **SSH Keys**: 
   - Store SSH private keys securely
   - Use passphrase-protected keys for additional security
   - Limit SSH key permissions to deployment operations only

2. **Docker Socket**: 
   - The autoupdater requires access to Docker socket
   - Ensure proper host security measures are in place

3. **Network Security**:
   - Use HTTPS for all Git repository URLs
   - Configure firewall rules appropriately
   - Consider using VPN for SSH connections

## Monitoring

- Access the web UI at: http://localhost:8080
- Check logs: `docker-compose logs -f`
- Monitor update status via the API endpoints

## Troubleshooting

### SSH Connection Issues
```bash
# Test SSH connectivity
docker-compose exec autoupdater ssh -i /data/ssh/id_rsa deploy@172.17.0.1 echo "Connected"

# Check SSH key permissions
docker-compose exec autoupdater ls -la /data/ssh/
```

### Repository Access Issues
```bash
# Verify repository clone
docker-compose exec autoupdater ls -la /data/

# Check Git connectivity
docker-compose exec autoupdater git ls-remote https://github.com/modelingevolution/autoupdater-compose.git

# Fix Git ownership issues (if repositories show "dubious ownership" errors)
sudo chown -R root:root /var/docker/configuration/autoupdater
sudo chown -R root:root /var/docker/configuration/rocket-welder

# Test Git operations from inside container
docker exec autoupdater bash -c "cd /data/autoupdater && git pull"
```

## Updates

The autoupdater will automatically update itself when new versions are tagged in this repository. To trigger a manual update:

1. Tag a new version in this repository
2. The autoupdater will detect and apply the update within its polling interval

## License

MIT License - See the main [autoupdater repository](https://github.com/modelingevolution/autoupdater) for details.