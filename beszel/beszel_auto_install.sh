#!/bin/bash

# === Beszel Hub Auto-Installation Init Script ===
# This script automatically installs Beszel Hub during server initialization
# A separate script is provided for configuring domain and HTTPS after deployment

# Enable command tracing for detailed logs
set -x

# Define log files
LOG_FILE="/root/beszel-installation.log"
DETAILED_LOG="/tmp/beszel-init.log"

# Start logging
{
    echo "===== Beszel Hub Installation Started ====="
    echo "Date: $(date)"
    echo "Hostname: $(hostname)"
    echo ""
} > $LOG_FILE

# Define installation parameters
PORT=8090                              # Default port
GITHUB_PROXY_URL="https://ghfast.top/" # Default proxy URL

# Ensure the proxy URL ends with a trailing slash
ensure_trailing_slash() {
  if [ -n "$1" ]; then
    case "$1" in
    */) echo "$1" ;;
    *) echo "$1/" ;;
    esac
  else
    echo "$1"
  fi
}

GITHUB_PROXY_URL=$(ensure_trailing_slash "$GITHUB_PROXY_URL")

# Detect operating system type
if [ -f /etc/debian_version ]; then
    OS_TYPE="debian"
    PKG_MANAGER="apt-get"
elif [ -f /etc/centos-release ] || [ -f /etc/redhat-release ]; then
    OS_TYPE="centos"
    PKG_MANAGER="yum"
elif [ -f /etc/arch-release ]; then
    OS_TYPE="arch"
    PKG_MANAGER="pacman"
else
    {
        echo "[WARNING] Unsupported OS detected. Proceeding with best-effort installation."
        echo ""
    } >> $LOG_FILE
    # Continue anyway as we'll try with available package managers
fi

{
    echo "[STEP 1] Operating System Detected: $OS_TYPE"
    echo ""
} >> $LOG_FILE

# --- Install Required Packages ---
{
    echo "[STEP 2] Installing required packages (tar and curl)..."
} >> $LOG_FILE

if [ "$OS_TYPE" == "debian" ]; then
    export DEBIAN_FRONTEND=noninteractive
    $PKG_MANAGER update -y >> $DETAILED_LOG 2>&1
    $PKG_MANAGER install -y tar curl >> $DETAILED_LOG 2>&1
elif [ "$OS_TYPE" == "centos" ]; then
    $PKG_MANAGER install -y tar curl >> $DETAILED_LOG 2>&1
elif [ "$OS_TYPE" == "arch" ]; then
    $PKG_MANAGER -Sy --noconfirm tar curl >> $DETAILED_LOG 2>&1
else
    # Try commonly available package managers
    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y >> $DETAILED_LOG 2>&1
        apt-get install -y tar curl >> $DETAILED_LOG 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y tar curl >> $DETAILED_LOG 2>&1
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm tar curl >> $DETAILED_LOG 2>&1
    else
        {
            echo "[WARNING] Could not determine package manager. Please ensure 'tar' and 'curl' are installed."
            echo ""
        } >> $LOG_FILE
    fi
fi

{
    echo "[STEP 2] Required packages installation completed."
    echo ""
} >> $LOG_FILE

# --- Create Dedicated User ---
{
    echo "[STEP 3] Creating dedicated user for Beszel Hub service..."
} >> $LOG_FILE

if ! id -u beszel >/dev/null 2>&1; then
    useradd -M -s /bin/false beszel >> $DETAILED_LOG 2>&1
    {
        echo "[STEP 3] Dedicated user 'beszel' created successfully."
    } >> $LOG_FILE
else
    {
        echo "[STEP 3] User 'beszel' already exists. Skipping user creation."
    } >> $LOG_FILE
fi
echo "" >> $LOG_FILE

# --- Download and Install Beszel Hub ---
{
    echo "[STEP 4] Downloading and installing Beszel Hub..."
} >> $LOG_FILE

mkdir -p /opt/beszel/beszel_data >> $DETAILED_LOG 2>&1

# Determine system architecture and OS for download
SYS_OS=$(uname -s)
SYS_ARCH=$(uname -m | sed 's/x86_64/amd64/' | sed 's/armv7l/arm/' | sed 's/aarch64/arm64/')
DOWNLOAD_URL="${GITHUB_PROXY_URL}https://github.com/henrygd/beszel/releases/latest/download/beszel_${SYS_OS}_${SYS_ARCH}.tar.gz"

{
    echo "[INFO] Downloading from: $DOWNLOAD_URL"
} >> $LOG_FILE

