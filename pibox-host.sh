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

curl -fsSL https://deb.nodesource.com/setup_20.x | bash - &&\

apt-get update -yqq
apt-get full-upgrade -yqq
apt-get autoremove -yqq
apt-get autoclean -yqq
apt-get install -yqq \
  vim lvm2 raspberrypi-kernel-headers samba samba-common-bin \
  tmate sysstat smartmontools git iptables cryptsetup whois \
  jq build-essential libcairo2-dev libpango1.0-dev \
  libjpeg-dev libgif-dev librsvg2-dev nodejs

# Install node version manager
npm i -g n

# Give sudoers NOPASSWD requirement (same as pi user)
sed -i 's/%sudo\tALL=(ALL:ALL) ALL/%sudo\tALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers
# Create root files directory (and mount it)
mkdir -p /pibox
mkdir -p /etc/pibox-host
groupadd sambagroup

# Download pibox-host backend
mkdir -p /opt/pibox-host
PIBOX_HOST_VERSION=$(curl -s "https://api.github.com/repos/kubesail/pibox-host/releases/latest" | jq -r '.tag_name')
TARGET_DIR=/opt/pibox-host/$PIBOX_HOST_VERSION
mkdir -p $TARGET_DIR
echo "Extracting tarball to $TARGET_DIR ... (this may take a while)"
if [ -f pibox-host-$PIBOX_HOST_VERSION.tar.gz ]; then
  echo "Using existing tarball"
else
  echo "Downloading tarball"
  curl -L https://github.com/kubesail/pibox-host/releases/download/$PIBOX_HOST_VERSION/pibox-host-$PIBOX_HOST_VERSION.tar.gz \
    -o /opt/pibox-host/pibox-host-$PIBOX_HOST_VERSION.tar.gz
fi
tar -xzf /opt/pibox-host/pibox-host-$PIBOX_HOST_VERSION.tar.gz --directory=$TARGET_DIR
cp $TARGET_DIR/pibox-host.service /etc/systemd/system/pibox-host.service
sed -i "s/PIBOX_HOST_VERSION/$PIBOX_HOST_VERSION/g" /etc/systemd/system/pibox-host.service
systemctl daemon-reload
systemctl enable pibox-host.service

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

# Enable SPI for Display
cat <<EOF >> /boot/config.txt
dtoverlay=spi0-1cs
dtoverlay=dwc2,dr_mode=host
hdmi_force_hotplug=1
dtparam=spi=on
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

echo '' > /var/log/lastlog
echo '' > /var/log/kern.log
echo '' > /var/log/syslog
echo '' > /var/log/user.log
echo '' > /var/log/faillog
echo '' > /var/log/messages
echo '' > /var/log/auth.log

rm -vf /home/pi/.ssh/*
sed -i s/#PasswordAuthentication\ yes/PasswordAuthentication\ no/ /etc/ssh/sshd_config
ssh-keygen -A
service ssh --full-restart

# Place PiBox support public key in for local debugging at factory
mkdir -p /root/.ssh
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCluY8xnwyrbfdxQebvawYI9qGvDqxsnKm8SYXKvJ8c0sO9dU3531dFHwkRLqdtiYQZl0xr+kuKSGGtFNJ1pUjJ+5t9tfwUZO3BL7DJkKYqUP4uuPg13Y1XFUsQw++IGW8pZNfcQjIDqYcaFd+Z0N7CCEVbHcBExaGYi/XaINl6EF+7aPSaymZrPXyzlVfFHbJlAN4+itWem4Ycm0oIu2Cw1YGXdap3RMrunjluYbHMWCJjpj1ipSpJsgyWq77+IX1Bom1pQypAZr1tu/lQyWFDtaJwcz3ZeSjqrTdFa5uxM4ppzVEgZEIQUKZmn/ETT9EWIsYugbhXKASdPdtx37ACpg0hkBZMBfffrOD9uhPjjhXhAzL3CCbGLqHdPj5SMtiBOJZ0+r8za0HK8NkTqpFNc9onKAtXXQr1Sajx4pd3tUPsyLDx4mROUxdOjRrO7xwmf4Ykxl7zy9a6W6NugJjupl4HF0tOm/P64gqSCjAZj0XpNDS+L8J2tVVVxqCpgYU=" > /root/.ssh/authorized_keys

# Clean bash history
history -c && history -w
exit

