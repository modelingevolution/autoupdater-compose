# AutoUpdater Production Deployment

Production deployment configuration for [ModelingEvolution.AutoUpdater](https://github.com/modelingevolution/autoupdater).

## Quick Start

### Automated Installation (Recommended)

Use the installation script for a complete setup:

```bash
# Download and run the installation script
wget https://raw.githubusercontent.com/modelingevolution/autoupdater-compose/main/installation.sh
chmod +x installation.sh

# Run with your application details
sudo ./installation.sh <app-name> <git-compose-url> <computer-name>

# Example for RocketWelder:
sudo ./installation.sh rocket-welder https://github.com/modelingevolution/rocketwelder-compose.git POC-400
```

The script will:
1. Create the `deploy` user and add it to the docker group
2. Set up the directory structure at `/var/docker/configuration/`
3. Generate SSH keys for secure communication
4. Configure the autoupdater to manage both itself and your application
5. Start the autoupdater container

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

## Configuration Structure

### StdPackages vs Packages

The configuration separates packages into two categories:

- **StdPackages**: System-critical packages including the autoupdater itself
  - These are updated with higher priority
  - The autoupdater monitors its own repository here
  
- **Packages**: Application packages managed by the autoupdater
  - Your applications (like RocketWelder) go here
  - Updated after StdPackages are up-to-date

### Example Configuration

```json
{
  "StdPackages": [
    {
      "RepositoryLocation": "/data/repositories/autoupdater-compose",
      "RepositoryUrl": "https://github.com/modelingevolution/autoupdater-compose.git",
      "DockerComposeDirectory": "./"
    }
  ],
  "Packages": [
    {
      "RepositoryLocation": "/data/repositories/rocket-welder-compose",
      "RepositoryUrl": "https://github.com/modelingevolution/rocket-welder-compose.git",
      "DockerComposeDirectory": "./"
    }
  ]
}
```

## Installation Script Parameters

The installation script accepts three required parameters:

| Parameter | Description | Example |
|-----------|-------------|---------|
| `app-name` | Name of your application (used in repository paths) | `rocket-welder` |
| `git-compose-url` | Git repository URL for your application's compose configuration | `https://github.com/modelingevolution/rocketwelder-compose.git` |
| `computer-name` | Unique identifier for this deployment/computer | `POC-400` |

### Example Usage

```bash
# For RocketWelder on POC-400
sudo ./installation.sh rocket-welder https://github.com/modelingevolution/rocketwelder-compose.git POC-400

# For a different application
sudo ./installation.sh my-app https://github.com/myorg/my-app-compose.git PROD-001
```

## Directory Structure

After installation, the following structure is created:

```
/var/docker/configuration/
├── autoupdater/
│   ├── docker-compose.yml           # Generated compose file
│   ├── appsettings.Production.json  # Generated configuration
│   ├── .env                         # Environment variables
│   └── .ssh/                        # SSH keys
│       ├── id_rsa                   # Private key (auto-generated)
│       └── id_rsa.pub               # Public key
└── repositories/                    # Managed by autoupdater
    ├── autoupdater-compose/         # Self-update repository
    └── <app-name>-compose/          # Your application repository
```

### Key Paths

- **Configuration Base**: `/var/docker/configuration/`
- **AutoUpdater Config**: `/var/docker/configuration/autoupdater/`
- **SSH Keys**: `/var/docker/configuration/autoupdater/.ssh/`
- **Repositories**: `/var/docker/configuration/repositories/`

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
docker-compose exec modelingevolution.autoupdater.host ssh -i /data/ssh/id_rsa deploy@target-host echo "Connected"

# Check SSH key permissions
docker-compose exec modelingevolution.autoupdater.host ls -la /data/ssh/
```

### Repository Access Issues
```bash
# Verify repository clone
docker-compose exec modelingevolution.autoupdater.host ls -la /data/repositories/

# Check Git connectivity
docker-compose exec modelingevolution.autoupdater.host git ls-remote https://github.com/modelingevolution/autoupdater-compose.git
```

## Updates

The autoupdater will automatically update itself when new versions are tagged in this repository. To trigger a manual update:

1. Tag a new version in this repository
2. The autoupdater will detect and apply the update within its polling interval

## License

MIT License - See the main [autoupdater repository](https://github.com/modelingevolution/autoupdater) for details.