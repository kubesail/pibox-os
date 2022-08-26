#!/bin/bash
set -e
set -x

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

hostnamectl set-hostname pibox
sed -i 's/raspberrypi/pibox/' /etc/hosts

# Unlimited bash history https://stackoverflow.com/a/19533853
# sed -i 's/HISTSIZE=1000//' /home/pi/.bashrc
# sed -i 's/HISTFILESIZE=2000//' /home/pi/.bashrc
# cat <<EOF >> /home/pi/.bashrc
# export HISTFILESIZE=
# export HISTSIZE=
# export HISTTIMEFORMAT="[%F %T] "
# export HISTFILE=~/.bash_eternal_history
# PROMPT_COMMAND="history -a; \$PROMPT_COMMAND"
# EOF

cp /home/pi/.bashrc /root/.bashrc

apt-get update -yqq
apt-get full-upgrade -yqq
apt-get autoremove -yqq
apt-get autoclean -yqq
apt-get install -yqq vim lvm2 openssh-server raspberrypi-kernel-headers samba samba-common-bin
apt-get remove -yqq iptables nftables

if [ -f /var/run/reboot-required ]; then
  echo 'PLEASE REBOOT TO ACTIVATE NEW KERNEL'
  exit 0
fi

# Set up samba share
mkdir -p /var/lib/rancher/k3s/storage
echo -e "kubesail\nkubesail" | smbpasswd pi -a -s
cat <<EOF > /etc/samba/smb.conf
[volumes]
force user=root
force group=root
path = /var/lib/rancher/k3s/storage
writeable=Yes
create mask=0777
directory mask=0777
public=no
EOF

mkdir -p /opt/kubesail
curl -sLo /opt/kubesail/update-framebuffer.sh https://raw.githubusercontent.com/kubesail/pibox-os/main/update-framebuffer.sh
chmod +x /opt/kubesail/update-framebuffer.sh
/opt/kubesail/update-framebuffer.sh

# Reduce logging and store in memory to reduce EMMC wear
sed -i 's/.MaxLevelStore.*/MaxLevelStore=info/' /etc/systemd/journald.conf
sed -i 's/.MaxLevelSyslog.*/MaxLevelSyslog=info/' /etc/systemd/journald.conf
sed -i "s/#Storage.*/Storage=volatile/" /etc/systemd/journald.conf
systemctl restart systemd-journald.service

# Add tmpfs at /tmp to reduce EMMC wear
echo "tmpfs /var/tmp tmpfs defaults,noatime,nosuid,nodev,noexec,mode=0755,size=1M 0 0" >> /etc/fstab

# Clone PiBox OS repo for building fan/display drivers
rm -rf pibox-os
git clone https://github.com/kubesail/pibox-os.git
pushd pibox-os
echo "PIBOX_RELEASE=$(git rev-parse --short HEAD)" > /etc/pibox-release
popd

# Enable Fan Support
pushd pibox-os/pwm-fan
tar zxvf bcm2835-1.68.tar.gz
pushd bcm2835-1.68
./configure && make && make install
popd
make && make install
popd

# Enable Display Driver
pushd pibox-os/st7789_module
make
mv /lib/modules/"$(uname -r)"/kernel/drivers/staging/fbtft/fb_st7789v.ko /lib/modules/"$(uname -r)"/kernel/drivers/staging/fbtft/fb_st7789v.BACK
mv fb_st7789v.ko /lib/modules/"$(uname -r)"/kernel/drivers/staging/fbtft/fb_st7789v.ko
popd
dtc --warning no-unit_address_vs_reg -I dts -O dtb -o /boot/overlays/drm-minipitft13.dtbo pibox-os/overlays/minipitft13-overlay.dts
cat <<EOF >> /boot/config.txt
dtoverlay=spi0-1cs
dtoverlay=dwc2,dr_mode=host
hdmi_force_hotplug=1
dtoverlay=drm-minipitft13,rotate=0,fps=60
EOF

# Remove PiBox repo
rm -rf pibox-os

# Kernel settings
grep -qxF 'cgroup_enable=memory cgroup_memory=1' /boot/cmdline.txt || sed -i 's/$/ cgroup_enable=memory cgroup_memory=1/' /boot/cmdline.txt
# Show text output during startup / shutdown (useful if reboot hangs)
sed -i 's/quiet splash plymouth.ignore-serial-consoles//' /boot/cmdline.txt

# Sysctl & limits
echo "vm.swappiness=1" >> /etc/sysctl.conf
echo "fs.file-max=1024000" >> /etc/sysctl.conf
sysctl -p
echo "* soft nofile 8192" >> /etc/security/limits.conf

# Swap
swapoff -a
systemctl mask  "dev-*.swap"
dphys-swapfile swapoff
dphys-swapfile uninstall
update-rc.d dphys-swapfile remove
apt-get -yqq purge dphys-swapfile || true

# Install helm
curl -Lo helm.tar.gz https://get.helm.sh/helm-v3.8.2-linux-arm64.tar.gz
tar zxf helm.tar.gz
mv linux-arm64/helm /usr/local/bin/
chmod +x /usr/local/bin/helm
rm -rf linux-arm64 helm.tar.gz

# Pibox Disk Provisioner - Note, this script will potentially format attached disks. Careful!
mkdir -p /opt/kubesail/
curl -sLo /opt/kubesail/provision-disk.sh https://raw.githubusercontent.com/kubesail/pibox-os/main/provision-disk.sh
chmod +x /opt/kubesail/provision-disk.sh
# /opt/kubesail/provision-disk.sh
# Run disk provisioner before K3s starts
mkdir -p /etc/systemd/system/k3s.service.d
echo -e "[Service]\nExecStartPre=/opt/kubesail/provision-disk.sh" > /etc/systemd/system/k3s.service.d/pre-exec.conf
systemctl daemon-reload

# Install KubeSail helper services
curl -s https://raw.githubusercontent.com/kubesail/pibox-os/main/setup.sh | bash

# This happens with PiShrink. Only uncomment if using packer
# truncate -s-1 /boot/cmdline.txt
# echo -n " init=/usr/lib/raspi-config/init_resize.sh" >> /boot/cmdline.txt

# Disable SSH
#systemctl stop ssh
#systemctl disable ssh

# SSH Config
echo "TCPKeepAlive yes" >> /etc/ssh/sshd_config
touch /boot/ssh
touch /boot/refresh-ssh-certs
rm -vf /home/pi/.ssh/*
sed -i s/PasswordAuthentication\ no/PasswordAuthentication\ yes/ /etc/ssh/sshd_config

# Clean bash history
history -c && history -w
exit
