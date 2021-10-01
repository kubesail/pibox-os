# PiBox OS

[Download the latest version](https://github.com/kubesail/pibox-os/releases)

This repository contains scripts and kernel modules used to modify Raspberry Pi OS in order to take full advantage of the PiBox hardware.

## First Boot

This script installs a service which can:

- Install SSH keys from GitHub public keys if `/boot/github-username.txt` contains a GitHub username
- Refresh SSH host certs
- Refresh MicroK8s certs

To use this script: replace `YOUR_GITHUB_USERNAME` and run:

```bash
echo "YOUR_GITHUB_USERNAME" | sudo tee -a /boot/github-ssh-username.txt
sudo touch /boot/refresh-ssh-certs
sudo touch /boot/refresh-microk8s-certs
```

then run:

```bash
curl -s https://raw.githubusercontent.com/kubesail/pibox-os/main/first-boot-installer.sh | sudo bash
```

## KubeSail Agent Installer

This script installs a service which verifies that the KubeSail agent is installed (for your KubeSail user) after MicroK8s has started.

To use this script, replace `YOUR_KUBESAIL_USERNAME` and run:

```bash
echo "YOUR_KUBESAIL_USERNAME" | sudo tee -a /boot/kubesail-username.txt
```

then run:

```bash
curl -s https://raw.githubusercontent.com/kubesail/pibox-os/main/agent-installer.sh | sudo bash
```

## PWM Fan Support

To make the fan quiet and only spin as fast as necessary, we install a service that sends the correct signal to the fan using the Pi's hardware PWM controller. See the [pwm-fan]() directory for details.

## LCD display

The python code used to render stats to the LCD display lives in the [lcd-display](lcd-display) directory. More info can be found on the PiBox docs: https://docs.kubesail.com/guides/pibox/os/#enabling-the-13-lcd-display
