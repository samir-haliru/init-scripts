#!/bin/bash

# === n8n Installation Script (Debian/Ubuntu Only) ===
# This script installs n8n using Docker.
# It prepares the system, installs Docker, creates the n8n Docker volume,
# configures the firewall for the n8n port, starts the n8n container via
# systemd, and creates an OPTIONAL script to configure Nginx/HTTPS later
# if you decide to use a domain name.

set -euo pipefail # Exit on error, unset variable, or pipe failure

# --- Configuration ---
LOG_FILE="/var/log/n8n-install.log"
DOCKER_IMAGE="docker.n8n.io/n8nio/n8n:latest" # Use official image
N8N_PORT=5678 # Default n8n port
DOCKER_VOLUME_NAME="n8n_data" # Recommended Docker volume name
CONTAINER_NAME="n8n"
DOMAIN_SETUP_SCRIPT="/opt/n8n/setup-domain.sh"
# --- End Configuration ---

# --- Logging ---
# Redirect all stdout/stderr to the log file
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== n8n Init Script Started ==="
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

# --- System Preparation (Minimal - Docker volume handled later) ---
prepare_system() {
    log "INFO" "Preparing system (minimal steps required)..."
    # No dedicated user needed for basic n8n Docker install
    # Docker volume creation will be handled just before container start
    log "INFO" "System preparation complete."
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

    log "INFO" "Installing prerequisites..."
    # Required by Docker's official install script and good practice
    if ! apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release; then
        log "ERROR" "Failed to install Docker prerequisites."
        exit 1
    fi

    log "INFO" "Adding Docker's official GPG key..."
    mkdir -p /etc/apt/keyrings
    # Check if key already exists to avoid error on re-run
    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
        if ! curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
            log "ERROR" "Failed to download or save Docker GPG key."
            exit 1
        fi
        chmod a+r /etc/apt/keyrings/docker.gpg
    else
        log "INFO" "Docker GPG key already exists."
    fi

    log "INFO" "Setting up Docker repository..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    log "INFO" "Updating package list after adding Docker repo..."
     if ! apt-get update -y; then
        log "ERROR" "apt-get update failed after adding Docker repo."
        exit 1
    fi

    log "INFO" "Installing Docker Engine, CLI, Containerd, and Compose plugin..."
    if ! apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        log "ERROR" "Failed to install Docker packages (docker-ce, etc.)."
        # Fallback to docker.io if docker-ce fails? Maybe not ideal for init script.
        # For now, fail hard if official install fails.
        exit 1
    fi

    log "INFO" "Ensuring Docker service is enabled and started..."
    if ! systemctl enable --now docker; then
         log "ERROR" "Failed to enable or start Docker service."
         exit 1
    fi

    log "INFO" "Docker installation complete."
}
# --- End Docker Installation ---

# --- Firewall Configuration ---
configure_firewall() {
    log "INFO" "Configuring firewall for n8n port $N8N_PORT..."

    if command -v ufw >/dev/null 2>&1; then
        log "INFO" "UFW detected. Allowing port $N8N_PORT/tcp."
        if ufw allow $N8N_PORT/tcp comment 'n8n Access'; then
            log "INFO" "UFW rule added for port $N8N_PORT."
            # Check if UFW is active - don't attempt to enable it automatically
            if ufw status | grep -qw active; then
                 log "INFO" "UFW is active. Rule for port $N8N_PORT is live."
            else
                 log "WARN" "UFW rule added, but UFW is not active. You may need to enable it manually (sudo ufw enable) after login."
            fi
        else
            log "ERROR" "Failed to add UFW rule for port $N8N_PORT."
            # Continue installation, but warn user
        fi
    else
        log "WARN" "UFW command not found. Firewall rule for port $N8N_PORT not added."
        log "WARN" "Please configure your firewall manually if required."
    fi
}
# --- End Firewall Configuration ---

