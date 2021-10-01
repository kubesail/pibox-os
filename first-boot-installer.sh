#!/bin/bash

mkdir -p /opt/pibox/

# Install service script
cat <<'EOF' > /opt/pibox/first-boot.sh
#!/bin/bash
PATH_FIRSTBOOT=/boot/pibox-first-boot
PATH_GITHUB_USERNAME=/boot/github-username.txt

if [[ ! -f $PATH_FIRSTBOOT ]]; then
    echo "Skipping first-boot script, $PATH_FIRSTBOOT file not found"
    exit 0
fi

echo "Updating apt registry"
apt update

GITHUB_USERNAME=$(cat $PATH_GITHUB_USERNAME)
if [[ -n "$GITHUB_USERNAME" ]]; then
    echo "Installing public SSH keys for GitHub user: $GITHUB_USERNAME"
    curl https://github.com/${GITHUB_USERNAME}.keys > ~/.ssh/authorized_keys
  else
    echo "Skipping GitHub SSH key installation, $PATH_GITHUB_USERNAME does not exist or is blank"
fi

echo "Generating new SSH host certs"
rm /etc/ssh/ssh_host_*
dpkg-reconfigure openssh-server

echo "Generating new MicroK8s certs"
microk8s.refresh-certs

rm $PATH_FIRSTBOOT
EOF

chmod +x /opt/pibox/init.sh

# Install service
cat <<'EOF' > /etc/systemd/system/pibox-first-boot.service
[Unit]
After=network.service
[Service]
ExecStart=/opt/pibox/init.sh
[Install]
WantedBy=default.target
EOF

systemctl daemon-reload
systemctl enable pibox-first-boot.service
systemctl start pibox-first-boot.service
