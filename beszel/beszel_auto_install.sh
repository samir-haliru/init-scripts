#!/bin/bash

# === Beszel Installation Script (Debian/Ubuntu Only) ===
# This script installs Beszel using Docker. It runs only once on first boot.
# It prepares the system, installs Docker, configures the firewall for the
# Beszel port, starts the Beszel container, and creates an OPTIONAL
# script to configure Nginx/HTTPS later if you decide to use a domain name.

set -euo pipefail # Exit on error, unset variable, or pipe failure

# --- Configuration ---
LOG_FILE="/var/log/beszel-install.log"
DOCKER_IMAGE="henrygd/beszel:latest"
BESZEL_PORT=8090
DATA_DIR="/opt/beszel/beszel_data"
DOMAIN_SETUP_SCRIPT="/opt/beszel/setup-domain.sh"
# --- End Configuration ---

# --- Logging ---
# Redirect all stdout/stderr to the log file
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== Beszel Init Script Started ==="
echo "Date: $(date)"
echo "Target OS: Debian / Ubuntu"

log() {
    local level=$1
    local msg=$2
    # Timestamps are added automatically by the exec redirection setup
    echo "[$level] $msg"
}
# --- End Logging ---

# --- OS Check ---
check_os() {
    if [ -f /etc/debian_version ]; then
        log "INFO" "Detected Debian/Ubuntu based system. Proceeding."
        # Source os-release to log specific version if needed
        if [ -f /etc/os-release ]; then
             . /etc/os-release
             log "INFO" "OS Detected: $PRETTY_NAME"
        fi
    else
        log "ERROR" "This script is only compatible with Debian or Ubuntu."
        log "ERROR" "Installation aborted."
        exit 1
    fi
}
# --- End OS Check ---

# --- System Preparation ---
prepare_system() {
    log "INFO" "Preparing system..."

    # Create dedicated user
    if ! id -u beszel &>/dev/null; then
        if useradd -Mr -s /usr/sbin/nologin beszel; then
             log "INFO" "Created system user 'beszel'."
        else
             log "ERROR" "Failed to create user 'beszel'."
             exit 1
        fi
    else
        log "INFO" "User 'beszel' already exists."
    fi

    # Create data directory
    if mkdir -p "$DATA_DIR"; then
        log "INFO" "Ensured data directory exists: $DATA_DIR"
    else
        log "ERROR" "Failed to create data directory: $DATA_DIR"
        exit 1
    fi
    if chown -R beszel:beszel "$DATA_DIR"; then
        log "INFO" "Set ownership of $DATA_DIR to beszel:beszel"
    else
        log "WARN" "Could not set ownership of $DATA_DIR. Check permissions."
    fi
}
# --- End System Preparation ---

# --- Docker Installation ---
install_docker() {
    log "INFO" "Installing Docker..."
    export DEBIAN_FRONTEND=noninteractive # Ensure non-interactive install

    log "INFO" "Updating package list..."
    if ! apt-get update -y; then
        log "ERROR" "apt-get update failed."
        exit 1
    fi

    log "INFO" "Installing docker.io package..."
    if ! apt-get install -y docker.io; then
        log "ERROR" "Failed to install docker.io."
        exit 1
    fi

    log "INFO" "Ensuring Docker service is enabled and started..."
    if ! systemctl enable --now docker; then
         log "ERROR" "Failed to enable or start Docker service."
         exit 1
    fi

    # Add beszel user to docker group (needed if Beszel interacts with Docker socket, good practice anyway)
    usermod -aG docker beszel
    log "INFO" "Added beszel user to the docker group."
    log "INFO" "Docker installation complete."
}
# --- End Docker Installation ---

# --- Firewall Configuration ---
configure_firewall() {
    log "INFO" "Configuring firewall for Beszel port $BESZEL_PORT..."

    if command -v ufw >/dev/null 2>&1; then
        log "INFO" "UFW detected. Allowing port $BESZEL_PORT/tcp."
        if ufw allow $BESZEL_PORT/tcp comment 'Beszel Hub Access'; then
            log "INFO" "UFW rule added for port $BESZEL_PORT."
            # Check if UFW is active - don't attempt to enable it automatically
            if ufw status | grep -qw active; then
                 log "INFO" "UFW is active. Rule for port $BESZEL_PORT is live."
            else
                 log "WARN" "UFW rule added, but UFW is not active. You may need to enable it manually (sudo ufw enable) after login."
            fi
        else
            log "ERROR" "Failed to add UFW rule for port $BESZEL_PORT."
            # Continue installation, but warn user
        fi
    else
        log "WARN" "UFW command not found. Firewall rule for port $BESZEL_PORT not added."
        log "WARN" "Please configure your firewall manually if required."
    fi
}
# --- End Firewall Configuration ---