# --- n8n Docker Service Setup ---
setup_docker_service() {
    log "INFO" "Configuring systemd service for n8n..."

    # Stop/Remove existing container if script is somehow re-run (defensive)
    log "INFO" "Attempting to stop/remove existing ${CONTAINER_NAME} container (if any)..."
    docker stop $CONTAINER_NAME > /dev/null 2>&1 || true
    docker rm $CONTAINER_NAME > /dev/null 2>&1 || true

    # Get system timezone, default to UTC
    SYSTEM_TZ=$(cat /etc/timezone 2>/dev/null || echo "Etc/UTC")
    log "INFO" "Using Timezone: $SYSTEM_TZ"

    log "INFO" "Creating systemd service file at /etc/systemd/system/n8n.service"
    cat > /etc/systemd/system/n8n.service <<EOF
[Unit]
Description=n8n Workflow Automation Container
Requires=docker.service
After=docker.service

[Service]
TimeoutStartSec=0
Restart=always
# Ensure Docker volume exists (command ignores error if already exists)
ExecStartPre=-/usr/bin/docker volume create $DOCKER_VOLUME_NAME
# Pull latest image on start (optional, can be commented out)
ExecStartPre=/usr/bin/docker pull $DOCKER_IMAGE
# Stop/Remove existing container before start
ExecStartPre=-/usr/bin/docker stop $CONTAINER_NAME
ExecStartPre=-/usr/bin/docker rm $CONTAINER_NAME
# The actual command to run n8n
ExecStart=/usr/bin/docker run \\
    --name $CONTAINER_NAME \\
    --rm \\
    -p $N8N_PORT:5678 \\
    -v $DOCKER_VOLUME_NAME:/home/node/.n8n \\
    -e TZ="$SYSTEM_TZ" \\
    -e N8N_SECURE_COOKIE=false \\
    $DOCKER_IMAGE

# Optional: Add other environment variables here if needed, e.g.:
#    -e N8N_HOST="your.domain.com" \\
#    -e WEBHOOK_URL="https://your.domain.com/" \\
#    -e GENERIC_TIMEZONE="$SYSTEM_TZ" \\

# Define how to stop the container gracefully
ExecStop=/usr/bin/docker stop -t 30 $CONTAINER_NAME

[Install]
WantedBy=multi-user.target
EOF

    log "INFO" "Reloading systemd daemon..."
    systemctl daemon-reload

    log "INFO" "Enabling and starting n8n service..."
    if ! systemctl enable --now n8n; then
        log "ERROR" "Failed to enable or start n8n service."
        log "ERROR" "Check service status with: systemctl status n8n"
        log "ERROR" "Check service logs with: journalctl -u n8n"
        exit 1
    fi

    log "INFO" "n8n service configured and started."
}
# --- End n8n Docker Service Setup ---

# --- Create Optional Domain Setup Script ---
create_domain_script() {
    log "INFO" "Creating optional domain setup script at $DOMAIN_SETUP_SCRIPT..."

    # Ensure the target directory exists
    mkdir -p "$(dirname "$DOMAIN_SETUP_SCRIPT")"

    # Heredoc for the domain setup script content
    cat > "$DOMAIN_SETUP_SCRIPT" << 'EOF_DOMAIN_SCRIPT'
#!/bin/bash

# === n8n Domain Setup Script (Debian/Ubuntu Only) ===
# Configures Nginx reverse proxy and obtains SSL certificate using Certbot.
# Run *after* pointing your domain name to this server's IP.
#
# Usage for Production Certificate:
#   sudo bash /opt/n8n/setup-domain.sh your-n8n-domain.com
#
# Usage for Testing with Let's Encrypt Staging (avoids rate limits):
#   sudo bash /opt/n8n/setup-domain.sh your-n8n-domain.com --staging

set -euo pipefail

# --- Configuration ---
DOMAIN="$1"
MODE="${2:-production}" # Default to production if second arg is missing
N8N_INTERNAL_PORT=5678 # n8n runs on this port inside Docker/on localhost
LOG_FILE="/var/log/n8n-domain-setup.log"
NGINX_SITES_DIR="/etc/nginx/sites-available"
NGINX_SYMLINK_DIR="/etc/nginx/sites-enabled"
CERTBOT_STAGING_FLAG="" # Initialize staging flag as empty
# --- End Configuration ---

# --- Input Validation & Mode Check ---
if [ -z "$DOMAIN" ]; then
    echo "ERROR: Domain name not provided."
    echo "Usage: sudo $0 <your-n8n-domain.com> [--staging]"
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
    echo "Usage: sudo $0 <your-n8n-domain.com> [--staging]"
    exit 1
fi
# --- End Input Validation & Mode Check ---

# --- Logging Setup ---
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== n8n Domain Setup Started ==="
echo "Date: $(date)"
echo "Domain: $DOMAIN"
echo "Mode: ${MODE/--/}" # Display 'staging' or 'production'
echo "n8n Internal Port: $N8N_INTERNAL_PORT"
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
rm -f "$NGINX_SYMLINK_DIR/default" # Remove default site symlink

# Nginx config for n8n, including WebSocket support and larger client body size
cat > "$NGINX_SITES_DIR/$DOMAIN.conf" << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    root /var/www/html; # Default root for certbot challenges

    # Increase max body size for potential large file uploads in workflows
    client_max_body_size 100M;

    location /.well-known/acme-challenge/ {
        # Let certbot handle this location
    }

    location / {
        proxy_pass http://127.0.0.1:$N8N_INTERNAL_PORT; # Proxy to n8n container
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket support (crucial for n8n UI)
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        # Increase timeouts for potentially long-running workflows
        proxy_read_timeout 3600s; # 1 hour, adjust if needed
        proxy_send_timeout 3600s;
    }
}
EOF

