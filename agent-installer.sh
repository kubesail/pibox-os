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
    #microk8s.refresh-certs
    microk8s.kubectl create -f https://byoc.kubesail.com/$KUBESAIL_USERNAME.yaml?initialID=PiBox
}
EOF

chmod +x /opt/kubesail/init.sh

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
