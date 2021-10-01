# PiBox OS

[Download the latest version](https://github.com/kubesail/pibox-os/releases)

This repository contains scripts and kernel modules used to modify Raspberry Pi OS in order to take full advantage of the PiBox hardware.

## First Boot

This script installs a service which checks if a file exists at `/boot/pibox-first-boot` and refreshes certs. Also optionally installs SSH keys from GitHub public keys if `/boot/github-username.txt` contains a GitHub username.

To use this script, replace `YOUR_GITHUB_USERNAME` and run:

```bash
echo "YOUR_GITHUB_USERNAME" | sudo tee -a /boot/github-ssh-username.txt
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

To make the fan quiet and only spin as fast as necessary, we install a service that sends the correct signal to the fan using the Pi's hardware PWM controller. This code can be found in [our fork]() of `alwynallan`'s original gist on GitHub.

```bash
git clone https://github.com/kubesail/pibox-os.git
cd pibox-os/rpi-pwm-fan
tar zxvf bcm2835-1.68.tar.gz
cd bcm2835-1.68
./configure
make
sudo make install
cd ..
make
sudo make install
```

## LCD display

The python code used to render stats to the LCD display lives in the [lcd-display](lcd-display) directory. More info can be found on the PiBox docs: https://docs.kubesail.com/guides/pibox/os/#enabling-the-13-lcd-display
