#!/bin/bash
set -x

# New password: Set a one time password here. You will be forced to change it on the first login
NEW_PASSWORD="upc10ud"

# Check hostname before proceeding.
if [ "$(hostname)" != "temp-password-reset" ]; then
    echo "Not a temporary password reset server. Exiting."
    exit 0
fi

# First, create and enable the service on the temporary server
# Create systemd service with 15 second delay
cat << 'EOF' > /etc/systemd/system/password-reset.service
[Unit]
Description=Password Reset Service
After=network.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/password-reset.sh
ExecStart=/bin/sleep 15
ExecStart=/sbin/shutdown -h now
RemainAfterExit=no
[Install]
WantedBy=multi-user.target
EOF

# Enable the service
systemctl enable password-reset.service

# Now create the password reset script
cat << EOF > /usr/local/bin/password-reset.sh
#!/bin/bash
# Ensure logging directory exists
mkdir -p /var/log/upcloud

# Create comprehensive logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] \$*" | tee -a /var/log/upcloud/password-reset-startup.log
}

log "Password Reset Script Started"

# Function to detect OS and reset the password accordingly
reset_password() {
    local target_dir=\$1
    
    # Try to detect OS
    if [ -f "\${target_dir}/etc/redhat-release" ]; then
        log "CentOS/RHEL system detected"
        
        # Set new root password using chpasswd
        log "Setting new root password using chpasswd"
        echo "root:${NEW_PASSWORD}" | chroot \${target_dir} /bin/bash -c "chpasswd"
        
        # Force password expiration on first login
        log "Forcing password expiration on first login"
        chroot \${target_dir} /bin/bash -c "chage -d 0 root"
        
        # Verify root account is unlocked and password is set
        if chroot \${target_dir} /bin/bash -c "grep '^root:[!*]' /etc/shadow"; then
            log "ERROR: Root account still appears to be locked"
            return 1
        else
            log "Root account successfully unlocked and password set"
        fi
        
        # Handle SELinux
        if [ -f "\${target_dir}/etc/selinux/config" ]; then
            log "SELinux detected, ensuring autorelabel on next boot"
            touch "\${target_dir}/.autorelabel"
        fi
    else
        log "Debian/Ubuntu system detected (or other)"
        echo "root:${NEW_PASSWORD}" | chroot \${target_dir} /bin/bash -c "chpasswd"
        
        # Force password expiration on first login
        log "Forcing password expiration on first login"
        chroot \${target_dir} /bin/bash -c "chage -d 0 root"
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
                
                # Reset root password
                log "Attempting root password reset"
                if reset_password "/mnt/target"; then
                    log "Password reset successful"
                else
                    log "ERROR: Password reset failed"
                fi
                
                # Mark successful reset
                touch /var/log/upcloud/password-reset-complete
                
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

log "Password reset process completed. System will shutdown in 15 seconds."
EOF

# Make the password reset script executable
chmod +x /usr/local/bin/password-reset.sh

# Start the service
systemctl start password-reset.service
