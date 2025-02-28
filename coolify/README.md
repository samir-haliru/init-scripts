# Coolify deployment guide on UpCloud
This script automates the deployment of [Coolify](https://coolify.io/) on a new UpCloud Server. It installs all necessary components and configures the system to run Coolify automatically, providing you with a self-hosted PaaS (Platform as a Service) solution.

## Initial setup

1. Deploy a new Cloud Server in the UpCloud control panel using the initialisation script:
   ```
   #!/bin/bash
   curl -s https://raw.githubusercontent.com/samir-haliru/init-scripts/refs/heads/main/coolify/coolify_auto_install.sh | bash
   ```

2. Once deployment is complete, log into the server via SSH.

3. You should see a welcome message indicating that Coolify is installed and accessible:
   ```
   ----------------------------------------
   Coolify is installed and running!
   Access your Coolify instance at: http://<YOUR-SERVER-IP>:8000
   
   Installation logs:
   - /var/log/coolify-install.log (summary)
   - /var/log/coolify-install-detailed.log (detailed)
   ----------------------------------------
   ```

4. You can also check the installation logs for more details:
   ```
   cat /var/log/coolify-install.log
   ```

## Accessing Coolify

You can immediately access the Coolify dashboard by visiting:
```
http://<YOUR-SERVER-IP>:8000
```

Upon your first visit, you'll need to create an admin account to get started.

## Key features of Coolify

- **Application Deployment**: Deploy applications from Git repositories with automatic builds and deployments
- **Database Management**: Create and manage databases for your applications
- **SSL/TLS Support**: Automatic HTTPS with Let's Encrypt
- **Service Integration**: Easy setup for Redis, MongoDB, MySQL, PostgreSQL, and more
- **Docker Management**: Built on Docker for containerized deployments

## Setting up a custom domain with SSL

Setting up a custom domain with SSL in Coolify v4.0.0-beta is straightforward:

### 1. Configure DNS records

First, set up the necessary DNS records for your domain:

1. Add an A record pointing your domain to your server's IP address:
   - Type: A
   - Name: @ (or leave blank for root domain)
   - Value: `<YOUR-SERVER-IP>`
   - TTL: 3600 (or as recommended by your DNS provider)

2. If you want to use a subdomain (e.g., coolify.yourdomain.com), create an A record for that instead:
   - Type: A
   - Name: coolify
   - Value: `<YOUR-SERVER-IP>`
   - TTL: 3600

3. Wait for DNS changes to propagate (typically takes between a few minutes to 48 hours).

### 2. Configure Instance Domain

1. Log into your Coolify dashboard (http://`<YOUR-SERVER-IP>`:8000)
2. Click on "Settings" in the left menu
3. Go to the "Configuration" tab
4. Under "Instance Settings", set your "Instance's Domain" to your domain (e.g., `https://coolify.yourdomain.com`)
5. Click "Save"

### 3. Wait for SSL configuration

After setting the domain:

1. **Be patient** - Coolify will automatically detect the domain change and begin provisioning an SSL certificate
2. This process typically takes 5-10 minutes but can sometimes take longer
3. Coolify manages all the proxy configuration and certificate generation in the background
4. No further manual steps are required

### 4. Verify SSL configuration

After waiting:

1. Visit your domain with https:// to verify the SSL certificate is working
2. If successful, you'll see a secure connection without warnings
3. If you still see SSL warnings after 15-20 minutes, refer to the troubleshooting section below

## Backup and data management

Important data is stored in the following locations:

- `/data/coolify/` - Contains all Coolify data and configurations
- `/data/coolify/source/.env` - Environment configuration file

It's recommended to back up these locations regularly, especially before updates.

## Troubleshooting

If you encounter issues with your Coolify installation:

1. Check the installation logs:
   ```
   cat /var/log/coolify-install.log
   cat /var/log/coolify-install-detailed.log
   ```

2. View Docker container status:
   ```
   docker ps -a | grep coolify
   ```

3. Check Docker container logs:
   ```
   docker logs coolify
   ```

4. Visit the Coolify documentation for additional help:
   [https://coolify.io/docs/](https://coolify.io/docs/)

## Updating Coolify

Coolify will automatically check for updates. When an update is available, you'll be notified in the dashboard and can apply the update with a single click.

To manually update Coolify:

```
bash /data/coolify/source/upgrade.sh
```

## Getting support

For additional support, visit:
- [Coolify Documentation](https://coolify.io/docs/)
- [Coolify GitHub Repository](https://github.com/coollabsio/coolify)
- [Coolify Discord Community](https://coolify.io/discord)
