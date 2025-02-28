#!/bin/bash

# === Configuration (modify these values as needed) ===
# Server Configuration
OVPN_PORT="1194"         # OpenVPN port (default: 1194)
OVPN_PROTOCOL="udp"      # Protocol: udp or tcp (default: udp)
DNS_SERVERS="1.1.1.1"    # DNS server for clients (default: Cloudflare)

# Client Configuration
CLIENT_NAME="client1"    # Name of the client configuration file

# Paths
LOG_FILE="/root/openvpn-setup.log"
OVPN_DIR="/etc/openvpn"
CLIENT_DIR="${OVPN_DIR}/clients"
EASY_RSA_DIR="${OVPN_DIR}/easy-rsa"

# === Logging Functions ===
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"
}

log_step() {
    local message="$1"
    echo "[$(get_timestamp)] $message" >> "$LOG_FILE"
}

log_error() {
    local message="$1"
    echo "[$(get_timestamp)] ERROR: $message" >> "$LOG_FILE"
}

handle_error() {
    local step="$1"
    local error="$2"
    log_error "Failed at: $step"
    log_error "Error code: $error"
    exit 1
}

# === Start Installation ===
{
    log_step "OpenVPN Server Installation Started"
} > "$LOG_FILE"

# --- Step 1: System Preparation ---
log_step "Beginning system preparation..."

# Update system
log_step "Updating package lists..."
export DEBIAN_FRONTEND=noninteractive
apt-get update || handle_error "Updating package lists" "$?"
log_step "Package lists updated successfully"

# Install dependencies
log_step "Installing required packages..."
apt-get install -y openvpn easy-rsa || handle_error "Installing packages" "$?"
log_step "Required packages installed successfully"

# Enable IP forwarding
log_step "Enabling IP forwarding..."
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-openvpn.conf
sysctl --system || handle_error "Enabling IP forwarding" "$?"

# Configure networking and NAT
log_step "Configuring networking and NAT rules..."

# Configure IP forwarding first
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-openvpn.conf
sysctl -p /etc/sysctl.d/99-openvpn.conf || handle_error "Enabling IP forwarding" "$?"

# Install iptables-persistent without prompts
export DEBIAN_FRONTEND=noninteractive
apt-get install -y iptables-persistent || handle_error "Installing iptables-persistent" "$?"

# Get default interface
DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}')
if [ -z "$DEFAULT_IFACE" ]; then
    DEFAULT_IFACE="eth0"  # Fallback to eth0 if no default interface found
    log_step "No default interface found, using fallback: eth0"
fi

# Flush existing rules
iptables -t nat -F
iptables -t nat -X

# Setup NAT rules
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$DEFAULT_IFACE" -j MASQUERADE || handle_error "Setting up NAT rules" "$?"

# Save rules
netfilter-persistent save || handle_error "Saving iptables rules" "$?"

# Double check IP forwarding is enabled
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
    echo 1 > /proc/sys/net/ipv4/ip_forward
fi

log_step "Network configuration and NAT rules set up successfully using interface: $DEFAULT_IFACE"

log_step "System preparation completed successfully"

# --- Step 2: OpenVPN Configuration ---
log_step "Beginning OpenVPN configuration..."

