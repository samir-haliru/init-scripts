# n8n Auto-Install Script

A comprehensive initialization script for automatically deploying n8n workflow automation on Debian/Ubuntu servers. This script sets up n8n using Docker with systemd service management, optional domain configuration with SSL, and comprehensive logging.

## What this script does

- **Installs Docker** using the official Docker repository
- **Deploys n8n** in a Docker container with persistent data storage
- **Creates systemd service** for automatic startup and management
- **Configures firewall** (UFW) to allow n8n access
- **Sets up logging** for installation and service monitoring
- **Creates optional domain setup script** for SSL/HTTPS configuration

## Prerequisites

- **Operating system**: Debian or Ubuntu server
- **Root access**: Script must run as root (typically via cloud-init)
- **Internet connection**: Required for downloading packages and Docker images
- **Basic server specifications**: 1GB RAM minimum, 2GB+ recommended

## Deployment

### Using cloud-init (recommended)

1. **Copy the script** (`n8n_auto_install.sh`) to your cloud provider's initialization script field
2. **Deploy your server** - the script will run automatically during first boot
3. **Wait for completion** - typically takes 5-10 minutes depending on server specs
4. **Access n8n** via `http://YOUR-SERVER-IP:5678`

### Manual execution

If running manually on an existing server:

```bash
# Download the script
wget https://your-script-location/n8n_auto_install.sh

# Make executable
chmod +x n8n_auto_install.sh

# Run as root
sudo ./n8n_auto_install.sh
```

## Post-deployment access

Once installation completes, you can access n8n at:
```
http://YOUR-SERVER-IP:5678
```

**Initial setup**: On first access, n8n will prompt you to create an admin account.

## Domain setup (optional HTTPS)

The script creates an optional domain configuration script at `/opt/n8n/setup-domain.sh` for adding SSL certificates and custom domains.

### Prerequisites for domain setup

1. **Registered domain name**
2. **DNS A record** pointing your domain to the server IP
3. **DNS propagation** complete (test with `nslookup your-domain.com`)

### Running domain setup

```bash
# For production certificate
sudo bash /opt/n8n/setup-domain.sh your-domain.com

# For testing (staging certificate)
sudo bash /opt/n8n/setup-domain.sh your-domain.com --staging
```

**What the domain script does:**
- Installs Nginx and Certbot
- Configures Nginx as reverse proxy with WebSocket support
- Obtains Let's Encrypt SSL certificate
- Configures automatic HTTP to HTTPS redirect
- Updates firewall for ports 80/443

**After domain setup**, access n8n at: `https://your-domain.com`

### Environment variables for domains

After setting up a domain, consider updating n8n's configuration:

```bash
# Edit the systemd service
sudo nano /etc/systemd/system/n8n.service

# Add these environment variables in the ExecStart section:
# -e N8N_HOST="your-domain.com" \
# -e WEBHOOK_URL="https://your-domain.com/" \

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart n8n
```

## Managing the n8n service

### Service commands
```bash
# Check status
sudo systemctl status n8n

# Start service
sudo systemctl start n8n

# Stop service
sudo systemctl stop n8n

# Restart service
sudo systemctl restart n8n

# View logs (follow mode)
sudo journalctl -u n8n -f

# View recent logs
sudo journalctl -u n8n --since "1 hour ago"
```

### Data persistence

n8n data is stored in a Docker volume called `n8n_data`. This includes:
- Workflow configurations
- Credentials
- Settings
- Execution history

### Backup considerations

```bash
# Backup n8n data volume
sudo docker run --rm -v n8n_data:/data -v $(pwd):/backup ubuntu tar czf /backup/n8n-backup.tar.gz /data

# Restore n8n data volume
sudo docker run --rm -v n8n_data:/data -v $(pwd):/backup ubuntu tar xzf /backup/n8n-backup.tar.gz -C /
```

## Updating n8n

The service automatically pulls the latest image on restart. To update:

```bash
# Method 1: Simple restart (if auto-pull is configured)
sudo systemctl restart n8n

# Method 2: Manual pull then restart
sudo docker pull docker.n8n.io/n8nio/n8n:latest
sudo systemctl restart n8n
```

### Pinning specific versions

To use a specific n8n version instead of `latest`:

```bash
# Edit the systemd service
sudo nano /etc/systemd/system/n8n.service

# Change the image tag from:
# docker.n8n.io/n8nio/n8n:latest
# to:
# docker.n8n.io/n8nio/n8n:1.x.x

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart n8n
```

## Security considerations

### Firewall configuration

The script configures UFW but doesn't enable it by default. Consider enabling:

```bash
# Enable UFW (be careful with SSH access)
sudo ufw enable

# Check current rules
sudo ufw status verbose
```

### Direct IP access security

If using direct IP access (without domain), consider:
- Restricting access to specific IP ranges
- Using VPN access
- Setting up basic authentication

### Domain access security

When using the domain setup:
- SSL certificates are automatically configured
- HTTP automatically redirects to HTTPS
- Consider additional security headers in Nginx

## Troubleshooting

### Common issues

**n8n not accessible:**
```bash
# Check if service is running
sudo systemctl status n8n

# Check Docker container
sudo docker ps | grep n8n

# Check logs
sudo journalctl -u n8n --no-pager
```

**Docker issues:**
```bash
# Restart Docker service
sudo systemctl restart docker

# Check Docker status
sudo systemctl status docker
```

**Firewall blocking access:**
```bash
# Check UFW status
sudo ufw status

# Allow n8n port manually
sudo ufw allow 5678/tcp
```

**Domain setup failures:**
```bash
# Check domain setup logs
sudo tail -f /var/log/n8n-domain-setup.log

# Verify DNS resolution
nslookup your-domain.com

# Check Nginx configuration
sudo nginx -t
```

### Log file locations

- **Installation script**: `/var/log/n8n-install.log`
- **Domain setup script**: `/var/log/n8n-domain-setup.log`
- **n8n service logs**: `sudo journalctl -u n8n`
- **Nginx logs**: `/var/log/nginx/access.log` and `/var/log/nginx/error.log`

## File locations and configuration

### Key files and directories

- **Systemd service**: `/etc/systemd/system/n8n.service`
- **Domain setup script**: `/opt/n8n/setup-domain.sh`
- **Docker volume**: `n8n_data` (managed by Docker)
- **Nginx config** (if domain setup): `/etc/nginx/sites-available/your-domain.conf`

### Customising the installation

The script includes configuration variables at the top:

```bash
DOCKER_IMAGE="docker.n8n.io/n8nio/n8n:latest"
N8N_PORT=5678
DOCKER_VOLUME_NAME="n8n_data"
CONTAINER_NAME="n8n"
```

Modify these before deployment to customise the installation.

## Script limitations

- **Debian/Ubuntu only**: The script specifically targets Debian-based distributions
- **Single instance**: Designed for single n8n instance per server
- **Root privileges required**: Must run with root access
- **Internet dependency**: Requires internet access throughout installation

## Support and maintenance

This script is designed for initial deployment. For ongoing maintenance:

- Monitor service status regularly
- Keep Docker and system packages updated
- Monitor disk usage (workflow data can grow)
- Regular backups of the `n8n_data` volume
- Review n8n logs for errors or performance issues

For n8n-specific issues, consult the [official n8n documentation](https://docs.n8n.io/).
