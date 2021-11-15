#!/bin/bash

mkdir -p /opt/kubesail/

# Install service script
cat <<'EOF' > /opt/kubesail/init.sh
#!/bin/bash
if [[ ! -f /boot/kubesail-username.txt ]]; then
    echo "Not installing KubeSail agent: /boot/kubesail-username.txt file not found"
    exit 0
fi

KUBESAIL_USERNAME=$(cat /boot/kubesail-username.txt)
echo "Installing KubeSail agent with username: $KUBESAIL_USERNAME"

microk8s.kubectl get namespace kubesail-agent || {
    microk8s.kubectl create -f https://byoc.kubesail.com/$KUBESAIL_USERNAME.yaml?initialID=PiBox
}
EOF

chmod +x /opt/kubesail/init.sh

cat <<'EOF' > /usr/local/bin/kubesail
#!/bin/bash

if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    echo "Not running as root. Try re-running with sudo, e.g. $(tput bold)sudo kubesail init$(tput sgr0)"
    exit
fi

read -p "What is your KubeSail username? " KUBESAIL_USERNAME

if [ -z "$KUBESAIL_USERNAME" ]; then
    echo "Username is empty, not installing KubeSail."
    exit 1
fi

read -p "Do you want to install $(tput bold)${KUBESAIL_USERNAME}$(tput sgr0)'s public GitHub $KUBESAIL_USERNAME for SSH access? [Y/n] " GITHUB_SSH
GITHUB_SSH=${GITHUB_SSH:-Y}

echo $KUBESAIL_USERNAME > /boot/kubesail-username.txt

if [ $GITHUB_SSH = "Y" ]; then
    echo $KUBESAIL_USERNAME > /boot/github-ssh-username.txt
    echo "Installing GitHub Keys..."
    systemctl start pibox-first-boot.service
fi

echo "Installing KubeSail agent. Please wait..."

systemctl start kubesail-init.service
EOF

chmod +x /usr/local/bin/kubesail


# Install service
cat <<'EOF' > /etc/systemd/system/kubesail-init.service
[Unit]
After=network.service
After=snap.microk8s.daemon-apiserver
[Service]
ExecStart=/opt/kubesail/init.sh
[Install]
WantedBy=default.target
EOF

systemctl daemon-reload
systemctl enable kubesail-init.service
systemctl start kubesail-init.service
