# PiBox OS

[Download the latest version](https://github.com/kubesail/pibox-os/releases)

This repository contains scripts and kernel modules used to modify Raspberry Pi OS in order to take full advantage of the PiBox hardware.

## First Boot

This script installs a service which checks if a file exists at `/boot/pibox-first-boot` and refreshes certs. Also optionally installs SSH keys from GitHub public keys if `/boot/github-username.txt` contains a GitHub username.

To use this script, replace `YOUR_GITHUB_USERNAME` and run:

```bash
sudo touch /boot/pibox-first-boot
echo "YOUR_GITHUB_USERNAME" | sudo tee -a /boot/github-username.txt
```

then run:

```bash
curl -s https://raw.githubusercontent.com/kubesail/pibox-os/main/first-boot-installer.sh | sudo bash
````

## KubeSail Agent Installer

This script installs a service which verifies that the KubeSail agent is installed (for your KubeSail user) after MicroK8s has started.

To use this script, replace `YOUR_KUBESAIL_USERNAME` and run:

```bash
echo "YOUR_KUBESAIL_USERNAME" | sudo tee -a /boot/kubesail-username.txt
```

then run:

```bash
curl -s https://raw.githubusercontent.com/kubesail/pibox-os/main/agent-installer.sh | sudo bash
````
