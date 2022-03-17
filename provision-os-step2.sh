#!/bin/bash

# Install K3s
if [[ ! -d /var/lib/rancher/k3s/data ]]; then
  curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_START=true INSTALL_K3S_CHANNEL=stable sh
fi

# Install helm
curl -sLo helm.tar.gz https://get.helm.sh/helm-v3.7.2-linux-arm64.tar.gz
tar zxf helm.tar.gz
mv linux-arm64/helm /usr/local/bin/
chmod +x /usr/local/bin/helm
rm -rf linux-arm64 helm.tar.gz

APISERVER_TIMEOUT=60 # Wait n seconds for k3s apiserver to start
for i in $(seq 1 $APISERVER_TIMEOUT); do 
    APISERVER_STATUS="$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 -k https://localhost:6443)"
    echo $APISERVER_STATUS
    if [ $APISERVER_STATUS == "401" ]; then
        break
    fi
    sleep 1
done
if [ $APISERVER_STATUS != "401" ]; then
    echo "!!! Timeout waiting for k3s apiserver to start !!!"
    echo "!!! PROVISION DID NOT COMPLETE !!!"
    exit 1
fi

# Stop K3s, remove certs to get regenerated on next boot
k3s kubectl --insecure-skip-tls-verify -n kube-system delete secret k3s-serving
service k3s stop
rm -vrf /var/lib/rancher/k3s/agent/*.key \
    /var/lib/rancher/k3s/agent/*.crt \
    /etc/rancher/k3s/k3s.yaml \
    /var/lib/rancher/k3s/server/token \
    /var/lib/rancher/k3s/server/tls

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
touch /boot/refresh-ssh-certs

# Reset password back to "raspberrypi"
# passwd pi

# This happens with PiShrink. Only uncomment if using packer
# truncate -s-1 /boot/cmdline.txt
# echo -n " init=/usr/lib/raspi-config/init_resize.sh" >> /boot/cmdline.txt

# Clean bash history
history -c && history -w
exit

# logout of root and do the same for pi user
history -c && history -w
exit