# --- Beszel Docker Service Setup ---
setup_docker_service() {
    log "INFO" "Configuring systemd service for Beszel..."

    # Stop/Remove existing container if script is somehow re-run (defensive)
    log "INFO" "Attempting to stop/remove existing beszel container (if any)..."
    docker stop beszel > /dev/null 2>&1 || true
    docker rm beszel > /dev/null 2>&1 || true

    log "INFO" "Creating systemd service file at /etc/systemd/system/beszel.service"
    cat > /etc/systemd/system/beszel.service <<EOF
[Unit]
Description=Beszel Hub Container
Requires=docker.service
After=docker.service

[Service]
TimeoutStartSec=0
Restart=always
User=beszel
Group=docker
# Pull latest image on start - uncomment if you want this behavior
# ExecStartPre=/usr/bin/docker pull $DOCKER_IMAGE
ExecStartPre=-/usr/bin/docker stop beszel
ExecStartPre=-/usr/bin/docker rm beszel
ExecStart=/usr/bin/docker run \\
    --name beszel \\
    --rm \\
    --network host \\
    -v $DATA_DIR:/beszel_data \\
    -e BESZEL_ENV=production \\
    $DOCKER_IMAGE

# Alternative network if you don't want --network host:
# ExecStart=/usr/bin/docker run \\
#    --name beszel \\
#    --rm \\
#    -p $BESZEL_PORT:8090 \\
#    -v $DATA_DIR:/beszel_data \\
#    -e BESZEL_ENV=production \\
#    $DOCKER_IMAGE

[Install]
WantedBy=multi-user.target
EOF
# Note: Using --network host simplifies things but is less secure than port mapping.
# The commented-out alternative shows the port mapping method (-p $BESZEL_PORT:8090).
# If using port mapping, ensure the `User=` and `Group=` lines are removed or adjusted
# as the docker daemon runs as root, not the beszel user. Let's stick with --network host for now.
# Removed --restart unless-stopped as --rm and systemd Restart=always handle it.

    log "INFO" "Reloading systemd daemon..."
    systemctl daemon-reload

    log "INFO" "Enabling and starting Beszel service..."
    if ! systemctl enable --now beszel; then
        log "ERROR" "Failed to enable or start beszel service."
        log "ERROR" "Check service status with: systemctl status beszel"
        log "ERROR" "Check service logs with: journalctl -u beszel"
        exit 1
    fi

    log "INFO" "Beszel service configured and started."
}
# --- End Beszel Docker Service Setup ---