# Download, extract, and install
if ! curl -sL "$DOWNLOAD_URL" | tar -xz -O beszel > /opt/beszel/beszel 2>> $DETAILED_LOG; then
    {
        echo "[ERROR] Failed to download and extract Beszel Hub. Please check network connectivity and URL."
        echo "Download URL was: $DOWNLOAD_URL"
        echo ""
    } >> $LOG_FILE
    exit 1
fi

chmod +x /opt/beszel/beszel >> $DETAILED_LOG 2>&1
chown -R beszel:beszel /opt/beszel >> $DETAILED_LOG 2>&1

{
    echo "[STEP 4] Beszel Hub downloaded and installed successfully."
    echo ""
} >> $LOG_FILE

# --- Create Systemd Service ---
{
    echo "[STEP 5] Creating systemd service for Beszel Hub..."
} >> $LOG_FILE

cat > /etc/systemd/system/beszel-hub.service << EOF
[Unit]
Description=Beszel Hub Service
After=network.target

[Service]
ExecStart=/opt/beszel/beszel serve --http "0.0.0.0:$PORT"
WorkingDirectory=/opt/beszel
User=beszel
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

{
    echo "[STEP 5] Systemd service created successfully."
    echo ""
} >> $LOG_FILE

# --- Enable and Start Service ---
{
    echo "[STEP 6] Enabling and starting Beszel Hub service..."
} >> $LOG_FILE

systemctl daemon-reload >> $DETAILED_LOG 2>&1
systemctl enable beszel-hub.service >> $DETAILED_LOG 2>&1
systemctl start beszel-hub.service >> $DETAILED_LOG 2>&1

# Wait for service to start
sleep 5

# Check if service is running
if systemctl is-active --quiet beszel-hub.service; then
    {
        echo "[STEP 6] Beszel Hub service started successfully."
        echo ""
    } >> $LOG_FILE
else
    {
        echo "[ERROR] Failed to start Beszel Hub service. Check systemd service logs with 'journalctl -u beszel-hub.service'"
        echo "Service status: $(systemctl status beszel-hub.service | grep Active)"
        echo ""
    } >> $LOG_FILE
fi

# --- Create post-installation domain setup script ---
{
    echo "[STEP 7] Creating domain setup script for later use..."
} >> $LOG_FILE

cat > /opt/beszel/setup-domain.sh << 'EOF'
#!/bin/bash

# Script to configure domain and HTTPS for Beszel Hub post-installation
# IMPORTANT: DNS records must be properly configured before running this script.
#            Your domain should already be pointing to this server's IP address.

LOG_FILE="/root/beszel-domain-setup.log"

