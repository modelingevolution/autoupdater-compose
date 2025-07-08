# AutoUpdater Production Deployment

This repository contains the production deployment configuration for [ModelingEvolution.AutoUpdater](https://github.com/modelingevolution/autoupdater).

## Overview

This compose configuration is designed for production deployments where the autoupdater monitors and updates:
1. **Itself** (via StdPackages configuration)
2. **Other applications** like RocketWelder (via Packages configuration)

## Quick Start

1. **Clone this repository to your production server:**
   ```bash
   git clone https://github.com/modelingevolution/autoupdater-compose.git
   cd autoupdater-compose
   ```

2. **Set up SSH keys:**
   ```bash
   mkdir -p data/ssh
   ssh-keygen -t rsa -b 4096 -f data/ssh/id_rsa -C "autoupdater@$(hostname)"
   chmod 600 data/ssh/id_rsa
   ```

3. **Install SSH key on target hosts:**
   ```bash
   ssh-copy-id -i data/ssh/id_rsa.pub deploy@target-host
   ```

4. **Configure environment:**
   ```bash
   cp .env.example .env
   # Edit .env if needed
   ```

5. **Review and customize `appsettings.Production.json`:**
   - Update repository URLs for your applications
   - Configure Docker registry authentication if needed

6. **Start the autoupdater:**
   ```bash
   docker-compose up -d
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

## Directory Structure

```
autoupdater-compose/
├── docker-compose.yml           # Main compose file
├── appsettings.Production.json  # Production configuration
├── .env.example                 # Environment variables template
├── .gitignore                   # Git ignore rules
├── data/                        # Persistent data (created at runtime)
│   ├── ssh/                     # SSH keys
│   │   ├── id_rsa              # Private key (generate this)
│   │   └── id_rsa.pub          # Public key
│   └── repositories/            # Cloned repositories
│       ├── autoupdater-compose/
│       └── rocket-welder-compose/
└── README.md                    # This file
```

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