log_domain "INFO" "Enabling Nginx site configuration for $DOMAIN..."
ln -sf "$NGINX_SITES_DIR/$DOMAIN.conf" "$NGINX_SYMLINK_DIR/$DOMAIN.conf"

log_domain "INFO" "Testing INITIAL Nginx configuration..."
if ! nginx -t; then
    log_domain "ERROR" "INITIAL Nginx configuration test failed. Check $NGINX_SITES_DIR/$DOMAIN.conf"
    exit 1
fi
log_domain "INFO" "INITIAL Nginx configuration test successful."

log_domain "INFO" "Reloading Nginx to apply INITIAL configuration..."
# Ensure Nginx service is running and enabled
systemctl enable --now nginx &>/dev/null
if ! systemctl reload nginx; then
    log_domain "ERROR" "Failed to reload Nginx."
    exit 1
fi
log_domain "INFO" "Nginx reloaded with config ready for Certbot validation & modification."

log_domain "INFO" "Attempting to obtain SSL certificate (Mode: ${MODE/--/}) and configure HTTPS using Certbot..."
ADMIN_EMAIL="admin@$DOMAIN" # Use a generic admin email, user might want to change this
log_domain "INFO" "Using email $ADMIN_EMAIL for Let's Encrypt registration/renewal notices."

# Construct the certbot command, including the staging flag if set
# --nginx: Use the Nginx plugin to automatically configure HTTPS
# -d: Specify the domain
# --non-interactive: Run without prompts
# --agree-tos: Agree to Let's Encrypt Terms of Service
# --email: Provide email for registration and recovery
# --redirect: Automatically redirect HTTP to HTTPS
CERTBOT_CMD="certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email $ADMIN_EMAIL --redirect $CERTBOT_STAGING_FLAG"
log_domain "INFO" "Running Certbot command: $CERTBOT_CMD"

if ! $CERTBOT_CMD; then
    log_domain "ERROR" "Certbot failed to obtain/install certificate or configure Nginx."
    log_domain "ERROR" "Check Certbot logs (/var/log/letsencrypt/letsencrypt.log) and Nginx logs."
    log_domain "ERROR" "Ensure your domain '$DOMAIN' correctly points to this server's IP and DNS has propagated."
    exit 1
fi
log_domain "INFO" "Certbot successfully obtained certificate and configured Nginx for HTTPS."

log_domain "INFO" "Testing FINAL Nginx configuration (after Certbot)..."
if ! nginx -t; then
    log_domain "ERROR" "FINAL Nginx configuration test failed after Certbot modifications."
    # Attempt to reload anyway, but warn
    systemctl reload nginx || log_domain "WARN" "Failed to reload Nginx after failed final test."
    exit 1
fi
log_domain "INFO" "FINAL Nginx configuration test successful."

log_domain "INFO" "Reloading Nginx one last time to ensure all changes are active..."
if ! systemctl reload nginx; then
    log_domain "WARN" "Failed to reload Nginx after final configuration check."
fi

log_domain "INFO" "Checking Certbot auto-renewal..."
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
    log_domain "WARN" "  sudo bash $0 $DOMAIN"
