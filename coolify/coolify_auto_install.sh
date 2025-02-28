#!/bin/bash

# === Coolify Auto-Installation Init Script ===
# This script automatically installs Coolify during server initialization

# Enable logging
LOG_FILE="/var/log/coolify-install.log"
DETAILED_LOG="/var/log/coolify-install-detailed.log"

# Start logging
{
    echo "===== Coolify Installation Started ====="
    echo "Date: $(date)"
    echo "Hostname: $(hostname)"
    echo ""
} | tee -a $LOG_FILE $DETAILED_LOG

# Create a function to handle errors
handle_error() {
    {
        echo "[ERROR] An error occurred during installation at step: $1"
        echo "Please check $DETAILED_LOG for more details"
        echo ""
    } | tee -a $LOG_FILE $DETAILED_LOG
    
    # Create a failure notice in MOTD
    cat > /etc/update-motd.d/99-coolify-install-failed << 'EOF'
#!/bin/bash
echo "----------------------------------------"
echo -e "\033[0;31mCoolify installation failed\033[0m"
echo "Please check the installation logs for details:"
echo "- /var/log/coolify-install.log (summary)"
echo "- /var/log/coolify-install-detailed.log (detailed)"
echo "----------------------------------------"
EOF
    chmod +x /etc/update-motd.d/99-coolify-install-failed
    
    exit 1
}

# Function to get the server's IP addresses
get_server_ip() {
    # Try to get the public IP first
    PUBLIC_IP=$(curl -s -4 https://ifconfig.io || curl -s -4 https://api.ipify.org || curl -s -4 https://icanhazip.com)
    
    # Get the private IP as backup
    PRIVATE_IP=$(hostname -I | awk '{print $1}')
    
    # If public IP is available, use it; otherwise use private IP
    if [[ -n "$PUBLIC_IP" && "$PUBLIC_IP" != "127.0.0.1" ]]; then
        echo "$PUBLIC_IP"
    else
        echo "$PRIVATE_IP"
    fi
}

# Step 1: Install Coolify
{
    echo "[STEP 1] Installing Coolify using the official installer script..."
    echo "This may take several minutes. Please be patient."
    echo ""
} | tee -a $LOG_FILE $DETAILED_LOG

# Run the Coolify installer and redirect output to logs
if ! curl -fsSL https://cdn.coollabs.io/coolify/install.sh | sudo bash >> $DETAILED_LOG 2>&1; then
    handle_error "Coolify installation script"
fi

{
    echo "[STEP 1] Coolify installation completed successfully."
    echo ""
} | tee -a $LOG_FILE $DETAILED_LOG

# Step 2: Check if Coolify is running
{
    echo "[STEP 2] Verifying Coolify is running..."
} | tee -a $LOG_FILE $DETAILED_LOG

# Wait for services to fully start
sleep 20

# Check if Coolify containers are running
RUNNING_CONTAINERS=$(docker ps --filter "name=coolify" --format "{{.Names}}" | wc -l)

if [ "$RUNNING_CONTAINERS" -gt 0 ]; then
    {
        echo "[STEP 2] Verified $RUNNING_CONTAINERS Coolify containers are running."
        echo ""
    } | tee -a $LOG_FILE $DETAILED_LOG
else
    {
        echo "[WARNING] No Coolify containers found running after installation."
        echo "This might indicate an issue with the installation process."
        echo ""
    } | tee -a $LOG_FILE $DETAILED_LOG
    handle_error "Coolify service verification"
fi

# Step 3: Create a simplified MOTD
{
    echo "[STEP 3] Creating Message of the Day for Coolify..."
} | tee -a $LOG_FILE $DETAILED_LOG

SERVER_IP=$(get_server_ip)

# Create the MOTD file
cat > /etc/update-motd.d/99-coolify-installed << EOF
#!/bin/bash
echo "----------------------------------------"
echo -e "\033[0;32mCoolify is installed and running!\033[0m"
echo "Access your Coolify instance at: http://$SERVER_IP:8000"
echo ""
echo "Installation logs:"
echo "- /var/log/coolify-install.log (summary)"
echo "- /var/log/coolify-install-detailed.log (detailed)"
echo "----------------------------------------"
EOF

chmod +x /etc/update-motd.d/99-coolify-installed

# Ensure the MOTD is displayed by updating motd if needed
if [ -f /etc/default/motd-news ]; then
    sed -i 's/ENABLED=0/ENABLED=1/g' /etc/default/motd-news
fi

# Make sure update-motd is being used
if [ -d /etc/update-motd.d ]; then
    # For some systems, we may need to enable it
    if [ -f /etc/pam.d/sshd ]; then
        if ! grep -q "motd" /etc/pam.d/sshd; then
            echo "session optional pam_motd.so motd=/run/motd.dynamic" >> /etc/pam.d/sshd
        fi
    fi
fi

# Summary
{
    echo "==============================="
    echo "Coolify Installation Complete!"
    echo ""
    echo "Coolify is now accessible at:"
    echo "    http://$SERVER_IP:8000"
    echo "==============================="
} | tee -a $LOG_FILE $DETAILED_LOG

echo "Coolify installation completed. See $LOG_FILE for details."
