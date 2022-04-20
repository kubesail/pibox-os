#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# Install helm
curl -sLo helm.tar.gz https://get.helm.sh/helm-v3.7.2-linux-arm64.tar.gz
tar zxf helm.tar.gz
mv linux-arm64/helm /usr/local/bin/
chmod +x /usr/local/bin/helm
rm -rf linux-arm64 helm.tar.gz

# Pibox Disk Provisioner - Note, this script will potentially format attached disks. Careful!
mkdir -p /opt/kubesail/
curl -sLo /opt/kubesail/provision-disk.sh https://raw.githubusercontent.com/kubesail/pibox-os/main/provision-disk.sh
chmod +x /opt/kubesail/provision-disk.sh
/opt/kubesail/./provision-disk.sh
# Run disk provisioner before K3s starts
mkdir -p /etc/systemd/system/k3s.service.d
echo -e "[Service]\nExecStartPre=/opt/kubesail/provision-disk.sh" > /etc/systemd/system/k3s.service.d/override.conf
systemctl daemon-reload

# Install KubeSail helper services
curl -s https://raw.githubusercontent.com/kubesail/pibox-os/main/setup.sh | bash
# now you can run `kubesail` to initialize the KubeSail agent at any time

# Refresh SSH certs on first boot
# touch /boot/refresh-ssh-certs

# Reset password back to "raspberrypi"
# passwd pi

# This happens with PiShrink. Only uncomment if using packer
# truncate -s-1 /boot/cmdline.txt
# echo -n " init=/usr/lib/raspi-config/init_resize.sh" >> /boot/cmdline.txt

# Disable SSH
#systemctl stop ssh
#systemctl disable ssh

# Clean bash history
history -c && history -w
exit

# logout of root and do the same for pi user
history -c && history -w
exit
