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

# Install PiBox first boot script
cat <<'EOF' > /opt/kubesail/pibox-first-boot.sh
#!/bin/bash
PATH_GITHUB_USERNAME=/boot/github-ssh-username.txt
PATH_REFRESH_SSH_CERTS=/boot/refresh-ssh-certs
PATH_REFRESH_K3S_CERTS=/boot/refresh-k3s-certs

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

if [[ -f $PATH_REFRESH_K3S_CERTS ]]; then
    echo "Generating new K3s certs"

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

    k3s kubectl --insecure-skip-tls-verify -n kube-system delete secret k3s-serving
    service k3s stop
    rm -vrf /var/lib/rancher/k3s/agent/*.key \
        /var/lib/rancher/k3s/agent/*.crt \
        /etc/rancher/k3s/k3s.yaml \
        /var/lib/rancher/k3s/server/tls
    service k3s start
    rm $PATH_REFRESH_K3S_CERTS

    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.7.1/cert-manager.yaml
    # TODO install kubesail agent with initial (non-authed) config
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