# Setup EasyRSA
log_step "Setting up EasyRSA..."
mkdir -p "$EASY_RSA_DIR"
cp -r /usr/share/easy-rsa/* "$EASY_RSA_DIR/" || handle_error "Copying EasyRSA files" "$?"
cd "$EASY_RSA_DIR" || handle_error "Changing to EasyRSA directory" "$?"

# Initialize PKI
log_step "Initializing PKI..."
./easyrsa init-pki || handle_error "Initializing PKI" "$?"
echo "yes" | ./easyrsa build-ca nopass || handle_error "Building CA" "$?"
log_step "PKI initialized successfully"

# Generate server certificates
log_step "Generating server certificates..."
echo "yes" | ./easyrsa gen-req server nopass || handle_error "Generating server request" "$?"
echo "yes" | ./easyrsa sign-req server server || handle_error "Signing server request" "$?"
./easyrsa gen-dh || handle_error "Generating DH params" "$?"
openvpn --genkey secret ta.key || handle_error "Generating TLS auth key" "$?"
log_step "Server certificates generated successfully"

# Create server config
log_step "Creating server configuration..."
cat > "$OVPN_DIR/server.conf" << EOF
port $OVPN_PORT
proto $OVPN_PROTOCOL
dev tun
ca $EASY_RSA_DIR/pki/ca.crt
cert $EASY_RSA_DIR/pki/issued/server.crt
key $EASY_RSA_DIR/pki/private/server.key
dh $EASY_RSA_DIR/pki/dh.pem
server 10.8.0.0 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS $DNS_SERVERS"
keepalive 10 120
tls-auth $EASY_RSA_DIR/ta.key 0
cipher AES-256-GCM
auth SHA256
user nobody
group nogroup
persist-key
persist-tun
status /var/log/openvpn/openvpn-status.log
verb 3
EOF
log_step "Server configuration created successfully"

# Create client config directory
mkdir -p "$CLIENT_DIR"

# --- Step 3: Generate Client Configurations ---
log_step "Generating client configurations..."

# Create client config template
cat > "$CLIENT_DIR/client.template" << EOF
client
dev tun
proto $OVPN_PROTOCOL
remote SERVER_IP $OVPN_PORT
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA256
key-direction 1
verb 3
EOF

# Get server IP
SERVER_IP=$(curl -s https://api.ipify.org)
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(hostname -I | cut -d' ' -f1)
fi

# Generate client configuration
log_step "Generating configuration for $CLIENT_NAME..."
    
# Generate client certificates
echo "yes" | ./easyrsa gen-req "$CLIENT_NAME" nopass || handle_error "Generating client request" "$?"
echo "yes" | ./easyrsa sign-req client "$CLIENT_NAME" || handle_error "Signing client request" "$?"

# Create client config
cp "$CLIENT_DIR/client.template" "$CLIENT_DIR/$CLIENT_NAME.ovpn"
sed -i "s/SERVER_IP/$SERVER_IP/" "$CLIENT_DIR/$CLIENT_NAME.ovpn"

# Append certificates
echo "<ca>" >> "$CLIENT_DIR/$CLIENT_NAME.ovpn"
cat "$EASY_RSA_DIR/pki/ca.crt" >> "$CLIENT_DIR/$CLIENT_NAME.ovpn"
echo "</ca>" >> "$CLIENT_DIR/$CLIENT_NAME.ovpn"

echo "<cert>" >> "$CLIENT_DIR/$CLIENT_NAME.ovpn"
cat "$EASY_RSA_DIR/pki/issued/$CLIENT_NAME.crt" >> "$CLIENT_DIR/$CLIENT_NAME.ovpn"
echo "</cert>" >> "$CLIENT_DIR/$CLIENT_NAME.ovpn"

echo "<key>" >> "$CLIENT_DIR/$CLIENT_NAME.ovpn"
cat "$EASY_RSA_DIR/pki/private/$CLIENT_NAME.key" >> "$CLIENT_DIR/$CLIENT_NAME.ovpn"
echo "</key>" >> "$CLIENT_DIR/$CLIENT_NAME.ovpn"

echo "<tls-auth>" >> "$CLIENT_DIR/$CLIENT_NAME.ovpn"
cat "$EASY_RSA_DIR/ta.key" >> "$CLIENT_DIR/$CLIENT_NAME.ovpn"
echo "</tls-auth>" >> "$CLIENT_DIR/$CLIENT_NAME.ovpn"

log_step "Configuration for $CLIENT_NAME generated successfully"

# --- Step 4: Start OpenVPN Service ---
log_step "Starting OpenVPN service..."
systemctl enable openvpn@server || handle_error "Enabling OpenVPN service" "$?"
systemctl start openvpn@server || handle_error "Starting OpenVPN service" "$?"
log_step "OpenVPN service started successfully"

# --- Final Status ---
{
    cat << EOF
======================================
🔒 OpenVPN Server Setup Complete!
======================================

Server Details:
    Public IP: $SERVER_IP
    Port: $OVPN_PORT
    Protocol: $OVPN_PROTOCOL

Client Configuration File:
    Location: $CLIENT_DIR/$CLIENT_NAME.ovpn

Download Client Config:
    Option 1 - From your local machine:
        scp root@$SERVER_IP:$CLIENT_DIR/$CLIENT_NAME.ovpn ./$CLIENT_NAME.ovpn

    Option 2 - If already connected via SSH:
        cat $CLIENT_DIR/$CLIENT_NAME.ovpn
        (Copy the output and save it as $CLIENT_NAME.ovpn on your device)

Basic Usage:
    1. Import the .ovpn file into your OpenVPN client
    2. Connect using the client

Server Management:
    - Start: systemctl start openvpn@server
    - Stop: systemctl stop openvpn@server
    - Status: systemctl status openvpn@server
    - Logs: tail -f /var/log/openvpn/openvpn-status.log
    
Documentation and Help:
    https://upcloud.com/docs/guides/link-to-documentation

Installation Log:
    $LOG_FILE

======================================
EOF
} | tee -a "$LOG_FILE"

exit 0