fi
log_domain "SUCCESS" "n8n should now be accessible at: https://$DOMAIN"
log_domain "INFO" "Nginx is configured as a reverse proxy with SSL."
log_domain "INFO" "You might need to update n8n's environment variables (e.g., WEBHOOK_URL) if they depend on the domain."
log_domain "INFO" "   -> Edit /etc/systemd/system/n8n.service"
log_domain "INFO" "   -> Run: sudo systemctl daemon-reload && sudo systemctl restart n8n"
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
    ip=$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null) || \
    ip=$(curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null) || \
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
    configure_firewall # Configure for direct n8n port access
    setup_docker_service # Creates volume, pulls image, configures and starts service
    create_domain_script # Create the *optional* script with the staging flag logic

    PUBLIC_IP=$(get_public_ip)

    # --- Final Output Message ---
    log "SUCCESS" "========================================================"
    log "SUCCESS" " n8n Installation Complete!"
    log "SUCCESS" "========================================================"
    log "INFO" " "
    log "INFO" " n8n is running in a Docker container managed by systemd."
    log "INFO" " Data is persisted in the Docker volume: $DOCKER_VOLUME_NAME"
    log "INFO" " "
    log "INFO" " You can access it directly via the server's IP address:"
    log "INFO" " -> http://${PUBLIC_IP}:${N8N_PORT}  (HTTP only)"
    log "INFO" " "
    log "INFO" " Firewall Status (Port ${N8N_PORT} for direct access):"
    # --- Check UFW Status ---
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -qw active; then
             if ufw status verbose | grep -q "${N8N_PORT}/tcp.*ALLOW IN"; then
                 log "INFO" " -> UFW is ACTIVE and allows incoming connections on port ${N8N_PORT}."
             else
                 log "WARN" " -> UFW is ACTIVE but the rule for port ${N8N_PORT} seems missing or incorrect."
                 log "WARN" "    Run 'sudo ufw status verbose' to check."
             fi
        else
             log "WARN" " -> UFW is installed but INACTIVE. Rule for port ${N8N_PORT} is not enforced."
             log "WARN" "    Consider running 'sudo ufw enable' after logging in if you need the firewall."
        fi
    else
         log "WARN" " -> UFW firewall is not installed. Access to port ${N8N_PORT} depends on your cloud provider's firewall settings."
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
    log "INFO" " 3. Wait for DNS propagation (can take minutes to hours)."
    log "INFO" " "
    log "INFO" " How to run the setup script:"
    log "INFO" " 1. SSH into this server: ssh <user>@${PUBLIC_IP}"
    log "INFO" " 2. Run ONE of the following commands:"
    log "INFO" " "
    log "INFO" "    a) For a PRODUCTION certificate (standard usage):"
    log "INFO" "       sudo bash ${DOMAIN_SETUP_SCRIPT} your-n8n-domain.com"
    log "INFO" "       (Replace 'your-n8n-domain.com' with your actual domain)"
    log "INFO" " "
    log "INFO" "    b) For TESTING with a STAGING certificate:"
    log "INFO" "       sudo bash ${DOMAIN_SETUP_SCRIPT} your-n8n-domain.com --staging"
    log "INFO" "       - Use this to test without hitting Let's Encrypt rate limits."
    log "INFO" "       - Staging certificates are NOT TRUSTED by browsers."
    log "INFO" "       - You MUST clean up staging certs before getting a production one."
    log "INFO" " "
    log "INFO" " The script will:"
    log "INFO" " - Install Nginx and Certbot."
    log "INFO" " - Configure Nginx as a reverse proxy for n8n (with WebSocket support)."
    log "INFO" " - Request and install the SSL certificate."
    log "INFO" " - Configure the firewall (UFW) for ports 80 (HTTP) and 443 (HTTPS)."
    log "INFO" " - After running, you may want to set n8n environment variables like"
    log "INFO" "   WEBHOOK_URL=https://your-n8n-domain.com/ in /etc/systemd/system/n8n.service"
    log "INFO" "   and restart n8n ('sudo systemctl daemon-reload && sudo systemctl restart n8n')."
    log "INFO" " "
    log "INFO" "========================================================"
    log "INFO" " Managing the n8n Service"
    log "INFO" "========================================================"
    log "INFO" " - Status: sudo systemctl status n8n"
    log "INFO" " - Stop:   sudo systemctl stop n8n"
    log "INFO" " - Start:  sudo systemctl start n8n"
    log "INFO" " - Restart:sudo systemctl restart n8n"
    log "INFO" " - Logs:   sudo journalctl -u n8n -f"
    log "INFO" " "
    log "INFO" "========================================================"
    log "INFO" " Updating n8n"
    log "INFO" "========================================================"
    log "INFO" " The systemd service is configured to pull the latest image on start/restart."
    log "INFO" " To manually update:"
    log "INFO" " 1. Pull the latest Docker image:"
    log "INFO" "    sudo docker pull ${DOCKER_IMAGE}"
    log "INFO" " 2. Restart the service to use the new image:"
    log "INFO" "    sudo systemctl restart n8n"
    log "INFO" " (Alternatively, just restarting the service might be sufficient if ExecStartPre includes docker pull)"
    log "INFO" " "
    log "INFO" "========================================================"
    log "INFO" " Log Files"
    log "INFO" "========================================================"
    log "INFO" " - This installation script log: ${LOG_FILE}"
    log "INFO" " - Domain setup script log (if run): /var/log/n8n-domain-setup.log"
    log "INFO" " - n8n service logs: sudo journalctl -u n8n"
    log "INFO" " ========================================================"
}

# --- Run Main ---
# Wrap main execution in a block to ensure logs capture everything, even early exits
{
    main
    log "INFO" "Init script finished successfully."
} || {
    # Log failure if main() exits with non-zero status due to set -e
    log "ERROR" "n8n Init Script failed. Check logs above for details: $LOG_FILE"
    exit 1
}

exit 0
# --- End Script ---
