# KubeSail PiBox Installer

This script installs a service which verifies that the KubeSail agent is installed (for your KubeSail user) after MicroK8s has started.

To use this script, write your KubeSail username to `/boot/kubesail-username.txt` and then run:

```bash
sudo source <(curl -s https://raw.githubusercontent.com/kubesail/agent-installer/main/install.sh)
````
