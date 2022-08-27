#!/bin/bash

useradd -u 989 --system --shell=/usr/sbin/nologin kubesail-agent
mkdir -p /opt/kubesail/
chown -R 989 /opt/kubesail/

# Install KubeSail Debug helper
curl -sLo /usr/local/bin/kubesail-support https://raw.githubusercontent.com/kubesail/pibox-os/main/kubesail-support.sh
chmod +x /usr/local/bin/kubesail-support

# Install PiBox first boot script
cat <<'EOF' > /opt/kubesail/pibox-first-boot.sh
#!/bin/bash
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

# Install K3s and KubeSail agent
if [[ ! -d /var/lib/rancher/k3s/data ]]; then
  echo "Installing k3s and KubeSail agent"
  curl --unix-socket /var/run/pibox/framebuffer.sock "http://localhost/text?content=Installing+k3s&background=000000&size=46&color=ffffff"
  service k3s start
  
  function kubernetes_failed_to_boot () {
    curl --unix-socket /var/run/pibox/framebuffer.sock "http://localhost/text?content=Failed+starting+k3s+services&background=000000&size=46&color=ff0000"
    kill $SCREEN_TIMER_PID
    exit 1
  }

  function screen_timer () {
    i=1
    while true
    do
      curl --unix-socket /var/run/pibox/framebuffer.sock "http://localhost/text?content=Waiting+for+k3s+services&background=000000&size=46&color=ffffff&y=100"
      curl --unix-socket /var/run/pibox/framebuffer.sock "http://localhost/text?content=${i}+sec&size=36&color=CCCCCC&y=200"

      sleep 1
      ((i=i+1))
    done
  }

  screen_timer &
  SCREEN_TIMER_PID=$!

  until kubectl -n kube-system get pod -l k8s-app="kube-dns" -o=jsonpath='{.items[0].metadata.name}' >/dev/null 2>&1; do
    echo "Waiting for pod"
    sleep 1
  done

  kubectl -n kube-system wait --for=condition=ready --timeout=180s pod -l k8s-app=kube-dns || kubernetes_failed_to_boot
  kubectl -n kube-system wait --for=condition=ready --timeout=180s pod -l k8s-app=metrics-server || kubernetes_failed_to_boot

  if [[ "$(kubectl -n kube-system get pods | sed 1d | egrep -v '(Completed|Running)')" != "" ]]; then
    kubernetes_failed_to_boot
  fi

  kill $SCREEN_TIMER_PID
  curl --unix-socket /var/run/pibox/framebuffer.sock "http://localhost/text?content=Installing+KubeSail+Agent&background=000000&size=46&color=ffffff"
  kubectl create -f https://api.kubesail.com/byoc
fi

EOF
chmod +x /opt/kubesail/pibox-first-boot.sh


# Install PiBox first boot service
cat <<'EOF' > /etc/systemd/system/pibox-first-boot.service
[Service]
Restart=on-failure
RestartSec=5
ExecStart=/opt/kubesail/pibox-first-boot.sh
[Unit]
After=network-online.target
Wants=network-online.target
Before=sshd.service
[Install]
WantedBy=default.target
EOF

systemctl daemon-reload
systemctl enable pibox-first-boot.service
