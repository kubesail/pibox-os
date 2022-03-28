#!/bin/bash

mkdir -p /opt/kubesail/

# Install KubeSail init script
cat <<'EOF' > /opt/kubesail/init.sh
#!/bin/bash
if [[ ! -f /boot/kubesail-username.txt ]]; then
    echo "Not installing KubeSail agent: /boot/kubesail-username.txt file not found"
    exit 0
fi

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
    echo "Timeout waiting for k3s apiserver to start"
    exit 1
fi

KUBESAIL_USERNAME=$(cat /boot/kubesail-username.txt)
echo "Installing KubeSail agent with username: $KUBESAIL_USERNAME"

k3s kubectl get namespace kubesail-agent || {
    k3s kubectl create -f https://byoc.kubesail.com/$KUBESAIL_USERNAME.yaml?initialID=PiBox
}
EOF
chmod +x /opt/kubesail/init.sh

# Install KubeSail CLI setup script
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

echo $KUBESAIL_USERNAME > /boot/kubesail-username.txt

read -p "Do you want to install your public GitHub keys for SSH access? NOTE: This will disable SSH password logins. [Y/n] " GITHUB_SSH
GITHUB_SSH=${GITHUB_SSH:-Y}

if [ $GITHUB_SSH = "Y" ]; then
    read -p "What is your GitHub username? [$KUBESAIL_USERNAME] " GITHUB_USERNAME
    GITHUB_USERNAME=${GITHUB_USERNAME:-$KUBESAIL_USERNAME}
    echo $GITHUB_USERNAME > /boot/github-ssh-username.txt
    echo "Installing GitHub Keys..."
    systemctl start pibox-first-boot.service
fi

echo "Installing KubeSail agent. Please wait..."

systemctl start kubesail-init.service
EOF
chmod +x /usr/local/bin/kubesail

# Install KubeSail Debug helper
cat <<'EOF' > /usr/local/bin/kubesail-support
#!/bin/bash

TMPFILE="$(mktemp)"
KUBESAIL_AGENT_KEY="$(sudo kubectl -n kubesail-agent get pods -o yaml | fgrep KUBESAIL_AGENT_KEY -A1 | tail -n1 | awk '{print $2}')"

if [ -f /etc/pibox-release ]; then
    echo -e "\n\nPiBox version ==============" >> ${TMPFILE}
    cat /etc/pibox-release >> ${TMPFILE}
fi
if [ -f /etc/os-release ]; then
    echo -e "\n\nOS version ==============" >> ${TMPFILE}
    cat /etc/os-release >> ${TMPFILE}
fi
echo -e "\n\nKernel ==============\n $(uname -a)" >> ${TMPFILE}
echo -e "\n\nkubectl version ==============" >> ${TMPFILE}
kubectl version >> ${TMPFILE}
echo -e "\n\nk3s check-config ==============" >> ${TMPFILE}
k3s check-config >> ${TMPFILE}
echo -e "\n\nkubectl get nodes ==============" >> ${TMPFILE}
kubectl get nodes >> ${TMPFILE}
echo -e "\n\nkubectl -n kube-system get pods ==============" >> ${TMPFILE}
kubectl -n kube-system get pods >> ${TMPFILE}
echo -e "\n\nkubectl -n kubesail-agent describe pods ==============" >> ${TMPFILE}
kubectl -n kubesail-agent describe pods >> ${TMPFILE}
echo -e "\n\nkubectl -n kubesail-agent logs -l app=kubesail-agent ==============" >> ${TMPFILE}
kubectl -n kubesail-agent logs -l app=kubesail-agent >> ${TMPFILE}
echo "Wrote logs to ${TMPFILE}"
gzip ${TMPFILE}
curl -s -H "Content-Type: application/json" -k -X POST --data-binary @${TMPFILE}.gz "https://192.168.100.162:4000/agent/upload-debug-logs/${KUBESAIL_AGENT_KEY}"
echo -e "\nUploaded logs to KubeSail-Support - thank you"

EOF
chmod +x /usr/local/bin/kubesail-support


# Install PiBox first boot script
cat <<'EOF' > /opt/kubesail/pibox-first-boot.sh
#!/bin/bash
PATH_GITHUB_USERNAME=/boot/github-ssh-username.txt
PATH_REFRESH_SSH_CERTS=/boot/refresh-ssh-certs

if [[ -f $PATH_GITHUB_USERNAME ]]; then
    set -e
    mkdir -p /home/pi/.ssh
    GITHUB_USERNAME=$(cat $PATH_GITHUB_USERNAME)
    echo "Installing public SSH keys for GitHub user: $GITHUB_USERNAME"
    curl -sS https://github.com/${GITHUB_USERNAME}.keys -o /tmp/authorized_keys.tmp
    mv /tmp/authorized_keys.tmp /home/pi/.ssh/authorized_keys
    curl https://github.com/${GITHUB_USERNAME}.keys > /home/pi/.ssh/authorized_keys
    sed -i -e s/#PasswordAuthentication\ yes/PasswordAuthentication\ no/g /etc/ssh/sshd_config
    rm $PATH_GITHUB_USERNAME
    chown -R pi:pi /home/pi/.ssh
    set +e
  else
    echo "Skipping GitHub SSH key installation, $PATH_GITHUB_USERNAME does not exist or is blank"
fi

if [[ -f $PATH_REFRESH_SSH_CERTS ]]; then
    echo "Generating new SSH host certs"
    rm /etc/ssh/ssh_host_*
    dpkg-reconfigure openssh-server
    rm $PATH_REFRESH_SSH_CERTS
fi


# Install K3s
if [[ ! -d /var/lib/rancher/k3s/data ]]; then
  curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable sh
fi

EOF
chmod +x /opt/kubesail/pibox-first-boot.sh

# Install KubeSail init service
cat <<'EOF' > /etc/systemd/system/kubesail-init.service
[Unit]
After=network.service
After=k3s.service
[Service]
ExecStart=/opt/kubesail/init.sh
[Install]
WantedBy=default.target
EOF


# Install PiBox first boot service
cat <<'EOF' > /etc/systemd/system/pibox-first-boot.service
[Unit]
After=network.service
[Service]
ExecStart=/opt/kubesail/pibox-first-boot.sh
[Install]
WantedBy=default.target
EOF

systemctl daemon-reload

systemctl enable pibox-first-boot.service
systemctl start pibox-first-boot.service
systemctl enable kubesail-init.service
systemctl start kubesail-init.service
