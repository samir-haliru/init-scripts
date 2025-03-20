#!/bin/bash

set -euo pipefail
LOG_FILE="/var/log/beszel-install.log"
DOCKER_IMAGE="henrygd/beszel:latest"
BESZEL_PORT=8090
DATA_DIR="/opt/beszel/beszel_data"

# Logging
log() {
    local level=$1
    local msg=$2
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $msg"
}

# OS detection and prep
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case $ID in
            debian|ubuntu) 
                OS_TYPE="debian"
                PKG_MANAGER="apt-get"
                ;;
            centos|rhel|almalinux|rocky|fedora) 
                OS_TYPE="centos"
                PKG_MANAGER="yum"
                ;;
            arch) 
                OS_TYPE="arch"
                PKG_MANAGER="pacman"
                ;;
            *) log "ERROR" "Unsupported OS: $ID"; exit 1 ;;
        esac
        log "INFO" "Detected OS: $ID $VERSION_ID"
    else
        log "ERROR" "Could not detect OS"; exit 1
    fi
}

# System prep
prepare_system() {
    log "INFO" "Preparing system..."
    
    # Create dedicated user
    if ! id -u beszel &>/dev/null; then
        useradd -Mr -s /usr/sbin/nologin beszel
        log "INFO" "Created beszel user"
    fi
    
    # Create data directory
    mkdir -p "$DATA_DIR"
    chown -R beszel:beszel "$DATA_DIR"
    log "INFO" "Prepared data directory: $DATA_DIR"
}

# Compatibility function for backward compatibility
install_docker() {
    log "INFO" "Using compatibility function: install_docker -> install_container_engine"
    install_container_engine
}

# Docker installation
install_docker() {
    log "INFO" "Installing Docker..."
    
    case $OS_TYPE in
        debian)
            apt-get update -y >> "$LOG_FILE" 2>&1
            apt-get install -y docker.io >> "$LOG_FILE" 2>&1
            systemctl enable --now docker >> "$LOG_FILE" 2>&1
            ;;
        centos)
            # For CentOS Stream 9 and other modern systems, use Docker CE repository
            if [[ "$VERSION_ID" =~ ^9 ]] || [[ "$VERSION_ID" =~ ^[1-9][0-9]+$ ]]; then
                log "INFO" "Installing Docker CE on modern RHEL-based system..."
                # Install required packages
                $PKG_MANAGER install -y yum-utils >> "$LOG_FILE" 2>&1
                
                # Add Docker repository
                yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >> "$LOG_FILE" 2>&1
                
                # Install Docker CE
                $PKG_MANAGER install -y docker-ce docker-ce-cli containerd.io >> "$LOG_FILE" 2>&1
            else
                # For older CentOS versions
                $PKG_MANAGER install -y docker >> "$LOG_FILE" 2>&1
            fi
            
            systemctl enable --now docker >> "$LOG_FILE" 2>&1
            ;;
        arch)
            pacman -Sy --noconfirm docker >> "$LOG_FILE" 2>&1
            systemctl enable --now docker >> "$LOG_FILE" 2>&1
            ;;
    esac
    
    usermod -aG docker beszel >> "$LOG_FILE" 2>&1
    log "INFO" "Docker installation complete"
}

# Configure firewall to allow dashboard port
configure_firewall() {
    log "INFO" "Configuring firewall for Beszel port $BESZEL_PORT..."
    
    case $OS_TYPE in
        debian)
            # Check if UFW is installed
            if command -v ufw >/dev/null 2>&1; then
                ufw allow $BESZEL_PORT/tcp >> "$LOG_FILE" 2>&1
                if ufw status | grep -q "active"; then
                    log "INFO" "UFW is active and configured to allow port $BESZEL_PORT"
                else
                    log "WARN" "UFW rule added for port $BESZEL_PORT, but UFW is not active. Enable with 'ufw enable'"
                fi
            else
                log "WARN" "UFW not installed, skipping firewall configuration"
            fi
            ;;
        centos)
            # Check if firewalld is installed and active
            if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
                firewall-cmd --permanent --add-port=$BESZEL_PORT/tcp >> "$LOG_FILE" 2>&1
                firewall-cmd --reload >> "$LOG_FILE" 2>&1
                log "INFO" "Firewalld configured to allow port $BESZEL_PORT"
            else
                log "WARN" "Firewalld not active, skipping firewall configuration"
            fi
            ;;
        arch)
            # For arch, check if either UFW or firewalld is installed
            if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "active"; then
                ufw allow $BESZEL_PORT/tcp >> "$LOG_FILE" 2>&1
                ufw reload >> "$LOG_FILE" 2>&1
                log "INFO" "UFW configured to allow port $BESZEL_PORT"
            elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
                firewall-cmd --permanent --add-port=$BESZEL_PORT/tcp >> "$LOG_FILE" 2>&1
                firewall-cmd --reload >> "$LOG_FILE" 2>&1
                log "INFO" "Firewalld configured to allow port $BESZEL_PORT"
            else
                log "WARN" "No active firewall detected, skipping firewall configuration"
            fi
            ;;
    esac
}