# Check if domain argument is provided
if [ $# -ne 1 ]; then
    echo "Error: Missing domain name"
    echo "Usage: $0 your-domain.com"
    echo ""
    echo "IMPORTANT: Before running this script, ensure that:"
    echo "1. DNS records for your domain are properly configured"
    echo "2. Your domain is already pointing to this server's IP address"
    echo "3. DNS changes have had time to propagate (may take up to 24-48 hours)"
    exit 1
fi

DOMAIN="$1"

# Start logging
{
    echo "===== Beszel Hub Domain Setup Started ====="
    echo "Date: $(date)"
    echo "Domain: $DOMAIN"
    echo ""
    echo "IMPORTANT: This script assumes DNS records are already configured."
    echo "If setup fails, please verify your DNS configuration and try again."
    echo ""
} > $LOG_FILE

# Detect OS
if [ -f /etc/debian_version ]; then
    PKG_MANAGER="apt-get"
    NGINX_USER="www-data"
elif [ -f /etc/centos-release ] || [ -f /etc/redhat-release ]; then
    PKG_MANAGER="yum"
    NGINX_USER="nginx"
else
    if command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER="apt-get"
        NGINX_USER="www-data"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
        NGINX_USER="nginx"
    else
        echo "Error: Unsupported OS"
        exit 1
    fi
fi

# Install Nginx and Certbot if not already installed
if ! command -v nginx >/dev/null 2>&1 || ! command -v certbot >/dev/null 2>&1; then
    {
        echo "[STEP 1] Installing Nginx and Certbot..."
    } >> $LOG_FILE
    
    if [ "$PKG_MANAGER" = "apt-get" ]; then
        export DEBIAN_FRONTEND=noninteractive
        $PKG_MANAGER update -y
        $PKG_MANAGER install -y nginx certbot python3-certbot-nginx
    elif [ "$PKG_MANAGER" = "yum" ]; then
        # Enable EPEL repository for CentOS/RHEL
        $PKG_MANAGER install -y epel-release
        $PKG_MANAGER install -y nginx certbot python3-certbot-nginx
    fi
    
    {
        echo "[STEP 1] Nginx and Certbot installed."
        echo ""
    } >> $LOG_FILE
else
    {
        echo "[STEP 1] Nginx and Certbot already installed."
        echo ""
    } >> $LOG_FILE
fi

# Get port from Beszel service
PORT=$(grep -o "\-\-http.*:[0-9]\+" /etc/systemd/system/beszel-hub.service | grep -o "[0-9]\+$")
if [ -z "$PORT" ]; then
    PORT=8090
    {
        echo "[INFO] Could not determine port from service file. Using default: $PORT"
    } >> $LOG_FILE
fi

# Verify that DNS is correctly pointing to this server
# Get both IPv4 and IPv6 addresses
IPV4_SERVER=$(curl -s -4 ifconfig.me 2>/dev/null || echo "")
IPV6_SERVER=$(curl -s -6 ifconfig.me 2>/dev/null || echo "")
IPV4_DOMAIN=$(dig +short A $DOMAIN 2>/dev/null || echo "")
IPV6_DOMAIN=$(dig +short AAAA $DOMAIN 2>/dev/null || echo "")

{
    echo "[INFO] Server IPv4: $IPV4_SERVER"
    echo "[INFO] Server IPv6: $IPV6_SERVER"
    echo "[INFO] Domain IPv4: $IPV4_DOMAIN"
    echo "[INFO] Domain IPv6: $IPV6_DOMAIN"
} >> $LOG_FILE

# Check if any of the domain IPs match any of the server IPs
MATCH_FOUND=false
if [ -n "$IPV4_SERVER" ] && [ -n "$IPV4_DOMAIN" ] && [ "$IPV4_SERVER" = "$IPV4_DOMAIN" ]; then
    MATCH_FOUND=true
    echo "Domain IPv4 record matches server IPv4 address."
fi

if [ -n "$IPV6_SERVER" ] && [ -n "$IPV6_DOMAIN" ] && [ "$IPV6_SERVER" = "$IPV6_DOMAIN" ]; then
    MATCH_FOUND=true
    echo "Domain IPv6 record matches server IPv6 address."
fi

if [ "$MATCH_FOUND" = "false" ]; then
    {
        echo "[WARNING] The domain $DOMAIN does not appear to point to this server."
        echo "IPv4 - Server: $IPV4_SERVER, Domain: $IPV4_DOMAIN"
        echo "IPv6 - Server: $IPV6_SERVER, Domain: $IPV6_DOMAIN"
        echo "The certificate process may fail. Please update your DNS records."
        echo ""
    } >> $LOG_FILE
    echo "WARNING: $DOMAIN does not appear to point to this server."
    echo "IPv4 - Server: $IPV4_SERVER, Domain: $IPV4_DOMAIN"
    echo "IPv6 - Server: $IPV6_SERVER, Domain: $IPV6_DOMAIN"
    echo ""
    echo "IMPORTANT: DNS records must be properly configured before proceeding."
    echo "This typically means:"
    echo "1. Creating an A record pointing to the server's IPv4 address"
    echo "2. Optionally creating an AAAA record for the IPv6 address"
    echo "3. Allowing time for DNS changes to propagate (up to 24-48 hours)"
    echo ""
    read -p "Continue anyway? (y/n): " CONTINUE
    if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
        echo "Aborted. Please update your DNS records and try again."
        exit 1
    fi
fi

# Update Beszel Hub service to listen only on localhost
{
    echo "[STEP 2] Updating Beszel Hub service to listen on localhost only..."
} >> $LOG_FILE

# Check if service is already configured correctly
if grep -q "127.0.0.1:$PORT" /etc/systemd/system/beszel-hub.service; then
    {
        echo "[STEP 2] Service already configured correctly."
        echo ""
    } >> $LOG_FILE
else
    # Update the service file - avoid nested quotes that cause systemd errors
    sed -i "s|^ExecStart=.*$|ExecStart=/opt/beszel/beszel serve --http 127.0.0.1:$PORT|" /etc/systemd/system/beszel-hub.service
    
    # Reload and restart service
    systemctl daemon-reload
    systemctl restart beszel-hub.service
    
    {
        echo "[STEP 2] Service updated and restarted."
        echo ""
    } >> $LOG_FILE
fi

# Configure Nginx as reverse proxy
{
    echo "[STEP 3] Configuring Nginx as reverse proxy for domain: $DOMAIN"
} >> $LOG_FILE

# Create Nginx configuration
cat > /etc/nginx/conf.d/beszel.conf << NEOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NEOF

# Test Nginx configuration
nginx -t
if [ $? -ne 0 ]; then
    {
        echo "[ERROR] Nginx configuration test failed."
        echo ""
    } >> $LOG_FILE
    echo "Error: Nginx configuration test failed. Check syntax and try again."
    exit 1
fi

# Reload Nginx
systemctl restart nginx

{
    echo "[STEP 3] Nginx configured and reloaded."
    echo ""
} >> $LOG_FILE

# Request Let's Encrypt certificate
{
    echo "[STEP 4] Requesting Let's Encrypt certificate for $DOMAIN..."
} >> $LOG_FILE

# Request certificate
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN" --redirect

if [ $? -eq 0 ]; then
    {
        echo "[STEP 4] Let's Encrypt certificate obtained successfully."
        echo ""
    } >> $LOG_FILE
else
    {
        echo "[ERROR] Failed to obtain Let's Encrypt certificate."
        echo "This is often due to DNS not being properly configured or not having enough time to propagate."
        echo ""
    } >> $LOG_FILE
    echo "Error: Failed to obtain Let's Encrypt certificate."
    echo "This is typically because:"
    echo "1. DNS records are not correctly pointing to this server"
    echo "2. DNS changes haven't had enough time to propagate"
    echo "3. Let's Encrypt rate limits have been reached"
    echo ""
    echo "You can try manually with: certbot --nginx -d $DOMAIN"
    exit 1
fi

# Set up auto-renewal if not already configured
{
    echo "[STEP 5] Setting up automatic certificate renewal..."
} >> $LOG_FILE

# Check if crontab entry already exists
if crontab -l 2>/dev/null | grep -q "certbot renew"; then
    {
        echo "[STEP 5] Automatic renewal already configured."
        echo ""
    } >> $LOG_FILE
else
    # Create crontab entry for certificate renewal
    (crontab -l 2>/dev/null || echo "") | { cat; echo "0 3 * * * certbot renew --quiet --deploy-hook 'systemctl reload nginx'"; } | crontab -
    
    {
        echo "[STEP 5] Automatic certificate renewal configured."
        echo ""
    } >> $LOG_FILE
fi

# Test the setup
{
    echo "[STEP 6] Testing the setup..."
} >> $LOG_FILE

if curl -s -I "https://$DOMAIN" | grep -q "200 OK\|301 Moved Permanently\|302 Found"; then
    {
        echo "[STEP 6] Setup successful. HTTPS is working correctly."
        echo ""
    } >> $LOG_FILE
    echo "Success! Beszel Hub is now configured with HTTPS at https://$DOMAIN"
else
    {
        echo "[WARNING] Could not verify HTTPS is working. Please check manually."
        echo ""
    } >> $LOG_FILE
    echo "Setup completed, but automatic verification failed."
    echo "Please manually check https://$DOMAIN"
fi

# Summary
{
    echo "==============================="
    echo "🎉 Beszel Hub Domain Setup Complete!"
    echo ""
    echo "Beszel Hub is now accessible at:"
    echo "    https://$DOMAIN"
    echo ""
    echo "Certificate will auto-renew via cron job."
    echo ""
    echo "Official Documentation: https://beszel.dev/guide/getting-started"
    echo "==============================="
} >> $LOG_FILE

echo "Beszel Hub domain setup completed. See $LOG_FILE for details."
EOF

chmod +x /opt/beszel/setup-domain.sh

{
    echo "[STEP 7] Domain setup script created at /opt/beszel/setup-domain.sh"
    echo ""
} >> $LOG_FILE

# --- Installation Summary ---
SERVER_IP=$(hostname -I | awk '{print $1}')
{
    echo "==============================="
    echo "📊 Beszel Hub Installation Complete!"
    echo ""
    echo "Beszel Hub is now accessible at:"
    echo "    http://$SERVER_IP:$PORT"
    echo ""
    echo "IMPORTANT: To configure HTTPS with a domain name:"
    echo "1. Set up DNS records to point your domain to this server's IP: $SERVER_IP"
    echo "2. Wait for DNS changes to propagate (may take up to 24-48 hours)"
    echo "3. Run the domain setup script:"
    echo "    /opt/beszel/setup-domain.sh your-domain.com"
    echo ""
    echo "To check service status: systemctl status beszel-hub.service"
    echo "To view logs: journalctl -u beszel-hub.service"
    echo ""
    echo "Official Documentation: https://beszel.dev/guide/getting-started"
    echo "==============================="
} >> $LOG_FILE

echo "Beszel Hub installation completed. See $LOG_FILE for details."
