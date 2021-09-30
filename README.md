# KubeSail PiBox Installer

This script installs a service which verifies that the KubeSail agent is installed (for your KubeSail user) after MicroK8s has started.

To use this script, replace `YOUR_KUBESAIL_USERNAME` below and run the following snippet:

```bash
echo "YOUR_KUBESAIL_USERNAME" | sudo tee -a /boot/kubesail-username.txt
curl -s https://raw.githubusercontent.com/kubesail/agent-installer/main/install.sh | sudo bash
````
