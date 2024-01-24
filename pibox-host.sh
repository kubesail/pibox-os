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

# Give sudoers NOPASSWD requirement (same as pi user)
sed -i 's/%sudo\tALL=(ALL:ALL) ALL/%sudo\tALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers
# Create root files directory (and mount it)
mkdir -p /files
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
  curl https://github.com/kubesail/pibox-host/releases/download/$PIBOX_HOST_VERSION/pibox-host-$PIBOX_HOST_VERSION.tar.gz \
    -o /opt/pibox-host/pibox-host-$PIBOX_HOST_VERSION.tar.gz
fi
tar -xzf /opt/pibox-host/pibox-host-$PIBOX_HOST_VERSION.tar.gz --directory=$TARGET_DIR
cp $TARGET_DIR/pibox-host.service /etc/systemd/system/pibox-host.service
sed -i "s/PIBOX_HOST_VERSION/$PIBOX_HOST_VERSION/g" /etc/systemd/system/pibox-host.service
systemctl daemon-reload
systemctl enable pibox-host.service

# Install framebuffer
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

# Disable SSH
systemctl stop ssh
systemctl disable ssh

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

# Clean bash history
history -c && history -w
exit

