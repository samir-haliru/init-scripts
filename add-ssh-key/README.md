### **UpCloud SSH Key Injection Script**

#### **Overview**

This procedure uses a temporary helper server to securely mount a target server's storage device and inject a new SSH public key into the `root` user's `authorized_keys` file. This is useful for regaining access to a server if you have lost your original SSH key.

#### **⚠️ Important Warnings ⚠️**

*   **USE AT YOUR OWN RISK:** This procedure involves modifying the root filesystem of your server. While tested, unforeseen circumstances could lead to data loss or an unbootable server.
*   **BACKUP RECOMMENDED:** Before starting, it is **strongly recommended** to create a backup of your target server's storage device.
*   **FOLLOW INSTRUCTIONS CAREFULLY:** Pay close attention to each step, especially the server hostname (`temp-ssh-key-add`). Mistakes can lead to failure.
*   **PUBLIC KEY:** You must replace the placeholder public key in the script with your own. Ensure you have the corresponding **private key** to log in afterward.
*   **TARGET SERVER DOWNTIME:** The target server will be stopped during this process. Plan for downtime accordingly.

#### **Prerequisites**

*   Access to your UpCloud account and control panel.
*   The name and region of the target server needing the SSH key.
*   Your **SSH public key** (e.g., the contents of `~/.ssh/id_rsa.pub`).
*   Access to the corresponding **SSH private key** on your local machine.

---

### **Step-by-Step Instructions**

**Phase 1: Prepare and Create Temporary Server**

1.  **Identify Target Server:** Note the **name** and **region** of the server you need to add the key to.
2.  **Backup (Recommended):** Go to the target server's "Storage" tab in the UpCloud control panel and create a backup of its OS disk.
3.  **Prepare the Script:**
    *   Copy the entire script you provided into a text editor.
    *   Find the line: `SSH_PUBLIC_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEArV1..."`
    *   **Replace the placeholder key** with your actual, full public key. The key must be on a single line and enclosed in double quotes.
4.  **Deploy Temporary Server:**
    *   Click "Deploy server" in the UpCloud control panel.
    *   **Location:** Select the **exact same region** as your target server.
    *   **Plan:** Choose a small, inexpensive plan.
    *   **Operating System:** Select a recent Linux distribution (e.g., Ubuntu 22.04 LTS).
    *   **Hostname:** Set the hostname **exactly** to `temp-ssh-key-add`. This is critical for the script's safety check.
    *   **Initialization script:** In the "Initialization script" text box, paste your **modified** script (with your public key in it).
    *   Click "Deploy".
5.  **Wait for Setup:** Allow the `temp-ssh-key-add` server to deploy. The initialization script will run, create the service, and then the server should **shut down automatically** after about a minute. Verify its status changes to "stopped" in the control panel.

**Phase 2: Swap Storage and Inject Key**

6.  **Stop Target Server:** Ensure your original target server is **Stopped**.
7.  **Detach Target Storage Device:** In the target server's "Storage" tab, find the primary OS disk and click "Detach".
8.  **Attach Storage to Temporary Server:** Go to the `temp-ssh-key-add` server's "Storage" tab and "Attach existing storage", selecting the disk you just detached.
9.  **Start Temporary Server (Perform Injection):**
    *   Start the `temp-ssh-key-add` server.
    *   Upon booting, the `ssh-key-add.service` will automatically run, mount `/dev/vdb2`, and inject your SSH key into the `authorized_keys` file.
    *   Wait for the server to **shut down automatically again**. This typically takes 1-2 minutes. Monitor its status until it shows as "stopped".

**Phase 3: Restore Storage and Finalise**

10. **Detach Storage from Temporary Server:** Once stopped, go to its "Storage" tab and detach the target server's disk.
11. **Reattach Storage to Target Server:** Go back to your original target server, navigate to its "Storage" tab, and reattach its original OS disk. Ensure it is the primary boot device.
12. **Start Target Server:** Start your original server.
13. **Connect via SSH:**
    *   Wait for the server to boot fully.
    *   Open a terminal on your local machine.
    *   You should now be able to log in as the `root` user using the SSH key you injected:
        ```bash
        ssh root@<your_server_ip_address>
        ```
    *   If successful, you will be logged in without needing a password.

**Phase 4: Cleanup**

14. **Delete Temporary Server:** Once you have confirmed you can access your target server, delete the `temp-ssh-key-add` server and its local storage disk to avoid further charges.
