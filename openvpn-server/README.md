# OpenVPN Server Deployment Guide on UpCloud

This script automates the deployment of an OpenVPN server on an UpCloud Server. It installs all necessary components, configures network settings, including IP forwarding and NAT rules, generates server and client certificates using Easy-RSA, creates ready-to-use client configurations, and sets up the OpenVPN service to start automatically. 

## Initial setup

1. Deploy a new Linux server in the UpCloud control panel using the initialisation script.
   ```
   #!/bin/bash
   curl -s https://raw.githubusercontent.com/samir-haliru/init-scripts/refs/heads/main/openvpn-server/ovpn_auto_install.sh | bash
   ```
2. Once deployment is complete, check the installation logs:
   ```
   cat /root/openvpn-setup.log
   ```
3. You should see output confirming successful installation:
   ```
   ======================================
   🔒 OpenVPN Server Setup Complete!
   ======================================

   Server Details:
       Public IP: <SERVER_IP>
       Port: 1194
       Protocol: udp

   Client Configuration File:
       Location: /etc/openvpn/clients/client1.ovpn

   Download Client Config:
       Option 1 - From your local machine:
           scp root@<SERVER_IP>:/etc/openvpn/clients/client1.ovpn ./client1.ovpn

       Option 2 - If already connected via SSH:
           cat /etc/openvpn/clients/client1.ovpn
           (Copy the output and save it as client1.ovpn on your device)

   Basic Usage:
       1. Import the .ovpn file into your OpenVPN client
       2. Connect using the client

   Server Management:
       - Start: systemctl start openvpn@server
       - Stop: systemctl stop openvpn@server
       - Status: systemctl status openvpn@server
       - Logs: tail -f /var/log/openvpn/openvpn-status.log
   ```

## Accessing client configurations

The installation automatically creates a client configuration file named `client1.ovpn`. You can download this file using one of the following methods:

### Method 1: Download via SCP
From your local computer (not the server), run:
```
scp root@<SERVER_IP>:/etc/openvpn/clients/client1.ovpn ./client1.ovpn
```
Replace `<SERVER_IP>` with your server's IP address.

The full prepopulated command can also be found in the installation logs

### Method 2: Copy via SSH
If you're already connected to the server via SSH:
1. Display the content of the configuration file:
   ```
   cat /etc/openvpn/clients/client1.ovpn
   ```
2. Copy the entire output (including the certificate and key information).
3. Save it as `client1.ovpn` on your local device.

## Connecting to your VPN

1. Install an OpenVPN client on your device:
   - **Windows**: [OpenVPN Community Client](https://openvpn.net/community-downloads/)
   - **macOS**: [Tunnelblick](https://tunnelblick.net/) or [OpenVPN Connect](https://openvpn.net/client-connect-vpn-for-mac-os/)
   - **Linux**: Install via package manager (`sudo apt install openvpn` for Ubuntu/Debian)
   - **iOS**: [OpenVPN Connect](https://apps.apple.com/gb/app/openvpn-connect/id590379981) from App Store
   - **Android**: [OpenVPN Connect](https://play.google.com/store/apps/details?id=net.openvpn.openvpn) from Play Store

2. Import the `.ovpn` file into your chosen OpenVPN client.
3. Connect using the client application.


## Server management

### Service control
- **Start the OpenVPN server**: `systemctl start openvpn@server`
- **Stop the OpenVPN server**: `systemctl stop openvpn@server`
- **Restart the OpenVPN server**: `systemctl restart openvpn@server`
- **Check service status**: `systemctl status openvpn@server`

### Logs and monitoring
- **View service logs**: `journalctl -u openvpn@server`
- **View OpenVPN status log**: `cat /var/log/openvpn/openvpn-status.log`
- **Follow OpenVPN status log in real-time**: `tail -f /var/log/openvpn/openvpn-status.log`

### Server configuration
The main server configuration file is located at `/etc/openvpn/server.conf`. After making any changes to this file, restart the service for them to take effect:
```
systemctl restart openvpn@server
```
