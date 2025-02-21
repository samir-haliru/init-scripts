#!/bin/bash
set -x

# Specify the SSH public key here (replace with your actual public key)
SSH_PUBLIC_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEArV1..."

# Check hostname before proceeding.
if [ "$(hostname)" != "temp-ssh-key-add" ]; then
    echo "Not a temporary SSH key add server. Exiting."
    exit 0
fi

# First, create and enable the service on the temporary server
# Create systemd service with 15 second delay
cat << 'EOF' > /etc/systemd/system/ssh-key-add.service
[Unit]
Description=SSH Key Add Service
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ssh-key-add.sh
ExecStart=/bin/sleep 15
ExecStart=/sbin/shutdown -h now
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
systemctl enable ssh-key-add.service

# Now create the SSH key add script
cat << EOF > /usr/local/bin/ssh-key-add.sh
#!/bin/bash

# Ensure logging directory exists
mkdir -p /var/log/upcloud

# Create comprehensive logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] \$*" | tee -a /var/log/upcloud/ssh-key-add-startup.log
}

log "SSH Key Add Script Started"

# Function to detect OS and add the SSH key accordingly
add_ssh_key() {
    local target_dir=\$1
    local ssh_key="$SSH_PUBLIC_KEY"
    
    # Try to detect OS
    if [ -f "\${target_dir}/etc/redhat-release" ]; then
        log "CentOS/RHEL system detected"
        
        # Add SSH key to root's authorized_keys
        mkdir -p "\${target_dir}/root/.ssh"
        echo "\$ssh_key" >> "\${target_dir}/root/.ssh/authorized_keys"
        chmod 700 "\${target_dir}/root/.ssh"
        chmod 600 "\${target_dir}/root/.ssh/authorized_keys"
        chown -R 0:0 "\${target_dir}/root/.ssh"
        
        log "SSH key added to root's authorized_keys on CentOS/RHEL system"
        
    else
        log "Debian/Ubuntu system detected (or other)"
        
        # Add SSH key to root's authorized_keys
        mkdir -p "\${target_dir}/root/.ssh"
        echo "\$ssh_key" >> "\${target_dir}/root/.ssh/authorized_keys"
        chmod 700 "\${target_dir}/root/.ssh"
        chmod 600 "\${target_dir}/root/.ssh/authorized_keys"
        chown -R 0:0 "\${target_dir}/root/.ssh"
        
        log "SSH key added to root's authorized_keys on Debian/Ubuntu system"
    fi
    
    return \$?
}

# Debug: List block devices
log "Block Devices:"
lsblk

# Check for secondary disk
if [ -b /dev/vdb ]; then
    log "Secondary disk detected: /dev/vdb"
    
    # Check for root partition (vdb2)
    if [ -b /dev/vdb2 ]; then
        log "Root partition detected: /dev/vdb2"
        
        # Mount and check filesystem
        mkdir -p /mnt/target
        if mount /dev/vdb2 /mnt/target; then
            log "Successfully mounted /dev/vdb2"
        
            # Verify root filesystem
            if [ -d "/mnt/target/etc" ]; then
                log "Valid root filesystem detected"
                
                # Bind mount system directories
                mount --bind /dev /mnt/target/dev
                mount --bind /proc /mnt/target/proc
                mount --bind /sys /mnt/target/sys
                
                # Add SSH key
                log "Attempting to add SSH key"
                if add_ssh_key "/mnt/target"; then
                    log "SSH key addition successful"
                else
                    log "ERROR: SSH key addition failed"
                fi
                
                # Mark successful addition
                touch /var/log/upcloud/ssh-key-add-complete
                
                # Cleanup mounts
                umount /mnt/target/sys
                umount /mnt/target/proc
                umount /mnt/target/dev
                umount /mnt/target
            else
                log "ERROR: Not a valid root filesystem"
                umount /mnt/target  # Cleanup if filesystem check fails
            fi
        else
            log "ERROR: Could not mount /dev/vdb2"
        fi
    else
        log "ERROR: Root partition (vdb2) not found"
    fi
else
    log "ERROR: No secondary disk found"
fi

log "SSH key addition process completed. System will shutdown in 15 seconds."
EOF

# Make the SSH key add script executable
chmod +x /usr/local/bin/ssh-key-add.sh

# Start the service
systemctl start ssh-key-add.service
