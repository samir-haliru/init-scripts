# UpCloud Root Password Reset Script

## Overview

This repository contains a script and instructions for resetting the root password of a Linux server hosted on UpCloud when the password is lost or forgotten. It uses a temporary helper server to securely mount the target server's storage device, reset the password, and handle necessary configurations like SELinux relabeling.

**The process involves:**

1.  Creating a temporary Linux server with the provided initialization script.
2.  Attaching the *storage device* of the server needing the password reset (the "target server") to this temporary server.
3.  Booting the temporary server, which automatically detects the attached disk, resets the root password within it, and then shuts down.
4.  Reattaching the storage disk to the original target server.
5.  Booting the target server and logging in with a known temporary password, immediately changing it.

## :warning: Important warnings :warning:

*   **USE AT YOUR OWN RISK:** This procedure involves modifying the root filesystem of your server. While tested, unforeseen circumstances or deviations from the instructions could lead to data loss or an unbootable server.
*   **BACKUP RECOMMENDED:** Before starting this process, it is **strongly recommended** to create a backup of your target server's storage device via the UpCloud control panel.
*   **FOLLOW INSTRUCTIONS CAREFULLY:** Pay close attention to each step, especially server naming, region selection, and storage operations. Mistakes can lead to failure or data issues.
*   **TEMPORARY PASSWORD:** The script sets a default temporary password (`upc10ud`). This password is **public knowledge** (as it's in the script). You **must** change it immediately upon first login.
*   **TARGET SERVER DOWNTIME:** The target server will need to be stopped during the storage detachment and reattachment phases. Plan for downtime accordingly.

## Prerequisites

*   Access to your UpCloud account and control panel ([https://hub.upcloud.com/](https://hub.upcloud.com/)).
*   The name and region of the UpCloud server whose root password needs resetting (the "target server").
*   Ability to create, stop, and start servers, and manage storage attachments within the UpCloud control panel.


## Step-by-Step Instructions

**Phase 1: Prepare and create temporary server**

1.  **Identify target server:** Note the **name**, and **region** of the server needing the password reset.
2.  **Backup (recommended):** Go to the target server's "Storage" tab in the UpCloud control panel and create a backup of the OS disk.
3.  **Deploy temporary server:**
    *   Click "Deploy server" in the UpCloud control panel.
    *   **Location:** Select the **exact same region** as your target server.
    *   **Plan:** Choose a small, inexpensive plan (e.g., the smallest General Purpose plan).
    *   **Operating System:** Select a recent Linux distribution (e.g., Ubuntu 22.04 LTS). The script is designed for common Linux distributions.
    *   **Storage:** Leave the default storage options.
    *   **Login Method:** You can use any SSH key as it won't actually be used
    *   **Hostname:** Set the hostname **exactly** to `temp-password-reset`. This is critical for the script's safety check.
    *   **Initialization script:** In the "Initialization script" text box, paste the following:
        ```bash
        #!/bin/bash
        curl -s https://raw.githubusercontent.com/samir-haliru/init-scripts/main/root-password-reset.sh | bash
        ```
    *   Click "Deploy".
4.  **Wait for Setup:** Allow the `temp-password-reset` server to deploy and boot up. The initialization script will run. The server should then **shut down automatically** after about a minute (it sets up the service which includes a shutdown command, though the main work happens later). Verify its status changes to "stopped" in the control panel.

**Phase 2: Swap storage and perform reset**

5.  **Stop sarget server:** Ensure your original target server (the one needing the password reset) is **Stopped**.
6.  **Detach target storage device:**
    *   Go to the target server's details page in the UpCloud control panel.
    *   Navigate to the "Storage" tab.
    *   Identify the primary OS disk (usually the first one in the list).
    *   Click the "Detach" button for this disk. Confirm the detachment. Note the disk's name if needed.
7.  **Attach storage device to temporary server:**
    *   Go to the `temp-password-reset` server's details page (it should be stopped).
    *   Navigate to the "Storage" tab.
    *   Click "Attach existing storage".
    *   Select the disk you just detached from your target server.
8.  **Start temporary server (perform reset):**
    *   Go back to the `temp-password-reset` server's "Overview" tab.
    *   Click "Start".
    *   The server will boot up. The `password-reset.service` will run the `password-reset.sh` script, which will mount `/dev/vdb2`, reset the password inside it, and handle SELinux if needed.
    *   Wait for the server to **shut down automatically again**. This typically takes about 1-2 minutes (boot time + script execution). Monitor its status in the control panel until it shows as "stopped".

**Phase 3: Restore storage and finalise**

9.  **Detach storage device from temporary server:**
    *   Ensure the `temp-password-reset` server is stopped.
    *   Go to its "Storage" tab.
    *   Detach the target server's disk (the one attached in step 7).
10. **Reattach storage device to target Server:**
    *   Go back to your original target server (still stopped).
    *   Navigate to its "Storage" tab.
    *   Click "Attach storage device".
    *   Select the original OS disk you detached earlier.
    *   Ensure it is attached as the primary boot device (first in the list).
11. **Start target server:**
    *   Go to the target server's "Overview" tab.
    *   Click "Start".
12. **Login and change password:**
    *   Wait for the server to boot.
    *   Open the "Console" for the target server from the UpCloud control panel.
    *   At the login prompt, enter:
        *   Username: `root`
        *   Password: `upc10ud`
    *   If successful, the system should immediately prompt you to set a new password because the script used `chage -d 0 root`.
    *   Enter a **new, strong, unique password** twice as prompted.
13. **Verify:** Ensure you can log out and log back in with the new password. Check basic system functionality.

**Phase 4: Cleanup**

14. **Delete temporary server:** Once you have successfully reset the password and logged into your target server, you no longer need the temporary server.
    *   Go to the `temp-password-reset` server in the UpCloud control panel.
    *   "Delete server".
    *   Ensure you also select the option to delete its attached storage (the *original* small disk it was created with) to avoid further charges.

