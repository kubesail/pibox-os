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
sed -i 's/HISTSIZE=1000//' /home/pi/.bashrc
sed -i 's/HISTFILESIZE=2000//' /home/pi/.bashrc
cat <<EOF >> /home/pi/.bashrc
export HISTFILESIZE=
export HISTSIZE=
export HISTTIMEFORMAT="[%F %T] "
export HISTFILE=~/.bash_eternal_history
PROMPT_COMMAND="history -a; \$PROMPT_COMMAND"
EOF

cp /home/pi/.bashrc /root/.bashrc

apt-get update -yqq
apt-get full-upgrade -yqq
apt-get autoremove -yqq
apt-get autoclean -yqq
apt-get install -yqq vim lvm2 openssh-server raspberrypi-kernel-headers samba samba-common-bin tmate sysstat smartmontools whois git
apt-get remove -yqq iptables nftables

# Kernel settings
grep -qxF 'cgroup_enable=memory cgroup_memory=1' /boot/cmdline.txt || sed -i 's/$/ cgroup_enable=memory cgroup_memory=1/' /boot/cmdline.txt
# Show text output during startup / shutdown (useful if reboot hangs)
sed -i 's/quiet splash plymouth.ignore-serial-consoles//' /boot/cmdline.txt

if [ -f /var/run/reboot-required ]; then
  echo 'PLEASE REBOOT TO ACTIVATE NEW KERNEL'
  exit 0
fi

# Set up samba share
mkdir -p /var/log/samba/
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
sed -i "s/#SystemMaxUse.*/SystemMaxUse=10M/" /etc/systemd/journald.conf
sed -i "s/#SystemMaxFileSize.*/SystemMaxFileSize=10M/" /etc/systemd/journald.conf
systemctl restart systemd-journald.service

# Add tmpfs at /tmp to reduce EMMC wear
echo "tmpfs /var/tmp tmpfs defaults,noatime,nosuid,nodev,noexec,mode=0755,size=64M 0 0" >> /etc/fstab

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
make install
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

# Install pibox-help script
cat <<EOF > /usr/local/bin/pibox-help
#!/bin/bash
curl -sL https://raw.githubusercontent.com/kubesail/pibox-os/main/kubesail-support.sh | sudo bash
EOF
chmod +x /usr/local/bin/pibox-help

# This happens with PiShrink. Only uncomment if using packer
# truncate -s-1 /boot/cmdline.txt
# echo -n " init=/usr/lib/raspi-config/init_resize.sh" >> /boot/cmdline.txt

# Disable SSH
#systemctl stop ssh
#systemctl disable ssh

# Install Fix "Unknown" pods service
cat <<EOF > /opt/kubesail/fix-unknown-pods.sh
#!/bin/bash

# Redirect standard out and standard error to a file.
exec &> /var/log/fix-unknown-pods.log
echo \$(date +"%D %T")" Fixing any pods in Unknown state. Waiting 90s after boot..."

(
    sleep 90
    UNKNOWN_PODS=\$(sudo kubectl get pods -A | grep Unknown)
    if [ -z "\${UNKNOWN_PODS}" ]; then
      echo \$(date +"%D %T")" No Unknown pods found."
    else  
      echo \$(date +"%D %T")" 90s elapsed, finding and fixing all Unknown pods."
      for i in \$(sudo k3s ctr c ls | awk '{print  \$1}'); do sudo k3s ctr c rm \$i; done
      sudo service k3s restart
      echo "All done - things should be back up and running in just a moment"
    fi
) &

exit 0
EOF
chmod +x /opt/kubesail/fix-unknown-pods.sh
cat <<EOF > /etc/systemd/system/fix-unknown-pods.service
[Unit]
Description=Fix Unknown pods
Requires=k3s.service

[Service]
Type=forking
GuessMainPID=no
StandardInput=null
ExecStart=/opt/kubesail/fix-unknown-pods.sh

[Install]
WantedBy=default.target
EOF
systemctl daemon-reload
sudo systemctl enable fix-unknown-pods.service

cat <<EOF > /usr/local/bin/rgb
#!/bin/bash
# RED
echo "17" > /sys/class/gpio/export
echo "out" > /sys/class/gpio/gpio17/direction
# GREEN
echo "27" > /sys/class/gpio/export
echo "out" > /sys/class/gpio/gpio27/direction
# BLUE
echo "23" > /sys/class/gpio/export
echo "out" > /sys/class/gpio/gpio23/direction

while :
do
    echo "1" > /sys/class/gpio/gpio17/value
    sleep 0.2
    echo "0" > /sys/class/gpio/gpio17/value
    echo "1" > /sys/class/gpio/gpio27/value
    sleep 0.2
    echo "0" > /sys/class/gpio/gpio27/value
    echo "1" > /sys/class/gpio/gpio23/value
    sleep 0.2
    echo "0" > /sys/class/gpio/gpio23/value
done
EOF
chmod +x /usr/local/bin/rgb

# SSH Config
echo "TCPKeepAlive yes" >> /etc/ssh/sshd_config
touch /boot/ssh
touch /boot/refresh-ssh-certs
rm -vf /home/pi/.ssh/*
sed -i s/PasswordAuthentication\ no/PasswordAuthentication\ yes/ /etc/ssh/sshd_config

curl --connect-timeout 10 --retry 5 --retry-delay 3 -L https://get.k3s.io | INSTALL_K3S_CHANNEL=stable INSTALL_K3S_EXEC="server --cluster-cidr=172.30.0.0/16 --service-cidr=172.31.0.0/16 --disable=traefik --kubelet-arg container-log-max-files=3 --kubelet-arg container-log-max-size=10Mi --disable-network-policy" sh
until kubectl -n kube-system get pod -l k8s-app="kube-dns" -o=jsonpath='{.items[0].metadata.name}' >/dev/null 2>&1; do
  echo "Waiting for pod"
  sleep 1
done
kubectl -n kube-system wait --for=condition=ready --timeout=180s pod -l k8s-app=kube-dns
kubectl -n kube-system wait --for=condition=ready --timeout=180s pod -l k8s-app=metrics-server
k3s ctr i pull docker.io/kubesail/agent:v0.73.0
/usr/local/bin/k3s-killall.sh
rm -rfv /var/lib/rancher/k3s/server
rm -rfv /var/lib/rancher/k3s/agent/client*
rm -rfv /var/lib/rancher/k3s/agent/etc
rm -rfv /var/lib/rancher/k3s/agent/*.kubeconfig
rm -rfv /var/lib/rancher/k3s/agent/pod-manifests/
rm -rfv /var/lib/rancher/k3s/agent/*.crt
rm -rfv /var/lib/rancher/k3s/agent/*.key
rm -rfv /etc/rancher/k3s/k3s.yaml

echo '' > /var/log/lastlog
echo '' > /var/log/kern.log
echo '' > /var/log/syslog
echo '' > /var/log/user.log
echo '' > /var/log/faillog
echo '' > /var/log/messages
echo '' > /var/log/auth.log

# Clean bash history
history -c && history -w
exit