# Docker service setup
setup_docker_service() {
    log "INFO" "Configuring Docker service..."
    
    cat > /etc/systemd/system/beszel.service <<EOF
[Unit]
Description=Beszel Hub Container
Requires=docker.service
After=docker.service

[Service]
TimeoutStartSec=0
Restart=always
ExecStartPre=-/usr/bin/docker exec beszel stop
ExecStartPre=-/usr/bin/docker rm beszel
ExecStart=/usr/bin/docker run \\
    --name beszel \\
    --restart unless-stopped \\
    -p $BESZEL_PORT:8090 \\
    -v $DATA_DIR:/beszel_data \\
    -e BESZEL_ENV=production \\
    $DOCKER_IMAGE

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable beszel
    systemctl start beszel
    
    log "INFO" "Docker service configured and started"
}

# Domain setup script
create_domain_script() {
    log "INFO" "Creating domain setup script..."
    
    # Ensure the directory exists
    mkdir -p /opt/beszel
    
    cat > /opt/beszel/setup-domain.sh << 'EOF_DOMAIN_SCRIPT'
#!/bin/bash
LOG_FILE="/var/log/beszel-domain-setup.log"
DOMAIN="$1"

# Validate input
if [ -z "$DOMAIN" ]; then
    echo "Usage: $0 <your-domain.com>"
    exit 1
fi

# Logging setup
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== Beszel Domain Setup Started ==="
echo "Date: $(date)"
echo "Domain: $DOMAIN"

# OS detection
if [ -f /etc/debian_version ]; then
    PKG_MANAGER="apt-get"
    FIREWALL_TYPE="ufw"
    OS_TYPE="debian"
elif [ -f /etc/redhat-release ] || [ -f /etc/almalinux-release ] || [ -f /etc/rocky-release ] || [ -f /etc/centos-release ]; then
    PKG_MANAGER="dnf"
    [ ! -x "$(command -v dnf)" ] && PKG_MANAGER="yum"
    FIREWALL_TYPE="firewalld"
    OS_TYPE="centos"
elif [ -f /etc/arch-release ]; then
    PKG_MANAGER="pacman"
    FIREWALL_TYPE="either"
    OS_TYPE="arch"
else
    echo "Unsupported OS"
    exit 1
fi

echo "Detected OS type: $OS_TYPE with package manager: $PKG_MANAGER"

# Install EPEL repository if this is a RHEL-based system
if [ "$OS_TYPE" = "centos" ]; then
    echo "Installing EPEL repository for RHEL-based system..."
    if ! $PKG_MANAGER repolist | grep -q "epel"; then
        $PKG_MANAGER install -y epel-release
    fi
    # Refresh package lists after adding the repository
    $PKG_MANAGER makecache
fi

# Install dependencies
echo "Updating package lists..."
if [ "$OS_TYPE" = "debian" ]; then
    $PKG_MANAGER update -y
elif [ "$OS_TYPE" = "centos" ]; then
    $PKG_MANAGER check-update || true
elif [ "$OS_TYPE" = "arch" ]; then
    $PKG_MANAGER -Sy
fi

echo "Installing required packages..."
if [ "$OS_TYPE" = "debian" ]; then
    $PKG_MANAGER install -y nginx certbot python3-certbot-nginx
elif [ "$OS_TYPE" = "centos" ]; then
    # Install nginx first
    if ! $PKG_MANAGER install -y nginx; then
        echo "Failed to install nginx. Aborting."
        exit 1
    fi
    
    # Enable and start nginx
    systemctl enable nginx
    systemctl start nginx
    
    # Then install certbot
    if ! $PKG_MANAGER install -y certbot python3-certbot-nginx; then
        echo "Failed to install certbot. Aborting."
        exit 1
    fi
elif [ "$OS_TYPE" = "arch" ]; then
    $PKG_MANAGER -S --noconfirm nginx certbot certbot-nginx
fi

# Verify nginx installation
if ! command -v nginx &>/dev/null; then
    echo "Nginx installation failed. Aborting."
    exit 1
fi

# Verify certbot installation
if ! command -v certbot &>/dev/null; then
    echo "Certbot installation failed. Aborting."
    exit 1
fi

# Create necessary directories
echo "Creating necessary directories..."
mkdir -p /etc/nginx/conf.d

# Configure firewall to allow ports 80 and 443
echo "Configuring firewall to allow HTTP/HTTPS ports..."
if [ "$FIREWALL_TYPE" = "ufw" ] && command -v ufw >/dev/null 2>&1; then
    if ! ufw status | grep -q "active"; then
        echo "Warning: UFW is not active. You may need to enable it manually."
    else
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw reload
        echo "UFW configured to allow ports 80 and 443"
    fi
elif [ "$FIREWALL_TYPE" = "firewalld" ] && command -v firewall-cmd >/dev/null 2>&1; then
    if ! systemctl is-active --quiet firewalld; then
        echo "Warning: Firewalld is not active. Attempting to enable..."
        systemctl enable --now firewalld
    fi
    
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https
    firewall-cmd --reload
    echo "Firewalld configured to allow HTTP and HTTPS services"
else
    echo "WARNING: No active firewall detected, or failed to configure firewall"
fi

# Handle different nginx config locations based on OS
if [ "$OS_TYPE" = "debian" ]; then
    NGINX_SITES_DIR="/etc/nginx/sites-enabled"
    # Remove default Nginx configuration if it exists
    rm -f "$NGINX_SITES_DIR/default"
else
    NGINX_SITES_DIR="/etc/nginx/conf.d"
fi

# Configure SELinux for Nginx (RHEL-based systems only)
if [ "$OS_TYPE" = "centos" ]; then
    echo "Configuring SELinux for Nginx proxy..."
    
    # Check if SELinux is enabled and enforcing
    if command -v sestatus >/dev/null && sestatus | grep -q "enabled" && [ "$(getenforce)" = "Enforcing" ]; then
        # Set the httpd boolean persistently
        if ! setsebool -P httpd_can_network_connect 1; then
            echo "WARNING: Failed to set SELinux boolean. Continuing but proxy might not work."
        else
            echo "SELinux policy updated: httpd_can_network_connect=1"
        fi
        
        # Optional: Add port mapping if needed
        # semanage port -a -t http_port_t -p tcp 8090
    else
        echo "SELinux not in enforcing mode, skipping policy update"
    fi
fi

# Configure Nginx
echo "Configuring Nginx..."
cat > "$NGINX_SITES_DIR/beszel.conf" << EOF
server {
    listen 80;
    server_name $DOMAIN;
    
    location / {
        proxy_pass http://127.0.0.1:8090;
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
EOF

# Test and reload Nginx
echo "Testing Nginx configuration..."
if ! nginx -t; then
    echo "Nginx configuration test failed. Aborting."
    exit 1
fi

echo "Reloading Nginx..."
systemctl reload nginx

# Obtain SSL certificate
echo "Obtaining SSL certificate..."
if ! certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN" --redirect; then
    echo "Certbot failed to obtain certificate. Aborting."
    exit 1
fi

# Setup auto-renewal
echo "Setting up auto-renewal..."
if ! crontab -l | grep -q "certbot renew"; then
    (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet") | crontab -
fi

echo "=== Setup Complete ==="
echo "Beszel Hub is now available at: https://$DOMAIN"
echo "Certificate auto-renewal configured"
EOF_DOMAIN_SCRIPT

    chmod +x /opt/beszel/setup-domain.sh
    log "INFO" "Domain setup script created at /opt/beszel/setup-domain.sh"
}

# Function to get public IP (with fallbacks)
get_public_ip() {
    # Try different methods to get public IP
    local public_ip
    
    # First try curl with timeout
    public_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null)
    
    # If curl failed, try dig
    if [ -z "$public_ip" ]; then
        public_ip=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null)
    fi
    
    # If both failed, fallback to local IP
    if [ -z "$public_ip" ]; then
        public_ip=$(hostname -I | awk '{print $1}')
    fi
    
    echo "$public_ip"
}

# Main Execution
main() {
    detect_os
    prepare_system
    install_docker
    configure_firewall 
    setup_docker_service
    create_domain_script
    
    PUBLIC_IP=$(get_public_ip)
    
    log "SUCCESS" "Installation complete!"
    log "INFO" "Beszel Hub is running on port $BESZEL_PORT"
    log "INFO" "Firewall configured to allow connections to port $BESZEL_PORT"
    log "INFO" "Beszel Hub is available at: http://${PUBLIC_IP}:${BESZEL_PORT}"
    log "INFO" "To configure HTTPS: /opt/beszel/setup-domain.sh yourdomain.com (will configure ports 80/443)"
    log "INFO" "To update Beszel: docker pull henrygd/beszel:latest && systemctl restart beszel"
}

main "$@" >> "$LOG_FILE" 2>&1