# --- Create Optional Domain Setup Script ---
create_domain_script() {
    log "INFO" "Creating optional domain setup script at $DOMAIN_SETUP_SCRIPT..."

    # Ensure the target directory exists
    mkdir -p "$(dirname "$DOMAIN_SETUP_SCRIPT")"

    # Heredoc for the domain setup script content
    cat > "$DOMAIN_SETUP_SCRIPT" << 'EOF_DOMAIN_SCRIPT'
#!/bin/bash

# === Beszel Domain Setup Script (Debian/Ubuntu Only) ===
# Configures Nginx reverse proxy and obtains SSL certificate using Certbot.
# Run *after* pointing your domain name to this server's IP.
#
# Usage for Production Certificate:
#   sudo bash /opt/beszel/setup-domain.sh your-domain.com
#
# Usage for Testing with Let's Encrypt Staging (avoids rate limits):
#   sudo bash /opt/beszel/setup-domain.sh your-domain.com --staging

set -euo pipefail

# --- Configuration ---
DOMAIN="$1"
MODE="${2:-production}" # Default to production if second arg is missing
BESZEL_INTERNAL_PORT=8090
LOG_FILE="/var/log/beszel-domain-setup.log"
NGINX_SITES_DIR="/etc/nginx/sites-available"
NGINX_SYMLINK_DIR="/etc/nginx/sites-enabled"
CERTBOT_STAGING_FLAG="" # Initialize staging flag as empty
# --- End Configuration ---

# --- Input Validation & Mode Check ---
if [ -z "$DOMAIN" ]; then
    echo "ERROR: Domain name not provided."
    echo "Usage: sudo $0 <your-domain.com> [--staging]"
    exit 1
fi
if ! [[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo "ERROR: '$DOMAIN' does not look like a valid domain name."
    exit 1
fi

if [[ "$MODE" == "--staging" ]]; then
    echo "INFO: Running in STAGING mode. Certificates will NOT be trusted by browsers."
    CERTBOT_STAGING_FLAG="--staging"
elif [[ "$MODE" != "production" ]]; then
    # Handle cases where a second argument is provided but it's not --staging
    echo "ERROR: Invalid second argument '$MODE'. Only '--staging' is accepted."
    echo "Usage: sudo $0 <your-domain.com> [--staging]"
    exit 1
fi
# --- End Input Validation & Mode Check ---

# --- Logging Setup ---
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== Beszel Domain Setup Started ==="
echo "Date: $(date)"
echo "Domain: $DOMAIN"
echo "Mode: ${MODE/--/}" # Display 'staging' or 'production'
echo "Beszel Internal Port: $BESZEL_INTERNAL_PORT"
# --- End Logging Setup ---

log_domain() {
    local level=$1
    local msg=$2
    echo "[$level] $msg"
}

# --- Start of original script logic ---

log_domain "INFO" "Checking OS compatibility..."
if [ ! -f /etc/debian_version ]; then
    log_domain "ERROR" "This script is only compatible with Debian or Ubuntu."
    exit 1
fi
log_domain "INFO" "Debian/Ubuntu system confirmed."

log_domain "INFO" "Updating package lists..."
export DEBIAN_FRONTEND=noninteractive
if ! apt-get update -y; then
    log_domain "ERROR" "apt-get update failed."
    exit 1
fi

log_domain "INFO" "Installing Nginx and Certbot (with Nginx plugin)..."
if ! apt-get install -y nginx certbot python3-certbot-nginx; then
    log_domain "ERROR" "Failed to install required packages (nginx, certbot)."
    exit 1
fi

if ! command -v nginx &>/dev/null; then log_domain "ERROR" "Nginx installation failed."; exit 1; fi
if ! command -v certbot &>/dev/null; then log_domain "ERROR" "Certbot installation failed."; exit 1; fi
log_domain "INFO" "Nginx and Certbot installed successfully."

log_domain "INFO" "Configuring firewall (UFW) to allow HTTP/HTTPS..."
if command -v ufw >/dev/null 2>&1; then
    if ufw status | grep -qw active; then
        log_domain "INFO" "UFW is active. Allowing ports 80 and 443."
        ufw allow 80/tcp comment 'Nginx HTTP'
        ufw allow 443/tcp comment 'Nginx HTTPS'
        log_domain "INFO" "UFW rules for HTTP/HTTPS added."
    else
        log_domain "WARN" "UFW is installed but not active. Firewall rules not applied."
        log_domain "WARN" "Consider enabling UFW with 'sudo ufw enable'."
    fi
else
    log_domain "WARN" "UFW command not found. Firewall rules for HTTP/HTTPS not added."
fi

log_domain "INFO" "Creating Nginx configuration with proxy settings (for HTTP initially)..."
mkdir -p "$NGINX_SITES_DIR" "$NGINX_SYMLINK_DIR"
rm -f "$NGINX_SYMLINK_DIR/default"

cat > "$NGINX_SITES_DIR/$DOMAIN.conf" << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    root /var/www/html;
    location /.well-known/acme-challenge/ { }
    location / {
        proxy_pass http://127.0.0.1:$BESZEL_INTERNAL_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}
EOF

log_domain "INFO" "Enabling Nginx site configuration for $DOMAIN..."
ln -sf "$NGINX_SITES_DIR/$DOMAIN.conf" "$NGINX_SYMLINK_DIR/$DOMAIN.conf"

log_domain "INFO" "Testing INITIAL Nginx configuration (with proxy settings)..."
if ! nginx -t; then log_domain "ERROR" "INITIAL Nginx configuration test failed."; exit 1; fi
log_domain "INFO" "INITIAL Nginx configuration test successful."

log_domain "INFO" "Reloading Nginx to apply INITIAL configuration..."
systemctl enable --now nginx &>/dev/null
if ! systemctl reload nginx; then log_domain "ERROR" "Failed to reload Nginx."; exit 1; fi
log_domain "INFO" "Nginx reloaded with config ready for Certbot validation & modification."

log_domain "INFO" "Attempting to obtain SSL certificate (Mode: ${MODE/--/}) and configure HTTPS using Certbot..."
ADMIN_EMAIL="admin@$DOMAIN"
log_domain "INFO" "Using email $ADMIN_EMAIL for Let's Encrypt."

# Construct the certbot command, including the staging flag if set
CERTBOT_CMD="certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email $ADMIN_EMAIL --redirect $CERTBOT_STAGING_FLAG"
log_domain "INFO" "Running Certbot command: $CERTBOT_CMD"

if ! $CERTBOT_CMD; then
    log_domain "ERROR" "Certbot failed to obtain/install certificate or configure Nginx."
    log_domain "ERROR" "Check Certbot logs (/var/log/letsencrypt/letsencrypt.log) and Nginx logs."
    exit 1
fi
log_domain "INFO" "Certbot successfully obtained certificate and configured Nginx for HTTPS."

log_domain "INFO" "Checking Certbot auto-renewal..."
# Note: Renewal checks typically don't use --staging automatically, even if issued with it.
# Production renewals will fail if the staging cert is still present when a real one is needed.
if systemctl list-timers | grep -q 'certbot.timer'; then
    log_domain "INFO" "Certbot systemd timer for auto-renewal is active."
elif crontab -l 2>/dev/null | grep -q 'certbot renew'; then
    log_domain "INFO" "Certbot cron job for auto-renewal found."
else
    log_domain "WARN" "Could not automatically verify Certbot auto-renewal setup. Check manually."
fi

log_domain "SUCCESS" "=== Domain Setup Complete ==="
if [[ "$MODE" == "--staging" ]]; then
    log_domain "WARN" "Using STAGING certificate. Browser will show security warnings."
    log_domain "WARN" "To get a production certificate, re-run without '--staging' after deleting existing certs:"
    log_domain "WARN" "  sudo rm -rf /etc/letsencrypt/{live,renewal,archive}/$DOMAIN"
fi
log_domain "SUCCESS" "Beszel Hub should now be accessible at: https://$DOMAIN"
log_domain "INFO" "Nginx is configured as a reverse proxy with SSL."
log_domain "INFO" "Full logs for this script are available at: $LOG_FILE"

exit 0
EOF_DOMAIN_SCRIPT
# --- End Heredoc ---

    # Make the script executable
    chmod +x "$DOMAIN_SETUP_SCRIPT"
    log "INFO" "Domain setup script created and made executable: $DOMAIN_SETUP_SCRIPT"
}
# --- End Create Domain Setup Script ---

# --- Public IP Detection ---
get_public_ip() {
    # Try different methods with timeouts
    local ip
    ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null) || \
    ip=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null) || \
    ip=$(hostname -I | awk '{print $1}') || \
    ip="<Could not detect IP>"
    echo "$ip"
}
# --- End Public IP Detection ---

# --- Main Execution ---
main() {
    check_os
    prepare_system
    install_docker
    configure_firewall # Configure for direct Beszel port access
    setup_docker_service
    create_domain_script # Create the *optional* script with the staging flag logic

    PUBLIC_IP=$(get_public_ip)

    # --- Final Output Message ---
    log "INFO" "========================================================"
    log "INFO" " Beszel Installation Complete!"
    log "INFO" "========================================================"
    log "INFO" " "
    log "INFO" " Beszel Hub is running in a Docker container."
    log "INFO" " You can access it directly via the server's IP address:"
    log "INFO" " -> http://${PUBLIC_IP}:${BESZEL_PORT}  (HTTP only)"
    log "INFO" " "
    log "INFO" " Firewall Status (Port ${BESZEL_PORT} for direct access):"
    # --- Check UFW Status ---
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -qw active; then
             if ufw status verbose | grep -q "${BESZEL_PORT}/tcp.*ALLOW IN"; then
                 log "INFO" " -> UFW is ACTIVE and allows incoming connections on port ${BESZEL_PORT}."
             else
                 log "WARN" " -> UFW is ACTIVE but the rule for port ${BESZEL_PORT} seems missing or incorrect."
                 log "WARN" "    Run 'sudo ufw status verbose' to check."
             fi
        else
             log "WARN" " -> UFW is installed but INACTIVE. Rule for port ${BESZEL_PORT} is not enforced."
             log "WARN" "    Consider running 'sudo ufw enable' after logging in if you need the firewall."
        fi
    else
         log "WARN" " -> UFW firewall is not installed. Access to port ${BESZEL_PORT} depends on your cloud provider's firewall settings."
    fi
    # --- End UFW Check ---
    log "INFO" " "
    log "INFO" "========================================================"
    log "INFO" " OPTIONAL: Configure a Domain Name (HTTPS Access)"
    log "INFO" "========================================================"
    log "INFO" " A script has been created to help you configure Nginx"
    log "INFO" " as a reverse proxy and obtain a free SSL certificate"
    log "INFO" " from Let's Encrypt using Certbot."
    log "INFO" " "
    log "INFO" " Prerequisites:"
    log "INFO" " 1. You need a registered domain name."
    log "INFO" " 2. Point your domain's DNS A record to this server's IP: ${PUBLIC_IP}"
    log "INFO" " 3. Wait for DNS propagation (this can take anywhere from a few minutes to several hours)."
    log "INFO" " "
    log "INFO" " How to run the setup script:"
    log "INFO" " 1. SSH into this server: ssh <user>@${PUBLIC_IP}"
    log "INFO" " 2. Run ONE of the following commands:"
    log "INFO" " "
    log "INFO" "    a) For a PRODUCTION certificate (standard usage):"
    log "INFO" "       sudo bash ${DOMAIN_SETUP_SCRIPT} your-domain.com"
    log "INFO" "       (Replace 'your-domain.com' with your actual domain)"
    log "INFO" " "
    log "INFO" "    b) For TESTING with a STAGING certificate:"
    log "INFO" "       sudo bash ${DOMAIN_SETUP_SCRIPT} your-domain.com --staging"
    log "INFO" "       - Use this to test the setup process without hitting Let's Encrypt's"
    log "INFO" "         production rate limits."
    log "INFO" "       - Staging certificates are NOT TRUSTED by browsers (you'll see errors)."
    log "INFO" "       - IMPORTANT: You MUST clean up staging certificates before requesting"
    log "INFO" "         a production one. The script will provide instructions if run with --staging."
    log "INFO" " "
    log "INFO" " The script will:"
    log "INFO" " - Install Nginx and Certbot."
    log "INFO" " - Configure Nginx as a reverse proxy for Beszel."
    log "INFO" " - Request and install the SSL certificate."
    log "INFO" " - Configure the firewall (UFW) for ports 80 (HTTP) and 443 (HTTPS)."
    log "INFO" " "
    log "INFO" "========================================================"
    log "INFO" " Managing the Beszel Service"
    log "INFO" "========================================================"
    log "INFO" " - Status: sudo systemctl status beszel"
    log "INFO" " - Stop:   sudo systemctl stop beszel"
    log "INFO" " - Start:  sudo systemctl start beszel"
    log "INFO" " - Restart:sudo systemctl restart beszel"
    log "INFO" " - Logs:   sudo journalctl -u beszel -f"
    log "INFO" " "
    log "INFO" "========================================================"
    log "INFO" " Updating Beszel"
    log "INFO" "========================================================"
    log "INFO" " 1. Pull the latest Docker image:"
    log "INFO" "    sudo docker pull ${DOCKER_IMAGE}"
    log "INFO" " 2. Restart the service to use the new image:"
    log "INFO" "    sudo systemctl restart beszel"
    log "INFO" " "
    log "INFO" "========================================================"
    log "INFO" " Log Files"
    log "INFO" "========================================================"
    log "INFO" " - This installation script log: ${LOG_FILE}"
    log "INFO" " - Domain setup script log (if run): /var/log/beszel-domain-setup.log"
    log "INFO" " ========================================================"
}

# --- Run Main ---
# Wrap main execution in a block to ensure logs capture everything, even early exits
{
    main
    log "INFO" "Init script finished successfully."
} || {
    # Log failure if main() exits with non-zero status due to set -e
    log "ERROR" "Beszel Init Script failed. Check logs above for details: $LOG_FILE"
    exit 1
}

exit 0
# --- End Script ---
