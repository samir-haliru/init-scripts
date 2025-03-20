# Beszel Hub deployment guide on UpCloud
This init script automates the deployment of a [Beszel](https://beszel.dev/) Hub on a new UpCloud Server. It installs all necessary components, configures the initial HTTP access, and prepares the server for optional HTTPS configuration with a custom domain. 

## Initial setup

1. Deploy a new Cloud Server in the UpCloud control panel using the initialisation script.
   ```
   #!/bin/bash
   curl -s https://raw.githubusercontent.com/samir-haliru/init-scripts/main/beszel/beszel_auto_install.sh | bash
   ```
2. Once deployment is complete, log into the server via SSH.
3. Run this command to check the installation logs:
   ```
   cat /var/log/beszel-install.log
   ```
4. You should see output confirming successful installation:
   ```
   [root@beszel-centos ~]# tail -f /var/log/beszel-install.log
   Created symlink /etc/systemd/system/multi-user.target.wants/beszel.service → /etc/systemd/system/beszel.service.
   [2025-03-19 08:06:34] [INFO] Docker service configured and started
   [2025-03-19 08:06:34] [INFO] Creating domain setup script...
   [2025-03-19 08:06:34] [INFO] Domain setup script created at /opt/beszel/setup-domain.sh
   [2025-03-19 08:06:35] [SUCCESS] Installation complete!
   [2025-03-19 08:06:35] [INFO] Beszel Hub is running on port 8090
   [2025-03-19 08:06:35] [INFO] Firewall configured to allow connections to port 8090
   [2025-03-19 08:06:35] [INFO] Beszel Hub is available at: http://12.34.56.78:8090
   [2025-03-19 08:06:35] [INFO] To configure HTTPS: /opt/beszel/setup-domain.sh yourdomain.com (will configure ports 80/443)
   [2025-03-19 08:06:35] [INFO] To update Beszel: docker pull henrygd/beszel:latest && systemctl restart beszel
   ```

## Accessing Beszel Hub
You can immediately access the Beszel Hub dashboard by visiting:
```
http://<YOUR-SERVER-IP>:8090
```

## Updating Beszel Hub
To update Beszel Hub to the latest version, run the following command:
```
docker pull henrygd/beszel:latest && systemctl restart beszel
```
This command pulls the latest Docker image and then restarts the Beszel service to apply the update.


## Adding a new server to monitor
![image](https://github.com/user-attachments/assets/8ae7395c-d7ec-4731-8b06-e1aa502ded54)
1. Log in to the Beszel Hub dashboard.
2. Click "Add System" in the top right corner.
3. Switch to the 'Binary' tab.
4. Replace `<SERVER NAME>` with a descriptive name for your server.
5. Replace `<IP-ADDRESS>` with the IPv4 address of the server you want to monitor.
   - For enhanced security, consider using the server's private IPv4 utility address or SDN network address.
6. Copy the generated Linux command to your clipboard and click "Add system".
7. Log into the server you want to monitor.
8. Paste the copied command and press Enter.
9. Type `y` when prompted to enable automatic daily updates for the beszel-agent.
10. Return to your Beszel Hub dashboard—the newly added server should now appear as "up" with updated statistics.

![image](https://github.com/user-attachments/assets/f1c36a8b-dfe2-4c92-8e0f-56a25f586e86)

## Setting up HTTPS with a custom domain

1. Create DNS records for your domain pointing to your server's IP address:
   - Add an A record: `yourdomain.com` → `<YOUR-SERVER-IP>`
2. Wait for DNS changes to propagate (typically takes between a few minutes to 48 hours).
3. Run the domain setup script:
   ```
   /opt/beszel/setup-domain.sh yourdomain.com
   ```
4. After successful completion, Beszel Hub will be accessible via HTTPS:
   ```
   https://yourdomain.com
   ```
5. To view domain setup logs, run:
   ```
   cat /var/log/beszel-domain-setup.log
   ```

You can change the domain for your Beszel Hub installation at any time by running:
```
/opt/beszel/setup-domain.sh yournewdomain.com
```



