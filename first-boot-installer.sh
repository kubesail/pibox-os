#!/bin/bash

mkdir -p /opt/pibox/

# Install service script
cat <<'EOF' > /opt/pibox/first-boot.sh
#!/bin/bash
PATH_GITHUB_USERNAME=/boot/github-ssh-username.txt
PATH_SSH_CERTS=/boot/refresh-ssh-certs
PATH_MICROK8S_CERTS=/boot/refresh-microk8s-certs

GITHUB_USERNAME=$(cat $PATH_GITHUB_USERNAME)
if [[ -n "$GITHUB_USERNAME" ]]; then
    echo "Installing public SSH keys for GitHub user: $GITHUB_USERNAME"
    curl https://github.com/${GITHUB_USERNAME}.keys > ~/.ssh/authorized_keys
    sed -i -e s/#PasswordAuthentication\ yes/PasswordAuthentication\ no/g /etc/ssh/sshd_config
    rm $PATH_GITHUB_USERNAME
  else
    echo "Skipping GitHub SSH key installation, $PATH_GITHUB_USERNAME does not exist or is blank"
fi

if [[ -f $PATH_SSH_CERTS ]]; then
    echo "Generating new SSH host certs"
    rm /etc/ssh/ssh_host_*
    dpkg-reconfigure openssh-server
    rm $PATH_SSH_CERTS
fi

if [[ -f $PATH_MICROK8S_CERTS ]]; then
    echo "Generating new MicroK8s certs"
    microk8s.refresh-certs
    rm $PATH_MICROK8S_CERTS
fi
EOF

chmod +x /opt/pibox/first-boot.sh

# Install service
cat <<'EOF' > /etc/systemd/system/pibox-first-boot.service
[Unit]
After=network.service
[Service]
ExecStart=/opt/pibox/first-boot.sh
[Install]
WantedBy=default.target
EOF

systemctl daemon-reload
systemctl enable pibox-first-boot.service
systemctl start pibox-first-boot.service
